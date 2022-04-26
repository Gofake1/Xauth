//
//  PasscodeList.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

enum PasscodeListAction: Equatable {
  case delete(IndexSet)
  case move(source: IndexSet, destination: Int)
  case passcode(id: UUID, action: PasscodeAction)
}

struct PasscodeListEnvironment {
  let keychain:     KeychainPersisting
  let keychainRefs: UserDefaultsArrayPersisting<Data>
  let otpList:      OTPList
}

struct Deletion: Equatable {
  let id:               UUID
  let offsetForOTPList: Int
}

let passcodeListReducer = Reducer<AppState, PasscodeListAction, PasscodeListEnvironment> { state, action, environment in
  switch action {
  case let .delete(indices): // Triggered by table item's built-in delete button
    state.alert = .init(
      title:           .init("Delete"),
      message:         .init("This action cannot be undone."),
      primaryButton:   .destructive(.init("Confirm"), action: .send(.alertConfirm)),
      secondaryButton: .cancel(.init("Cancel"))
    )
    state.deletions = indices.map {
      let id = state.passcodes[$0].id
      return .init(
        id:               id,
        offsetForOTPList: environment.otpList.ids.firstIndex(where: { $0.0 == id })!
      )
    }
    return .none
    
  case let .move(source, destination):
    environment.otpList.move(fromOffsets: source, toOffset: destination)
    state.passcodes = .init(uniqueElements: environment.otpList.passcodes)
    environment.keychainRefs.set(environment.otpList.keychainRefs)
    return .none
    
  case let .passcode(id, .incrementCounterAction):
    environment.otpList.update(hotp: id)
    state.passcodes = .init(uniqueElements: environment.otpList.passcodes)
    return .none
    
  case let .passcode(id, .deleteAction): // Triggered by table item's secondary menu item
    state.alert = .init(
      title:           .init("Delete"),
      message:         .init("This action cannot be undone."),
      primaryButton:   .destructive(.init("Confirm"), action: .send(.alertConfirm)),
      secondaryButton: .cancel(.init("Cancel"))
    )
    state.deletions = [
      .init(
        id:               id,
        offsetForOTPList: environment.otpList.ids.firstIndex(where: { $0.0 == id })!
      )
    ]
    return .none
    
  case let .passcode(id, .editAction):
    state.editToken = state.passcodes[id: id].flatMap(EditTokenState.init)
    return .none
    
  case .passcode: // copyAction is handled in Passcode
    return .none
  }
}

struct PasscodeListView: View {
  let store: Store<AppState, PasscodeListAction>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      List {
        ForEachStore(
          self.store.scope(state: { $0.passcodes }, action: PasscodeListAction.passcode),
          content: PasscodeView.init
        )
        .onMove(perform: { viewStore.send(.move(source: $0, destination: $1)) })
        .onDelete(perform: { viewStore.send(.delete($0)) })
      }
    }
  }
}
