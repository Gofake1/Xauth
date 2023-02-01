//
//  Models.swift
//  Xauth
//
//  Created by David on 10/4/19.
//  Copyright © 2019 David Wu. All rights reserved.
//

import CryptoKit
import Dependencies
import Foundation

struct Passcode: Equatable, Identifiable {
  /// Uses the same id as the `Token` that generated this passcode
  let id:        UUID
  let issuer:    String
  let account:   String
  let text:      String
  let isCounter: Bool
}

struct Token: Equatable {
  enum Algorithm: String {
    case sha1   = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
    
    init?(rawValue: String) {
      switch rawValue {
      case "sha1",   "SHA1":   self = .sha1
      case "sha256", "SHA256": self = .sha256
      case "sha512", "SHA512": self = .sha512
      default:                 return nil
      }
    }
  }
  
  enum `Type`: Equatable {
    case hotp(UInt64)
    case totp(Int)
  }
  
  enum Error: Swift.Error {
    case invalidCounterValue
    case invalidSecretValue
    case invalidTokenType
    case invalidUrl
  }
  
  let type:      `Type`
  let key:       SymmetricKey
  let algorithm: Algorithm
  let digits:    Int
  let issuer:    String
  let account:   String
  
  // https://github.com/google/google-authenticator/wiki/Key-Uri-Format
  // TODO: rewrite using swift-parsing https://github.com/pointfreeco/swift-parsing
  static func make(urlComponents: URLComponents) -> Validated<Token, Swift.Error> {
    func makeType(_ host: String?, _ queryItems: [String: String]) -> Validated<`Type`, Swift.Error> {
      switch host {
      case "hotp":
        return queryItems["counter"]
          .flatMap(UInt64.init)
          .ifNil(error: Error.invalidCounterValue)
          .flatMap { .valid(.hotp($0)) }
      case "totp":
        return queryItems["period"].flatMap(Int.init).flatMap { .valid(.totp($0)) } ?? .valid(.totp(30))
      default:
        return .invalid(Error.invalidTokenType)
      }
    }
    
    func makeSecret(_ queryItems: [String: String]) -> Validated<SymmetricKey, Swift.Error> {
      queryItems["secret"]
        .ifNil(error: Error.invalidSecretValue)
        .flatMap(base32Decode)
        .flatMap { .valid(SymmetricKey(data: $0)) }
    }
    
    func makeIssuerAndAccount(_ path: String, _ queryItems: [String: String]) -> (String, String) {
      let tokens = path.dropFirst() // Drop leading '/'
        .split(separator: ":").map(String.init)
      if tokens.count >= 2 {
        return (tokens[0].nilIfEmpty ?? queryItems["issuer"] ?? "", tokens[1])
      } else if tokens.count == 1 {
        return (queryItems["issuer"] ?? "", tokens[0])
      } else {
        return (queryItems["issuer"] ?? "", "")
      }
    }
    
    return (urlComponents.queryItems?.dictionary() as [String: String]?)
      .ifNil(error: Error.invalidUrl)
      .flatMap { queryItems in
        zip(makeType(urlComponents.host, queryItems), makeSecret(queryItems)).flatMap {
          let (issuer, account) = makeIssuerAndAccount(urlComponents.path, queryItems)
          return .valid(Token(
            type:      $0.0,
            key:       $0.1,
            algorithm: queryItems["algorithm"].flatMap(Algorithm.init) ?? .sha1,
            digits:    queryItems["digits"].flatMap(Int.init) ?? 6,
            issuer:    issuer,
            account:   account)
          )
        }
      }
  }
}

struct OTP: Equatable {
  let id:          UUID
  let keychainRef: Data
  let hashing:     Hashing
  let token:       Token
  
  init(id: UUID, keychainRef: Data, token: Token) {
    self.id          = id
    self.keychainRef = keychainRef
    self.hashing     = .init(algorithm: token.algorithm)
    self.token       = token
  }
  
  fileprivate func generate(_ factor: Data) -> (Bool) -> Passcode {
    let hash = UInt32(bigEndian: self.hashing.run(factor, self.token.key))
      & 0x7FFF_FFFF
      % UInt32(pow(10, Float(self.token.digits))
    )
    let text = String(format: "%0*u", self.token.digits, hash)
    return { isCounter in
      .init(id: self.id, issuer: self.token.issuer, account: self.token.account, text: text, isCounter: isCounter)
    }
  }
  
  static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.id == rhs.id
  }
}

class HOTP {
  private(set) var otp: OTP
  
  init(otp: OTP) {
    self.otp = otp
  }
  
  func generate() -> Passcode {
    guard case let .hotp(counter) = self.otp.token.type else { fatalError() }
    defer {
      let otp = self.otp
      self.otp = OTP(
        id:          otp.id,
        keychainRef: otp.keychainRef,
        token:       .init(
          type:      .hotp(counter + 1),
          key:       otp.token.key,
          algorithm: otp.token.algorithm,
          digits:    otp.token.digits,
          issuer:    otp.token.issuer,
          account:   otp.token.account
        )
      )
    }
    var factor = counter.bigEndian
    return self.otp.generate(Data(bytes: &factor, count: MemoryLayout<UInt64>.size))(true)
  }
}

struct TOTP {
  let otp: OTP
  
