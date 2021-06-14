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
    let otpList = OTPList(makeDate: { Date(timeIntervalSince1970: 0)} )
    var didWriteToKeychain = false
    var didWriteToKeychainRefs = false
    let store = TestStore(
      initialState: AppState(),
      reducer:      appReducer,
      environment:  AppEnvironment(
        keychain:     .mock(create: { _, _, _ in didWriteToKeychain = true; return .valid(Data()) }),
        keychainRefs: .mock(set: { _ in didWriteToKeychainRefs = true }),
        logging:      .os_log(),
        makeUUID:     { uuid },
        otpFactory:   .init(),
        otpList:      otpList,
        qrScan:       { fatalError() },
        tokenCoding:  .otpAuthURL()
      )
    )
    
    store.assert(
      .send(.showAddTokenForm) {
        $0.addTokenForm = .init()
      },
      .send(.newToken(.addTokenForm(.addToken(issuer: "GitHub", account: "david@gofake1.net", key: "23456", type: .totp)))) {
        $0.passcodes = [.init(id: uuid, issuer: "GitHub", account: "david@gofake1.net", text: "158781", isCounter: false)]
        $0.addTokenForm = nil
      },
      .do {
        XCTAssertTrue(didWriteToKeychain)
        XCTAssertTrue(didWriteToKeychainRefs)
        XCTAssertEqual(otpList.ids[0].0, uuid)
        XCTAssertEqual(otpList.hotps.count, 0)
        XCTAssertEqual(otpList.totps.count, 1)
      }
    )
  }
  
  func testEditToken() {
    let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let otpList = OTPList(makeDate: { Date(timeIntervalSince1970: 0) })
    var didWriteToKeychain = false
    var didWriteToKeychainRefs = false
    let store = TestStore(
      initialState: AppState(passcodes: [.init(id: uuid, issuer: "GitHub", account: "david@gofake1.net", text: "", isCounter: false)]),
      reducer:      appReducer,
      environment:  AppEnvironment(
        keychain:     .mock(update: { _, _, _, _ in didWriteToKeychain = true; return .valid(Data()) }),
        keychainRefs: .mock(set: { _ in didWriteToKeychainRefs = true }),
        logging:      .os_log(),
        makeUUID:     { fatalError() },
        otpFactory:   .init(),
        otpList:      otpList,
        qrScan:       { fatalError() },
        tokenCoding:  .otpAuthURL()
      )
    )
    otpList.add(
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
    
    store.assert(
      .send(.passcodeList(.passcode(id: uuid, action: .editAction))) {
        $0.editToken = EditTokenState(id: uuid, issuer: "GitHub", account: "david@gofake1.net")
      },
      .send(.editToken(.update(id: uuid, issuer: "New Issuer", account: "New Account"))) {
        $0.passcodes = [.init(id: uuid, issuer: "New Issuer", account: "New Account", text: "328482", isCounter: false)]
        $0.editToken = nil
      },
      .do {
        XCTAssertTrue(didWriteToKeychain)
        XCTAssertTrue(didWriteToKeychainRefs)
        XCTAssertEqual(otpList.totps[uuid]!.otp.token.issuer, "New Issuer")
        XCTAssertEqual(otpList.totps[uuid]!.otp.token.account, "New Account")
      }
    )
  }
  
  func testRemoveToken() {
    let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let otpList = OTPList(makeDate: { Date(timeIntervalSince1970: 0) })
    var didRemoveFromKeychain = false
    var didWriteToKeychainRefs = false
    let store = TestStore(
      initialState: AppState(passcodes: [.init(id: uuid, issuer: "", account: "", text: "", isCounter: false)]),
      reducer:      appReducer,
      environment:  AppEnvironment(
        keychain:     .mock(delete: { _ in didRemoveFromKeychain = true; return .valid(()) }),
        keychainRefs: .mock(set: { _ in didWriteToKeychainRefs = true }),
        logging:      .os_log(),
        makeUUID:     { fatalError() },
        otpFactory:   .init(),
        otpList:      otpList,
        qrScan:       { fatalError() },
        tokenCoding:  .otpAuthURL()
      )
    )
    otpList.add(
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
    
    store.assert(
      .send(.passcodeList(.delete([0]))) {
        $0.alert = .init(
          title:           .init("Delete"),
          message:         .init("This action cannot be undone."),
          primaryButton:   .destructive(.init("Confirm"), send: .alertConfirm),
          secondaryButton: .cancel()
        )
        $0.deletions = [.init(id: uuid, offsetForOTPList: 0)]
      },
      .send(.alertConfirm) {
        $0.alert = nil
        $0.deletions = nil
        $0.passcodes = []
      },
      .do {
        XCTAssertTrue(didRemoveFromKeychain)
        XCTAssertTrue(didWriteToKeychainRefs)
        XCTAssertEqual(otpList.ids.count, 0)
        XCTAssertEqual(otpList.totps.count, 0)
      }
    )
  }
  
  func testUpdatePasscode() {
    let uuid1 = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let uuid2 = UUID(uuidString: "11111111-0000-0000-0000-000000000000")!
    let otpList = OTPList(makeDate: { Date(timeIntervalSince1970: 0) })
    let store = TestStore(
      initialState: AppState(),
      reducer:      appReducer,
      environment:  AppEnvironment(
        keychain:     .mock(),
        keychainRefs: .mock(),
        logging:      .os_log(),
        makeUUID:     { fatalError() },
        otpFactory:   .init(),
        otpList:      otpList,
        qrScan:       { fatalError() },
        tokenCoding:  .otpAuthURL()
      )
    )
    otpList.add(otps: [
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
    
    store.assert(
      .send(.updateTime(Date(timeIntervalSince1970: 0))) {
        $0.passcodes = [
          .init(id: uuid1, issuer: "GitHub", account: "david@gofake1.net", text: "328482", isCounter: false),
          .init(id: uuid2, issuer: "Example", account: "alice@google.com", text: "328482", isCounter: true),
        ]
      },
      .send(.updateTime(Date(timeIntervalSince1970: 30))) {
        $0.passcodes = [
          .init(id: uuid1, issuer: "GitHub", account: "david@gofake1.net", text: "812658", isCounter: false),
          .init(id: uuid2, issuer: "Example", account: "alice@google.com", text: "328482", isCounter: true),
        ]
      },
      .send(.passcodeList(.passcode(id: uuid2, action: .incrementCounterAction))) {
        $0.passcodes = [
          .init(id: uuid1, issuer: "GitHub", account: "david@gofake1.net", text: "812658", isCounter: false),
          .init(id: uuid2, issuer: "Example", account: "alice@google.com", text: "812658", isCounter: true),
        ]
      },
      .send(.passcodeList(.passcode(id: uuid2, action: .incrementCounterAction))) {
        $0.passcodes = [
          .init(id: uuid1, issuer: "GitHub", account: "david@gofake1.net", text: "812658", isCounter: false),
          .init(id: uuid2, issuer: "Example", account: "alice@google.com", text: "073348", isCounter: true),
        ]
      }
    )
  }
  
  func testFilter() {
    let uuid1 = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let uuid2 = UUID(uuidString: "11111111-0000-0000-0000-000000000000")!
    let otpList = OTPList(makeDate: { Date(timeIntervalSince1970: 0) })
    let store = TestStore(
      initialState: AppState(),
      reducer:      appReducer,
      environment:  AppEnvironment(
        keychain:     .mock(),
        keychainRefs: .mock(),
        logging:      .os_log(),
        makeUUID:     { fatalError() },
        otpFactory:   .init(),
        otpList:      otpList,
        qrScan:       { fatalError() },
        tokenCoding:  .otpAuthURL()
      )
    )
    otpList.add(otps: [
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
    
    store.assert(
      .send(.updateFilterText("git")) {
        $0.passcodes = [.init(id: uuid2, issuer: "GitHub", account: "david@gofake1.net", text: "328482", isCounter: false)]
      },
      .send(.updateFilterText("")) {
        $0.passcodes = [
          .init(id: uuid1, issuer: "Example", account: "alice@google.com", text: "328482", isCounter: false),
          .init(id: uuid2, issuer: "GitHub", account: "david@gofake1.net", text: "328482", isCounter: false),
        ]
      }
    )
  }
}

extension KeychainPersisting {
  fileprivate static func mock(
    create: @escaping (String, String, String)       -> Validated<Data, Error>   = { _, _, _ in fatalError() },
    read:   @escaping (Data)                         -> Validated<String, Error> = { _ in fatalError() },
    update: @escaping (Data, String, String, String) -> Validated<Data, Error>   = { _, _, _, _ in fatalError() },
    delete: @escaping (Data)                         -> Validated<Void, Error>   = { _ in fatalError() }
  ) -> Self {
    .init(create: create, read: read, update: update, delete: delete)
  }
}

extension UserDefaultsArrayPersisting {
  fileprivate static func mock(
    get: @escaping ()    -> Validated<[T], Error> = { fatalError() },
    set: @escaping ([T]) -> Void                  = { _ in fatalError() }
  ) -> Self {
    .init(get: get, set: set)
  }
}
