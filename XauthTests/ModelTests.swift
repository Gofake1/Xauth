//
//  ModelTests.swift
//  XauthTests
//
//  Created by David on 5/7/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import struct CryptoKit.SymmetricKey
import XCTest

class ModelTests: XCTestCase {
  func testHashing() {
    let hashing = Hashing(algorithm: .sha1)
    let key = SymmetricKey(data: Array("12345678901234567890".utf8))
    var data: UInt64 = 1
    let hash = hashing.run(Data(bytes: &data, count: MemoryLayout<UInt64>.size), key)
    XCTAssertEqual(hash, 32190673)
  }
  
  func testOTPAuthURLDecoding_Success() {
    let encoded = "otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
    let tokenCoding = TokenCoding<String>.otpAuthURL()
    let validatedToken = tokenCoding.decode(encoded)
    switch validatedToken {
    case let .valid(_token):
      switch _token.type {
      case .hotp:
        XCTFail()
      case let .totp(period):
        XCTAssertEqual(period, 30)
      }
      XCTAssertEqual(_token.key, .init(data: [0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef]))
      XCTAssertEqual(_token.algorithm, .sha1)
      XCTAssertEqual(_token.issuer, "Example")
      XCTAssertEqual(_token.account, "alice@google.com")
    case .invalid:
      XCTFail()
    }
  }
  
  func testOTPAuthURLDecoding_Failure() {
    let encoded = "otpauth://totp/Example:alice@google.com"
    let tokenCoding = TokenCoding<String>.otpAuthURL()
    let validatedToken = tokenCoding.decode(encoded)
    switch validatedToken {
    case .valid:
      XCTFail()
    case let .invalid(errors):
      XCTAssertEqual(errors.count, 1)
    }
  }
  
  func testOTPAuthURLEncoding_Success() {
    let token = Token(
      type:      .totp(30),
      key:       .init(data: [0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef]),
      algorithm: .sha1,
      digits:    6,
      issuer:    "Example",
      account:   "alice@google.com"
    )
    let tokenCoding = TokenCoding<String>.otpAuthURL()
    let validatedEncoded = tokenCoding.encode(token)
    switch validatedEncoded {
    case let .valid(encoded):
      let expected = "otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA1&digits=6&period=30"
      XCTAssertEqual(encoded, expected)
    case .invalid:
      XCTFail()
    }
  }
}