  func generate(_ date: Date) -> Passcode {
    guard case let .totp(period) = self.otp.token.type else { fatalError() }
    var factor = UInt64(date.timeIntervalSince1970 / Double(period)).bigEndian
    return self.otp.generate(Data(bytes: &factor, count: MemoryLayout<UInt64>.size))(false)
  }
}

enum OTPFactory {
  static func addToKeychain(
    issuer:      String,
    account:     String,
    key:         String,
    type:        Token.`Type`,
    algorithm:   Token.Algorithm,
    digits:      Int,
    id:          UUID,
    tokenCoding: TokenCoding<String>,
    keychain:    KeychainPersisting
  ) -> Validated<OTP, Error> {
    base32Decode(key)
      .flatMap {
        .valid(Token(
          type:      type,
          key:       .init(data: $0),
          algorithm: algorithm,
          digits:    digits,
          issuer:    issuer,
          account:   account
        ))
      }
      .flatMap { token in
        tokenCoding.encode(token)
          .flatMap { keychain.create(token.account, token.issuer, $0) }
          .flatMap { .valid(.init(id: id, keychainRef: $0, token: token)) }
      }
  }
  
  static func addToKeychain(
    url:         String,
    id:          UUID,
    tokenCoding: TokenCoding<String>,
    keychain:    KeychainPersisting
  ) -> Validated<OTP, Error> {
    tokenCoding.decode(url).flatMap { token in
      keychain.create(token.account, token.issuer, url)
        .flatMap { .valid(.init(id: id, keychainRef: $0, token: token)) }
    }
  }
  
  static func fromKeychain(
    keychainRef: Data,
    id:          UUID,
    tokenCoding: TokenCoding<String>,
    keychain:    KeychainPersisting
  ) -> Validated<OTP, Error> {
    keychain.read(keychainRef)
      .flatMap(tokenCoding.decode)
      .flatMap { .valid(.init(id: id, keychainRef: keychainRef, token: $0)) }
  }
}

struct Hashing {
  let run: (Data, SymmetricKey) -> UInt32
  
  init(algorithm: Token.Algorithm) {
    switch algorithm {
    case .sha1:   self = Self(Insecure.SHA1.self)
    case .sha256: self = Self(SHA256.self)
    case .sha512: self = Self(SHA512.self)
    }
  }
  
  private init<H: HashFunction>(_ h: H.Type) {
    self.run = { factor, key in
      HMAC<H>.authenticationCode(for: factor, using: key).uint32
    }
  }
}

struct TokenCoding<Raw> {
  let decode: (Raw)   -> Validated<Token, Error>
  let encode: (Token) -> Validated<Raw, Error>
  
  enum OTPAuthURLError: Error {
    case decode(String)
    case encode(Token)
  }
  
  static func otpAuthURL() -> TokenCoding<String> {
    .init(
      decode: {
        URL(string: $0)
          .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
          .ifNil(error: OTPAuthURLError.decode($0))
          .flatMap(Token.make)
      },
      encode: {
        let makeQueryItems: (Token, URLQueryItem) -> [URLQueryItem] = {
          [
            .init(name: "secret",    value: $0.key.base32String),
            .init(name: "issuer",    value: $0.issuer),
            .init(name: "algorithm", value: $0.algorithm.rawValue),
            .init(name: "digits",    value: String($0.digits)),
            $1,
          ]
        }
        
        var urlComponents = URLComponents()
        urlComponents.scheme = "otpauth"
        urlComponents.path =  "/\($0.issuer):\($0.account)"
        switch $0.type {
        case .hotp(let counter):
          urlComponents.host = "hotp"
          urlComponents.queryItems = makeQueryItems($0, .init(name: "counter", value: String(counter)))
        case .totp(let period):
          urlComponents.host = "totp"
          urlComponents.queryItems = makeQueryItems($0, .init(name: "period", value: String(period)))
        }
        return urlComponents.string.ifNil(error: OTPAuthURLError.encode($0))
      }
    )
  }
}

extension TokenCoding<String>: DependencyKey, TestDependencyKey {
  static let liveValue = TokenCoding.otpAuthURL()
  static let testValue = TokenCoding.otpAuthURL()
}

extension DependencyValues {
  var tokenCoding: TokenCoding<String> {
    get { self[TokenCoding<String>.self] }
    set { self[TokenCoding<String>.self] = newValue }
  }
}

extension Array where Element == URLQueryItem {
  fileprivate func dictionary() -> [String: String] {
    self.reduce(into: [:]) {
      guard let value = $1.value else { return }
      $0[$1.name] = value
    }
  }
}

extension HashedAuthenticationCode {
  fileprivate var uint32: UInt32 {
    self.withUnsafeBytes { [byteCount] ptr in
      let offset = Int(ptr[byteCount-1] & 0x0f)
      let truncatedPtr = ptr.baseAddress! + offset
      return truncatedPtr.bindMemory(to: UInt32.self, capacity: 1).pointee
    }
  }
}

extension Optional {
  fileprivate func ifNil(error errorIfNil: Error) -> Validated<Wrapped, Error> {
    guard let wrapped = self else { return .invalid(errorIfNil) }
    return .valid(wrapped)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    self.isEmpty ? nil : self
  }
}

extension SymmetricKey {
  fileprivate var base32String: String {
    base32Encode(self.withUnsafeBytes(Array.init))
  }
}
