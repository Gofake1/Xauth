//
//  App.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

struct AppState: Equatable {
  var passcodes:    IdentifiedArrayOf<Passcode> = []
  var addTokenForm: AddTokenFormState?
  var editToken:    EditTokenState?
  var qrScan:       QRScanState?
  var alert:        AlertState<AppAction>?
  var deletions:    [Deletion]?
}

enum AppAction: Equatable {
  case setup
  case updateTime(Date)
  case updateFilterText(String)
  case showAddTokenForm
  case showQRScan
  case alertCancel
  case alertConfirm
  case closeWindow(WindowID)
  case editToken(EditTokenAction)
  case newToken(NewTokenAction)
  case passcodeList(PasscodeListAction)
}

enum NewTokenAction: Equatable {
  case addTokenForm(AddTokenFormAction)
  case qrScan(QRScanAction)
}

struct AppEnvironment {
  let keychain:     KeychainPersisting
  let keychainRefs: UserDefaultsArrayPersisting<Data>
  let logging:      Logging
  let makeUUID:     () -> UUID
  let otpFactory:   OTPFactory
  let otpList:      OTPList
  let qrScan:       () -> String?
  let tokenCoding:  TokenCoding<String>
}

enum WindowID: Equatable {
  case addTokenForm, qrScan
}

infix operator ..

