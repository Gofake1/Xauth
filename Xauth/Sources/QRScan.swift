//
//  QRScan.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

struct QRScanState: Equatable {}

enum QRScanAction: Equatable {
  case buttonPressed
  case succeeded(OTP)
}

struct QRScanEnvironment {
  let keychain:     KeychainPersisting
  let keychainRefs: UserDefaultsArrayPersisting<Data>
  let makeUUID:     () -> UUID
  let otpFactory:   OTPFactory
  let scan:         () -> String?
  let tokenCoding:  TokenCoding<String>
}

let qrScanReducer: Reducer<QRScanState, QRScanAction, QRScanEnvironment> = Reducer { _, action, environment in
  switch action {
  // Test: https://rootprojects.org/authenticator/
  case .buttonPressed:
    guard let url = environment.scan() else {
      return .none //*
    }
    let validatedOTP = environment.otpFactory.addToKeychain(
      url:         url,
      id:          environment.makeUUID(),
      tokenCoding: environment.tokenCoding,
      keychain:    environment.keychain
    )
    
    switch validatedOTP {
    case let .valid(otp):
      return Effect(value: .succeeded(otp)) // TODO: close window
    case let .invalid(errors):
      print(errors) //*
      return .none
    }
    
  default:
    return .none
  }
}

struct QRScanView: View {
  let store: Store<QRScanState, AppAction>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      VStack(spacing: 0) {
        Rectangle().fill(Color(white: 0, opacity: 0.5)).frame(height: 20)
        HStack {
          Rectangle().fill(Color(white: 0, opacity: 0.5)).frame(width: 20)
          Spacer()
          Rectangle().fill(Color(white: 0, opacity: 0.5)).frame(width: 20)
        }
        HStack {
          Button("Scan") { viewStore.send(.newToken(.qrScan(.buttonPressed))) }
          Spacer()
          Button("Customize") { viewStore.send(.showAddTokenForm) }
        }
        .padding()
        .background(Color(white: 0, opacity: 0.5))
      }
      .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
    }
  }
}

#if DEBUG
struct QRScanView_Previews: PreviewProvider {
  static var previews: some View {
    QRScanView(
      store: .init(
        initialState: .init(),
        reducer:      Reducer<QRScanState, AppAction, Void>.empty,
        environment:  ()
      )
    )
    .frame(width: 400, height: 300)
  }
}
#endif
