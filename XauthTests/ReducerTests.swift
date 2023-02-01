//
//  ReducerTests.swift
//  XauthTests
//
//  Created by David on 7/10/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import ComposableArchitecture
import XCTest

class ReducerTests: XCTestCase {
  func testAddToken() {
    let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    var didWriteToKeychain = false
    var didWriteToKeychainRefs = false
    let store = TestStore(
      initialState: AppReducer.State(),
      reducer:      AppReducer()
    ) { dependencies in
      dependencies.uuid = .constant(uuid)
      dependencies.keychainPersisting = .mock(create: { _, _, _ in didWriteToKeychain = true; return .valid(Data()) })
      dependencies.keychainRefs = .mock(set: { _ in didWriteToKeychainRefs = true })
      withDependencies { // AppModel's dependencies are not derived from the TestStore's
        $0.date = .constant(Date(timeIntervalSince1970: 0))
      } operation: {
        dependencies.appModel = AppModel()
      }
    }
    
    store.send(.showQRScan) {
      $0.qrScan = .init()
    }
    store.send(.newToken(.qrScan(.customizeButtonPressed))) {
      $0.qrScan = nil
      $0.addTokenForm = .init()
    }
    store.send(.newToken(.addTokenForm(.addToken(issuer: "GitHub", account: "david@gofake1.net", key: "23456", type: .totp)))) {
      $0.passcodes = [.init(id: uuid, issuer: "GitHub", account: "david@gofake1.net", text: "158781", isCounter: false)]
      $0.addTokenForm = nil
    }
    XCTAssertTrue(didWriteToKeychain)
    XCTAssertTrue(didWriteToKeychainRefs)
    XCTAssertEqual(store.dependencies.appModel.ids[0].0, uuid)
    XCTAssertEqual(store.dependencies.appModel.hotps.count, 0)
    XCTAssertEqual(store.dependencies.appModel.totps.count, 1)
  }
  
  func testEditToken() {
    let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    var didWriteToKeychain = false
    var didWriteToKeychainRefs = false
    let store = TestStore(
      initialState: AppReducer.State(passcodes: [.init(id: uuid, issuer: "GitHub", account: "david@gofake1.net", text: "", isCounter: false)]),
      reducer:      AppReducer()
    ) { dependencies in
      dependencies.keychainPersisting = .mock(update: { _, _, _, _ in didWriteToKeychain = true; return .valid(Data()) })
      dependencies.keychainRefs = .mock(set: { _ in didWriteToKeychainRefs = true })
      withDependencies {
        $0.date = .constant(Date(timeIntervalSince1970: 0))
      } operation: {
        dependencies.appModel = AppModel()
        dependencies.appModel.add(
          totp: TOTP(
            otp: OTP(
              id:          uuid,
              keychainRef: Data(),
              token:       .init(
                type:      .totp(30),
                key:       .init(data: []),
                algorithm: .sha1,
                digits:    6,
                issuer:    "GitHub",
                account:   "david@gofake1.net"
              )
            )
          )
        )
      }
    }
    
    store.send(.passcodeList(.passcode(id: uuid, action: .editAction))) {
      $0.editToken = EditTokenReducer.State(id: uuid, issuer: "GitHub", account: "david@gofake1.net")
    }
    store.send(.editToken(.update(id: uuid, issuer: "New Issuer", account: "New Account"))) {
      $0.passcodes = [.init(id: uuid, issuer: "New Issuer", account: "New Account", text: "328482", isCounter: false)]
      $0.editToken = nil
    }
    XCTAssertTrue(didWriteToKeychain)
    XCTAssertTrue(didWriteToKeychainRefs)
    XCTAssertEqual(store.dependencies.appModel.totps[uuid]!.otp.token.issuer, "New Issuer")
    XCTAssertEqual(store.dependencies.appModel.totps[uuid]!.otp.token.account, "New Account")
  }
  
  func testRemoveToken() {
    let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    var didRemoveFromKeychain = false
    var didWriteToKeychainRefs = false
    let store = TestStore(
      initialState: AppReducer.State(passcodes: [.init(id: uuid, issuer: "", account: "", text: "", isCounter: false)]),
      reducer:      AppReducer()
    ) { dependencies in
      dependencies.keychainPersisting = .mock(delete: { _ in didRemoveFromKeychain = true; return .valid(()) })
      dependencies.keychainRefs = .mock(set: { _ in didWriteToKeychainRefs = true })
      withDependencies {
        $0.date = .constant(Date(timeIntervalSince1970: 0))
      } operation: {
        dependencies.appModel = AppModel()
        dependencies.appModel.add(
          totp: TOTP(
            otp: OTP(
              id:          uuid,
              keychainRef: Data(),
              token:       .init(
                type:      .totp(30),
                key:       .init(data: []),
                algorithm: .sha1,
                digits:    6,
                issuer:    "",
                account:   ""
              )
            )
          )
        )
      }
    }
    
    store.send(.passcodeList(.delete([0]))) {
      $0.alert = .init(
        title:           .init("Delete"),
        message:         .init("This action cannot be undone."),
        primaryButton:   .destructive(.init("Confirm"), action: .send(.alertConfirm)),
        secondaryButton: .cancel(.init("Cancel"))
      )
      $0.deletions = [.init(id: uuid, offsetForOTPList: 0)]
    }
    store.send(.alertConfirm) {
      $0.alert = nil
      $0.deletions = nil
      $0.passcodes = []
    }
    XCTAssertTrue(didRemoveFromKeychain)
    XCTAssertTrue(didWriteToKeychainRefs)
    XCTAssertEqual(store.dependencies.appModel.ids.count, 0)
    XCTAssertEqual(store.dependencies.appModel.totps.count, 0)
  }
  
