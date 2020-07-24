//
//  EditToken.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

struct EditTokenState: Equatable {
  let id: UUID
  var issuer: String
  var account: String
}

extension EditTokenState {
  init(_ passcode: Passcode) {
    self.id      = passcode.id
    self.issuer  = passcode.issuer
    self.account = passcode.account
  }
}

enum EditTokenAction: Equatable {
  case cancel
  case textChangedIssuer(String)
  case textChangedAccount(String)
  case update(id: UUID, issuer: String, account: String)
}

let editTokenReducer: Reducer<EditTokenState, EditTokenAction, Void> = .init { state, action, _ in
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

struct EditTokenView: View {
  let store: Store<EditTokenState, EditTokenAction>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      VStack {
        TextField("Issuer",  text: viewStore.binding(get: { $0.issuer },  send: EditTokenAction.textChangedIssuer))
        TextField("Account", text: viewStore.binding(get: { $0.account }, send: EditTokenAction.textChangedAccount))
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
