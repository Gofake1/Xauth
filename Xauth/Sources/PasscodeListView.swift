//
//  PasscodeListView.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

struct PasscodeListReducer: ReducerProtocol {
  typealias State = AppReducer.State
  
  enum Action: Equatable {
    case delete(IndexSet)
    case move(source: IndexSet, destination: Int)
    case passcode(id: UUID, action: PasscodeReducer.Action)
  }
  
  @Dependency(\.appModel) var appModel
  @Dependency(\.keychainRefs) var keychainRefs
  
  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
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
          offsetForOTPList: self.appModel.ids.firstIndex(where: { $0.0 == id })!
        )
      }
      return .none
      
    case let .move(source, destination):
      self.appModel.move(fromOffsets: source, toOffset: destination)
      state.passcodes = .init(uniqueElements: self.appModel.passcodes)
      self.keychainRefs.set(self.appModel.keychainRefs)
      return .none
      
    case let .passcode(id, .incrementCounterAction):
      self.appModel.update(hotp: id)
      state.passcodes = .init(uniqueElements: self.appModel.passcodes)
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
          offsetForOTPList: self.appModel.ids.firstIndex(where: { $0.0 == id })!
        )
      ]
      return .none
      
    case let .passcode(id, .editAction):
      state.editToken = state.passcodes[id: id].flatMap(EditTokenReducer.State.init)
      return .none
      
    case .passcode: // copyAction is handled in PasscodeReducer
      return .none
    }
  }
}

struct Deletion: Equatable {
  let id:               UUID
  let offsetForOTPList: Int
}

struct PasscodeListView: View {
  let store: StoreOf<PasscodeListReducer>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      List {
        ForEachStore(
          self.store.scope(state: { $0.passcodes }, action: PasscodeListReducer.Action.passcode),
          content: PasscodeView.init
        )
        .onMove(perform: { viewStore.send(.move(source: $0, destination: $1)) })
        .onDelete(perform: { viewStore.send(.delete($0)) })
      }
    }
  }
}
