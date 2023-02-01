//
//  PasscodeView.swift
//  Xauth
//
//  Created by David on 7/2/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

struct PasscodeReducer: ReducerProtocol {
  typealias State = Passcode
  
  enum Action: Equatable {
    case incrementCounterAction
    case copyAction
    case deleteAction
    case editAction
  }
  
  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .copyAction:
      let pasteboard = NSPasteboard.general
      pasteboard.declareTypes([.string], owner: nil)
      pasteboard.setString(state.text, forType: .string)
      return .none
    default:
      return .none
    }
  }
}

struct PasscodeView: View {
  let store: StoreOf<PasscodeReducer>
  
  var body: some View {
    WithViewStore(self.store) { viewStore in
      HStack {
        Spacer()
        VStack(spacing: 0) {
          HStack {
            Text(viewStore.issuer).font(.headline)
            Text(viewStore.account).font(.headline).foregroundColor(.secondary)
          }
          Text(viewStore.text).font(Font.system(.largeTitle).monospacedDigit())
            .background(GeometryReader { geometry in
              if viewStore.isCounter {
                Button(action: { viewStore.send(.incrementCounterAction) }) {
                  Image(systemName: "plus.circle")
                }
                .buttonStyle(PlainButtonStyle())
                .position(x: geometry.size.width + 20, y: geometry.size.height/2)
              }
            })
        }
        Spacer()
      }
      .contextMenu {
        Button("Copy") { viewStore.send(.copyAction) }
        Button("Edit") { viewStore.send(.editAction) }
        Divider()
        Button("Delete") { viewStore.send(.deleteAction) }
      }
    }
  }
}

#if DEBUG
struct PasscodeView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      PasscodeView(
        store: .init(
          initialState: .init(id: UUID(), issuer: "GitHub", account: "david@gofake1.net", text: "000000", isCounter: false),
          reducer:      PasscodeReducer()
        )
      )
      PasscodeView(
        store: .init(
          initialState: .init(id: UUID(), issuer: "GitHub", account: "david@gofake1.net", text: "111111", isCounter: true),
          reducer:      PasscodeReducer()
        )
      )
    }
  }
}
#endif