  func testUpdatePasscode() {
    let uuid1 = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let uuid2 = UUID(uuidString: "11111111-0000-0000-0000-000000000000")!
    let store = TestStore(
      initialState: AppReducer.State(),
      reducer:      AppReducer()
    ) { dependencies in
      withDependencies {
        $0.date = .constant(Date(timeIntervalSince1970: 0))
      } operation: {
        dependencies.appModel = AppModel()
        dependencies.appModel.add(otps: [
          OTP(
            id:          uuid1,
            keychainRef: Data(),
            token:       .init(
              type:      .totp(30),
              key:       .init(data: []),
              algorithm: .sha1,
              digits:    6,
              issuer:    "GitHub",
              account:   "david@gofake1.net"
            )
          ),
          OTP(
            id:          uuid2,
            keychainRef: Data(),
            token:       .init(
              type:      .hotp(0),
              key:       .init(data: []),
              algorithm: .sha1,
              digits:    6,
              issuer:    "Example",
              account:   "alice@google.com"
            )
          )
        ])
      }
    }
    
    store.send(.updateTime(Date(timeIntervalSince1970: 0))) {
      $0.passcodes = [
        .init(id: uuid1, issuer: "GitHub", account: "david@gofake1.net", text: "328482", isCounter: false),
        .init(id: uuid2, issuer: "Example", account: "alice@google.com", text: "328482", isCounter: true),
      ]
    }
    store.send(.updateTime(Date(timeIntervalSince1970: 30))) {
      $0.passcodes = [
        .init(id: uuid1, issuer: "GitHub", account: "david@gofake1.net", text: "812658", isCounter: false),
        .init(id: uuid2, issuer: "Example", account: "alice@google.com", text: "328482", isCounter: true),
      ]
    }
    store.send(.passcodeList(.passcode(id: uuid2, action: .incrementCounterAction))) {
      $0.passcodes = [
        .init(id: uuid1, issuer: "GitHub", account: "david@gofake1.net", text: "812658", isCounter: false),
        .init(id: uuid2, issuer: "Example", account: "alice@google.com", text: "812658", isCounter: true),
      ]
    }
    store.send(.passcodeList(.passcode(id: uuid2, action: .incrementCounterAction))) {
      $0.passcodes = [
        .init(id: uuid1, issuer: "GitHub", account: "david@gofake1.net", text: "812658", isCounter: false),
        .init(id: uuid2, issuer: "Example", account: "alice@google.com", text: "073348", isCounter: true),
      ]
    }
  }
  
  func testFilter() {
    let uuid1 = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let uuid2 = UUID(uuidString: "11111111-0000-0000-0000-000000000000")!
    let store = TestStore(
      initialState: AppReducer.State(),
      reducer:      AppReducer()
    ) { dependencies in
      withDependencies {
        $0.date = .constant(Date(timeIntervalSince1970: 0))
      } operation: {
        dependencies.appModel = AppModel()
        dependencies.appModel.add(otps: [
          OTP(
            id: uuid1,
            keychainRef: Data(),
            token: .init(
              type:      .totp(30),
              key:       .init(data: []),
              algorithm: .sha1,
              digits:    6,
              issuer:    "Example",
              account:   "alice@google.com"
            )
          ),
          OTP(
            id: uuid2,
            keychainRef: Data(),
            token: .init(
              type:      .totp(30),
              key:       .init(data: []),
              algorithm: .sha1,
              digits:    6,
              issuer:    "GitHub",
              account:   "david@gofake1.net"
            )
          ),
        ])
      }
    }
    
    store.send(.updateFilterText("git")) {
      $0.passcodes = [.init(id: uuid2, issuer: "GitHub", account: "david@gofake1.net", text: "328482", isCounter: false)]
    }
    store.send(.updateFilterText("")) {
      $0.passcodes = [
        .init(id: uuid1, issuer: "Example", account: "alice@google.com", text: "328482", isCounter: false),
        .init(id: uuid2, issuer: "GitHub", account: "david@gofake1.net", text: "328482", isCounter: false),
      ]
    }
  }
}
