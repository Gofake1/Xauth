//
//  UserDefaults.swift
//  Xauth
//
//  Created by David on 1/23/23.
//  Copyright © 2023 David Wu. All rights reserved.
//

import Dependencies
import Foundation

struct UserDefaultsArrayPersisting<T> {
  let get: ()    -> Validated<[T], Error>
  let set: ([T]) -> Void
  
  enum Error: Swift.Error {
    case invalidType(Any, String)
  }
  
  static func live(_ userDefaults: UserDefaults, key: String) -> Self {
    .init(
      get: {
        guard let data = userDefaults.array(forKey: key) else { return .valid([]) }
        guard let array = data as? [T] else { return .invalid(Error.invalidType(data, "\(T.self)")) }
        return .valid(array)
      },
      set: { userDefaults.set($0, forKey: key) }
    )
  }
  
  static func mock(
    get: @escaping ()    -> Validated<[T], Error> = XCTUnimplemented(),
    set: @escaping ([T]) -> Void                  = XCTUnimplemented()
  ) -> Self {
    .init(get: get, set: set)
  }
}

typealias KeychainRefs = UserDefaultsArrayPersisting<Data>

extension KeychainRefs: DependencyKey, TestDependencyKey {
  static let liveValue = Self.live(.standard, key: "keychainRefs")
}

extension DependencyValues {
  var keychainRefs: KeychainRefs {
    get { self[KeychainRefs.self] }
    set { self[KeychainRefs.self] = newValue }
  }
}
