//
//  AppView.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

struct AppReducer: ReducerProtocol {
  struct State: Equatable {
    var passcodes:    IdentifiedArrayOf<PasscodeReducer.State> = []
    var addTokenForm: AddTokenFormReducer.State?
    var editToken:    EditTokenReducer.State?
    var qrScan:       QRScanReducer.State?
    var alert:        AlertState<Action>?
    var deletions:    [Deletion]?
  }
  
  enum Action: Equatable {
    case setup
    case updateTime(Date)
    case updateFilterText(String)
    case showQRScan
    case alertCancel
    case alertConfirm
    case closeWindow(WindowID)
    case editToken(EditTokenReducer.Action)
    case newToken(NewTokenAction)
    case passcodeList(PasscodeListReducer.Action)
  }
  
  @Dependency(\.appModel) var appModel
  @Dependency(\.keychainPersisting) var keychain
  @Dependency(\.keychainRefs) var keychainRefs
  @Dependency(\.log) var log
  @Dependency(\.tokenCoding) var tokenCoding
  @Dependency(\.uuid) var makeUUID
  
  var body: some ReducerProtocol<State, Action> {
    Scope(state: \.self, action: /Action.passcodeList) {
      PasscodeListReducer()
    }
    Reduce { state, action in
      switch action {
      case .setup:
        let makeOTP: (Data) -> Validated<OTP, Error> = {
          OTPFactory.fromKeychain(
            keychainRef: $0,
            id:          self.makeUUID(),
            tokenCoding: self.tokenCoding,
            keychain:    self.keychain
          )
        }
        let validatedArray = self.keychainRefs.get().flatMap { .valid($0.map(makeOTP)) }
        
        switch validatedArray {
        case let .valid(otps):
          self.appModel.add(otps: otps.compactMap(\.valid))
          otps.compactMap(\.invalid).forEach(self.log.callAsFunction(errors:))
        case let .invalid(errors):
          self.log(errors: errors)
        }
        return .none
        
      case let .updateTime(date):
        self.appModel.update(date: date)
        state.passcodes = .init(uniqueElements: self.appModel.passcodes)
        return .none
        
      case let .updateFilterText(filterText):
        self.appModel.filterText = filterText
        state.passcodes = .init(uniqueElements: self.appModel.passcodes)
        return .none
        
      case .showQRScan:
        state.qrScan = .init()
        state.addTokenForm = nil
        return .none
        
      case .alertCancel:
        state.alert = nil
        return .none
        
      case .alertConfirm:
        guard let deletions = state.deletions else { return .none }
        deletions
          .compactMap { self.appModel.otp(id: $0.id)?.keychainRef }
          .forEach {
            switch self.keychain.delete($0) {
            case .valid:
              break
            case let .invalid(errors):
              self.log(errors: errors)
            }
          }
        self.appModel.remove(atOffsets: IndexSet(deletions.map { $0.offsetForOTPList }))
        state.passcodes = .init(uniqueElements: self.appModel.passcodes)
        self.keychainRefs.set(self.appModel.keychainRefs)
        state.alert     = nil
        state.deletions = nil
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
        let otp = self.appModel.otp(id: id)!
        let newToken = Token(
          type:      otp.token.type,
          key:       otp.token.key,
          algorithm: otp.token.algorithm,
          digits:    otp.token.digits,
          issuer:    issuer,
          account:   account
        )
        let validatedNewKeychainRef = self.tokenCoding.encode(newToken)
          .flatMap { self.keychain.update(otp.keychainRef, account, issuer, $0) }
        
        switch validatedNewKeychainRef {
        case let .valid(newKeychainRef):
          let newOTP = OTP(id: id, keychainRef: newKeychainRef, token: newToken)
          self.appModel.update(otp: newOTP)
          state.passcodes = .init(uniqueElements: self.appModel.passcodes)
          self.keychainRefs.set(self.appModel.keychainRefs)
          state.editToken = nil
        case let .invalid(errors):
          self.log(errors: errors)
        }
        return .none
        
      case let .newToken(.addTokenForm(.addToken(issuer, account, key, type))):
        let type: Token.`Type` = {
          switch type {
          case .hotp: return .hotp(0)
          case .totp: return .totp(30)
          }
        }()
        let validatedOTP = OTPFactory.addToKeychain(
          issuer:      issuer,
          account:     account,
          key:         key,
          type:        type,
          algorithm:   .sha1,
          digits:      6,
          id:          self.makeUUID(),
          tokenCoding: self.tokenCoding,
          keychain:    self.keychain
        )
        
        switch validatedOTP {
        case let .valid(otp):
          self.appModel.add(otps: [otp])
          state.passcodes = .init(uniqueElements: self.appModel.passcodes)
          self.keychainRefs.set(self.appModel.keychainRefs)
          state.addTokenForm = nil
        case let .invalid(errors):
          self.log(errors: errors)
        }
        return .none
      
      case .newToken(.qrScan(.customizeButtonPressed)):
        state.addTokenForm = .init()
        state.qrScan = nil
        return .none
        
      case let .newToken(.qrScan(.succeeded(otp))):
        self.appModel.add(otps: [otp])
        state.passcodes = .init(uniqueElements: self.appModel.passcodes)
        self.keychainRefs.set(self.appModel.keychainRefs)
        state.qrScan = nil
        return .none
        
      default:
        return .none
      }
    }
      .ifLet(\.addTokenForm, action: /Action.newToken .. NewTokenAction.addTokenForm) {
        AddTokenFormReducer()
      }
      .ifLet(\.editToken, action: /Action.editToken) {
        EditTokenReducer()
      }
      .ifLet(\.qrScan, action: /Action.newToken .. NewTokenAction.qrScan) {
        QRScanReducer()
      }
      .forEach(\.passcodes, action: /Action.passcodeList .. PasscodeListReducer.Action.passcode) {
        PasscodeReducer()
      }
    #if DEBUG
      ._printChanges()
    #endif
  }
}

enum NewTokenAction: Equatable {
  case addTokenForm(AddTokenFormReducer.Action)
  case qrScan(QRScanReducer.Action)
}

enum WindowID: Equatable {
  case addTokenForm, qrScan
}

struct AppView: View {
  let store: StoreOf<AppReducer>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      if viewStore.passcodes.isEmpty {
        NoPasscodesView()
      } else {
        PasscodeListView(store: self.store.scope(state: { $0 }, action: AppReducer.Action.passcodeList))
          .sheet(isPresented: .init(get: { viewStore.editToken != nil }, set: { _ in })) {
            IfLetStore(self.store.scope(state: { $0.editToken }, action: AppReducer.Action.editToken), then: EditTokenView.init)
          }
          .alert(self.store.scope(state: \.alert), dismiss: .alertCancel)
      }
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