let appReducer: Reducer<AppState, AppAction, AppEnvironment> = Reducer.combine(
  passcodeReducer.forEach(
    state:       \.passcodes,
    action:      /AppAction.passcodeList .. PasscodeListAction.passcode,
    environment: { _ in }
  ),
  passcodeListReducer.pullback(
    state:       \.self,
    action:      /AppAction.passcodeList,
    environment: { .init(keychain: $0.keychain, keychainRefs: $0.keychainRefs, otpList: $0.otpList) }
  ),
  addTokenFormReducer.optional.pullback(
    state:       \.addTokenForm,
    action:      /AppAction.newToken .. NewTokenAction.addTokenForm,
    environment: { _ in }
  ),
  editTokenReducer.optional.pullback(
    state:       \.editToken,
    action:      /AppAction.editToken,
    environment: { _ in }
  ),
  qrScanReducer.optional.pullback(
    state:       \.qrScan,
    action:      /AppAction.newToken .. NewTokenAction.qrScan,
    environment: {
      .init(
        keychain:     $0.keychain,
        keychainRefs: $0.keychainRefs,
        makeUUID:     $0.makeUUID,
        otpFactory:   $0.otpFactory,
        scan:         $0.qrScan,
        tokenCoding:  $0.tokenCoding
      )
    }
  ),
  Reducer { state, action, environment in
    switch action {
    case .setup:
      let makeOTP: (Data) -> Validated<OTP, Error> = {
        environment.otpFactory.fromKeychain(
          keychainRef: $0,
          id:          environment.makeUUID(),
          tokenCoding: environment.tokenCoding,
          keychain:    environment.keychain
        )
      }
      let validatedArray = environment.keychainRefs.get().flatMap { .valid($0.map(makeOTP)) }
      
      switch validatedArray {
      case let .valid(otps):
        environment.otpList.add(otps: otps.compactMap(\.valid))
        otps.compactMap(\.invalid).forEach(environment.logging.log)
      case let .invalid(errors):
        environment.logging.log(errors: errors)
      }
      return .none
      
    case let .updateTime(date):
      environment.otpList.update(date: date)
      state.passcodes = .init(environment.otpList.passcodes)
      return .none
      
    case let .updateFilterText(filterText):
      environment.otpList.filterText = filterText
      state.passcodes = .init(environment.otpList.passcodes)
      return .none
      
    case .showAddTokenForm:
      state.addTokenForm = .init()
      state.qrScan = nil
      return .none
      
    case .showQRScan:
      state.qrScan = .init()
      state.addTokenForm = nil
      return .none
      
    case .alertCancel:
      state.alert = nil
      return .none
      
    case .alertConfirm:
      if let deletions = state.deletions {
        deletions
          .compactMap { environment.otpList.otp(id: $0.id)?.keychainRef }
          .forEach {
            switch environment.keychain.delete($0) {
            case .valid:
              break
            case let .invalid(errors):
              environment.logging.log(errors: errors)
            }
          }
        environment.otpList.remove(atOffsets: IndexSet(deletions.map { $0.offsetForOTPList }))
        state.passcodes = .init(environment.otpList.passcodes)
        environment.keychainRefs.set(environment.otpList.keychainRefs)
        state.alert     = nil
        state.deletions = nil
      }
      return .none
      
    case let .closeWindow(id):
      switch id {
      case .addTokenForm: state.addTokenForm = nil
      case .qrScan:       state.qrScan       = nil
      }
      return .none
      
    case .editToken(.cancel):
      state.editToken = nil
      return .none
      
    case let .editToken(.update(id, issuer, account)):
      let otp = environment.otpList.otp(id: id)!
      let newToken = Token(
        type:      otp.token.type,
        key:       otp.token.key,
        algorithm: otp.token.algorithm,
        digits:    otp.token.digits,
        issuer:    issuer,
        account:   account
      )
      let validatedNewKeychainRef = environment.tokenCoding.encode(newToken)
        .flatMap { environment.keychain.update(otp.keychainRef, account, issuer, $0) }
      
      switch validatedNewKeychainRef {
      case let .valid(newKeychainRef):
        let newOTP = OTP(id: id, keychainRef: newKeychainRef, token: newToken)
        environment.otpList.update(otp: newOTP)
        state.passcodes = .init(environment.otpList.passcodes)
        environment.keychainRefs.set(environment.otpList.keychainRefs)
        state.editToken = nil
      case let .invalid(errors):
        environment.logging.log(errors: errors)
      }
      return .none
      
    case let .newToken(.addTokenForm(.addToken(issuer, account, key, type))):
      let type: Token.`Type` = {
        switch type {
        case .hotp: return .hotp(0)
        case .totp: return .totp(30)
        }
      }()
      let validatedOTP = environment.otpFactory.addToKeychain(
        issuer:      issuer,
        account:     account,
        key:         key,
        type:        type,
        algorithm:   .sha1,
        digits:      6,
        id:          environment.makeUUID(),
        tokenCoding: environment.tokenCoding,
        keychain:    environment.keychain
      )

      switch validatedOTP {
      case let .valid(otp):
        environment.otpList.add(otps: [otp])
        state.passcodes = .init(environment.otpList.passcodes)
        environment.keychainRefs.set(environment.otpList.keychainRefs)
        state.addTokenForm = nil
      case let .invalid(errors):
        environment.logging.log(errors: errors)
      }
      return .none
      
    case let .newToken(.qrScan(.succeeded(otp))):
      environment.otpList.add(otps: [otp])
      state.passcodes = .init(environment.otpList.passcodes)
      environment.keychainRefs.set(environment.otpList.keychainRefs)
      state.qrScan = nil
      return .none
      
    default:
      return .none
    }
  }
)
.debug()

struct AppView: View {
  let store: Store<AppState, AppAction>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      viewStore.passcodes.isEmpty
        ? AnyView(NoPasscodesView())
        : AnyView(
            PasscodeListView(store: self.store.scope(state: { $0 }, action: AppAction.passcodeList))
              .sheet(isPresented: .init(get: { viewStore.editToken != nil }, set: { _ in })) {
                IfLetStore(
                  self.store.scope(state: { $0.editToken }, action: AppAction.editToken),
                  then: EditTokenView.init,
                  else: Text("Whoops")
                )
              }
              .alert(self.store.scope(state: \.alert), dismiss: .alertCancel)
          )
    }
  }
}

struct NoPasscodesView: View {
  var body: some View {
    HStack {
      Spacer()
      VStack {
        Spacer()
        Text("No passcodes").font(.headline).frame(minWidth: 250, minHeight: 120, alignment: .center)
        Spacer()
      }
      Spacer()
    }
  }
}
