//
//  QRScanView.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

struct QRScanReducer: ReducerProtocol {
  struct State: Equatable {}
  
  enum Action: Equatable {
    case scanButtonPressed
    case customizeButtonPressed
    case succeeded(OTP)
  }
  
  @Dependency(\.keychainPersisting) var keychain
  @Dependency(\.log) var log
  @Dependency(\.scanQR) var scan
  @Dependency(\.tokenCoding) var tokenCoding
  @Dependency(\.uuid) var makeUUID
  
  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    // Test: https://rootprojects.org/authenticator/
    case .scanButtonPressed:
      do {
        guard let url = try self.scan() else {
          log("Did not scan valid QR code")
          return .none
        }
        let validatedOTP = OTPFactory.addToKeychain(
          url:         url,
          id:          self.makeUUID(),
          tokenCoding: self.tokenCoding,
          keychain:    self.keychain
        )
        
        switch validatedOTP {
        case let .valid(otp):
          return Effect(value: .succeeded(otp))
        case let .invalid(errors):
          log(errors: errors)
          return .none
        }
      } catch {
        log("\(error)")
        return .none
      }
      
    default:
      return .none
    }
  }
}

struct QRScanView: View {
  let store: StoreOf<QRScanReducer>
  
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
          Button("Scan") { viewStore.send(.scanButtonPressed) }
          Spacer()
          Button("Customize") { viewStore.send(.customizeButtonPressed) }
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
        reducer:      QRScanReducer()
      )
    )
    .frame(width: 400, height: 300)
  }
}
#endif
