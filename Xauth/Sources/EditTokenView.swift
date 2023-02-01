//
//  EditTokenView.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

struct EditTokenReducer: ReducerProtocol {
  struct State: Equatable {
    let id: UUID
    var issuer: String
    var account: String

  }
  
  enum Action: Equatable {
    case cancel
    case textChangedIssuer(String)
    case textChangedAccount(String)
    case update(id: UUID, issuer: String, account: String)
  }
  
  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case let .textChangedIssuer(issuer):
      state.issuer = issuer
      return .none
    case let .textChangedAccount(account):
      state.account = account
      return .none
    default:
      return .none
    }
  }
}

extension EditTokenReducer.State {
  init(_ passcode: Passcode) {
    self.id      = passcode.id
    self.issuer  = passcode.issuer
    self.account = passcode.account
  }
}

struct EditTokenView: View {
  let store: StoreOf<EditTokenReducer>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      VStack {
        TextField("Issuer",  text: viewStore.binding(get: { $0.issuer },  send: EditTokenReducer.Action.textChangedIssuer))
        TextField("Account", text: viewStore.binding(get: { $0.account }, send: EditTokenReducer.Action.textChangedAccount))
        HStack {
          Button("Cancel") { viewStore.send(.cancel) }
            .keyboardShortcut(.cancelAction)
          Spacer()
          Button("Save") { viewStore.send(.update(id: viewStore.id, issuer: viewStore.issuer, account: viewStore.account)) }
            .keyboardShortcut(.defaultAction)
        }
      }
      .frame(maxWidth: 500)
      .padding()
    }
  }
}
