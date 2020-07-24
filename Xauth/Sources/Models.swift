//
//  Models.swift
//  Xauth
//
//  Created by David on 10/4/19.
//  Copyright © 2019 David Wu. All rights reserved.
//

import CryptoKit
import Foundation
import os

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
  
  let type:      `Type`
  let key:       SymmetricKey
  let algorithm: Algorithm
  let digits:    Int
  let issuer:    String
  let account:   String
  
  // https://github.com/google/google-authenticator/wiki/Key-Uri-Format
  static func make(urlComponents: URLComponents) -> Validated<Token, Error> {
    func makeType(_ host: String?, _ queryItems: [String: String]) -> Validated<`Type`, Error> {
      switch host {
      case "hotp":
        return queryItems["counter"]
          .flatMap(UInt64.init)
          .ifNil(error: NSError()) //FIXME
          .flatMap { .valid(.hotp($0)) }
      case "totp":
        return queryItems["period"].flatMap(Int.init).flatMap { .valid(.totp($0)) } ?? .valid(.totp(30))
      default:
        return .invalid(NSError()) //FIXME
      }
    }
    
    func makeSecret(_ queryItems: [String: String]) -> Validated<SymmetricKey, Error> {
      queryItems["secret"]
        .ifNil(error: NSError(domain: "", code: 0)) //*
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
      .ifNil(error: NSError(domain: "", code: 0))
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

struct OTPFactory { 
  func addToKeychain(
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
  
  func addToKeychain(
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
  
  func fromKeychain(
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

class OTPList {
  enum OTPType {
    case hotp, totp
  }
  
  private(set) var ids: [(UUID, OTPType)] = []
  private(set) var hotps: [UUID: HOTP] = [:]
  private(set) var totps: [UUID: TOTP] = [:]
  var filterText = ""
  var passcodes: [Passcode] {
    if self.filterText.isEmpty {
      return self.ids.map { self.passcodeCache[$0.0]! }
    } else {
      return self.ids.reduce(into: []) {
        let token = self.otp(id: $1.0)!.token
        if token.issuer.localizedCaseInsensitiveContains(self.filterText)
            || token.account.localizedCaseInsensitiveContains(self.filterText) {
          $0.append(self.passcodeCache[$1.0]!)
        }
      }
    }
  }
  var keychainRefs: [Data] {
    self.ids.map {
      switch $0.1 {
      case .hotp: return self.hotps[$0.0]!.otp.keychainRef
      case .totp: return self.totps[$0.0]!.otp.keychainRef
      }
    }
  }
  private let makeDate: () -> Date
  private var passcodeCache: [UUID: Passcode] = [:]
  
  init(makeDate: @escaping () -> Date) {
    self.makeDate = makeDate
  }
  
  func add(otps: [OTP]) {
    for otp in otps {
      switch otp.token.type {
      case .hotp:
        self.add(hotp: HOTP(otp: otp))
      case .totp:
        self.add(totp: TOTP(otp: otp))
      }
    }
  }
  
  func add(hotp: HOTP) {
    self.ids.append((hotp.otp.id, .hotp))
    self.hotps[hotp.otp.id] = hotp
    self.passcodeCache[hotp.otp.id] = hotp.generate()
  }
  
  func add(totp: TOTP) {
    self.ids.append((totp.otp.id, .totp))
    self.totps[totp.otp.id] = totp
    self.passcodeCache[totp.otp.id] = totp.generate(self.makeDate())
  }
  
  func otp(id: UUID) -> OTP? {
    guard let (id, type) = self.ids.first(where: { $0.0 == id }) else { return nil }
    switch type {
    case .hotp: return self.hotps[id]!.otp
    case .totp: return self.totps[id]!.otp
    }
  }
  
  func update(hotp id: UUID) {
    self.passcodeCache[id] = self.hotps[id]!.generate()
  }
  
  func update(date: Date) {
    for (_, totp) in self.totps {
      self.passcodeCache[totp.otp.id] = totp.generate(date)
    }
  }
  
  func update(otp: OTP) {
    switch otp.token.type {
    case .hotp:
      let hotp = HOTP(otp: otp)
      self.hotps[otp.id] = hotp
      self.passcodeCache[otp.id] = hotp.generate()
    case .totp:
      let totp = TOTP(otp: otp)
      self.totps[otp.id] = totp
      self.passcodeCache[otp.id] = totp.generate(self.makeDate())
    }
  }
  
  func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    self.ids.move(fromOffsets: source, toOffset: destination)
  }
  
  func remove(atOffsets indices: IndexSet) {
    let ids = indices.map { self.ids[$0] }
    for (id, type) in ids {
      switch type {
      case .hotp: self.hotps[id] = nil
      case .totp: self.totps[id] = nil
      }
      self.passcodeCache[id] = nil
    }
    self.ids.remove(atOffsets: indices)
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

enum OTPAuthURLError: Error {
  case decode(String)
  case encode(Token)
}

struct TokenCoding<Raw> {
  let decode: (Raw)   -> Validated<Token, Error>
  let encode: (Token) -> Validated<Raw, Error>
  
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

struct KeychainPersisting {
  let create: (String, String, String)       -> Validated<Data, Error>
  let read:   (Data)                         -> Validated<String, Error>
  let update: (Data, String, String, String) -> Validated<Data, Error>
  let delete: (Data)                         -> Validated<Void, Error>
}

enum UserDefaultsError: Error {
  case badKey(String)
  case badType(Any, String)
}

struct UserDefaultsArrayPersisting<T> {
  let get: ()    -> Validated<[T], Error>
  let set: ([T]) -> Void
  
  static func real(_ userDefaults: UserDefaults, key: String) -> Self {
    .init(
      get: {
        guard let data = userDefaults.array(forKey: key) else { return .invalid(UserDefaultsError.badKey(key)) }
        guard let array = data as? [T] else { return .invalid(UserDefaultsError.badType(data, "\(T.self)")) }
        return .valid(array)
      },
      set: { userDefaults.set($0, forKey: key) }
    )
  }
}

struct Logging {
  let log: (String) -> Void
  
  func log(errors: [Error]) {
    self.log("\(errors)")
  }
  
  func concatenate(_ other: Logging) -> Logging {
    .init {
      self.log($0)
      other.log($0)
    }
  }
  
  static func os_log() -> Logging {
    let logger = Logger()
    return .init {
      logger.log("\($0, privacy: .public)")
    }
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
