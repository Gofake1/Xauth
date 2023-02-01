//
//  AddTokenFormView.swift
//  Xauth
//
//  Created by David on 7/3/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

enum PasscodeType: Hashable {
  case hotp, totp
}

struct AddTokenFormReducer: ReducerProtocol {
  struct State: Equatable {
    var issuer:  String       = ""
    var account: String       = ""
    var key:     String       = ""
    var type:    PasscodeType = .totp
    
    var disabled: Bool {
      self.issuer.isEmpty || self.account.isEmpty || self.key.isEmpty
    }
  }
  
  enum Action: Equatable {
    case addToken(issuer: String, account: String, key: String, type: PasscodeType)
    case textChangedIssuer(String)
    case textChangedAccount(String)
    case textChangedKey(String)
    case changedType(PasscodeType)
  }
  
  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case let .textChangedIssuer(issuer):
      state.issuer = issuer
      return .none
    case let .textChangedAccount(account):
      state.account = account
      return .none
    case let .textChangedKey(key):
      state.key = key
      return .none
    case let .changedType(type):
      state.type = type
      return .none
    default:
      return .none
    }
  }
}

struct AddTokenFormView: View {
  let store: StoreOf<AddTokenFormReducer>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      VStack {
        TextField("Issuer",  text: viewStore.binding(get: { $0.issuer },  send: AddTokenFormReducer.Action.textChangedIssuer))
          .font(.headline)
        TextField("Account", text: viewStore.binding(get: { $0.account }, send: AddTokenFormReducer.Action.textChangedAccount))
          .font(.headline)
        TextField("Key",     text: viewStore.binding(get: { $0.key },     send: AddTokenFormReducer.Action.textChangedKey))
          .font(.headline)
        Picker("Type:", selection: viewStore.binding(get: { $0.type }, send: AddTokenFormReducer.Action.changedType)) {
          Text("TOTP").tag(PasscodeType.totp)
          Text("HOTP").tag(PasscodeType.hotp)
        }
        .pickerStyle(SegmentedPickerStyle())
        Button("Add Passcode") {
          viewStore.send(.addToken(issuer: viewStore.issuer, account: viewStore.account, key: viewStore.key, type: viewStore.type))
        }
        .disabled(viewStore.disabled)
      }
      .padding()
      .frame(minWidth: 250, alignment: .center)
    }
  }
}

#if DEBUG
struct AddPasscodeView_Previews: PreviewProvider {
  static var previews: some View {
    AddTokenFormView(
      store: Store(
        initialState: .init(issuer: "GitHub", account: "david@gofake1.net", key: "23456"),
        reducer:      AddTokenFormReducer()
      )
    )
  }
}
#endif
