//
//  Keychain.swift
//  Xauth
//
//  Created by David on 4/25/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

import Dependencies
import Foundation

struct KeychainPersisting {
  let create: (String, String, String)       -> Validated<Data, Error>
  let read:   (Data)                         -> Validated<String, Error>
  let update: (Data, String, String, String) -> Validated<Data, Error>
  let delete: (Data)                         -> Validated<Void, Error>
  
  static func mock(
    create: @escaping (String, String, String)       -> Validated<Data, Error>   = XCTUnimplemented(),
    read:   @escaping (Data)                         -> Validated<String, Error> = XCTUnimplemented(),
    update: @escaping (Data, String, String, String) -> Validated<Data, Error>   = XCTUnimplemented(),
    delete: @escaping (Data)                         -> Validated<Void, Error>   = XCTUnimplemented()
  ) -> Self {
    .init(create: create, read: read, update: update, delete: delete)
  }
}

extension KeychainPersisting: DependencyKey {
  static let liveValue = Self(
    create: Keychain.create,
    read:   Keychain.read,
    update: Keychain.update,
    delete: Keychain.delete
  )
}

extension DependencyValues {
  var keychainPersisting: KeychainPersisting {
    get { self[KeychainPersisting.self] }
    set { self[KeychainPersisting.self] = newValue }
  }
}

struct Keychain {
  enum Error: Swift.Error {
    case badStatus(String)
    case badQuery([CFString: AnyObject])
    case badType(Any?, String)
    case fieldMissing(CFString)
    case mismatchedIds(Data, Data)
    case invalidString(Data)
    
    static func badStatus(_ status: OSStatus) -> Self {
      let message: NSString? = SecCopyErrorMessageString(status, nil)
      return .badStatus(message.flatMap(String.init) ?? "\(status)")
    }
  }
  
  static func create(account: String, service: String, value: String) -> Validated<Data, Swift.Error> {
    let attributes: [CFString: AnyObject] = [
      kSecAttrAccount:         account as NSString,
      kSecAttrDescription:     "Xauth token" as NSString,
      kSecAttrLabel:           "\(service) (\(account))" as NSString,
      kSecAttrService:         service as NSString,
      kSecClass:               kSecClassGenericPassword,
      kSecReturnPersistentRef: kCFBooleanTrue,
      kSecValueData:           value.data(using: .utf8)! as NSData,
    ]
    var result: CFTypeRef?
    let status = SecItemAdd(attributes as CFDictionary, &result)
    guard status == errSecSuccess else { return .invalid(Error.badStatus(status)) }
    guard let ref = result as? Data else { return .invalid(Error.badType(result, "Data")) }
    return .valid(ref)
  }
  
  static func read(ref: Data) -> Validated<String, Swift.Error> {
    func validKeychainItemField(_ keychainItem: NSDictionary, key: CFString) -> Validated<Data, Swift.Error> {
      guard let value = keychainItem[key] else { return .invalid(Error.fieldMissing(key)) }
      guard let data = value as? Data else { return .invalid(Error.badType(value, "Data")) }
      return .valid(data)
    }
    
    func idsMatch(_ a: Data, _ b: Data) -> Validated<Void, Swift.Error> {
      guard a == b else { return .invalid(Error.mismatchedIds(a, b)) }
      return .valid(())
    }
    
    func validString(_ data: Data) -> Validated<String, Swift.Error> {
      guard let string = String(data: data, encoding: .utf8) else { return .invalid(Error.invalidString(data)) }
      return .valid(string)
    }
    
    let query: [CFString: AnyObject] = [
      kSecClass:               kSecClassGenericPassword,
      kSecValuePersistentRef:  ref as NSData,
      kSecReturnData:          kCFBooleanTrue,
      kSecReturnPersistentRef: kCFBooleanTrue,
    ]
    var result: AnyObject?
    let status = withUnsafeMutablePointer(to: &result) { SecItemCopyMatching(query as CFDictionary, $0) }
    guard status == errSecSuccess else { return .invalid(Error.badStatus(status)) }
    guard let _result = result else { return .invalid(Error.badQuery(query)) }
    guard let keychainItem = _result as? NSDictionary else { return .invalid(Error.badType(result, "NSDictionary")) }
    return zip(with: { ($0, $1) })(
      validKeychainItemField(keychainItem, key: kSecValuePersistentRef),
      validKeychainItemField(keychainItem, key: kSecValueData)
    ).flatMap({ (validatedRef, validatedSecret) in
      zip(with: { ($0, $1) })(
        idsMatch(ref, validatedRef),
        validString(validatedSecret)
      )
    }).flatMap({ (_, urlString) in
      .valid(urlString)
    })
  }
  
  static func update(ref: Data, account: String, service: String, newValue: String) -> Validated<Data, Swift.Error> {
    // SecItemUpdate doesn't keep the previous persistent ref if anything other than kSecValueData is changed,
    // so do "add and delete" instead to get another persistent ref
//    let query: [CFString: AnyObject] = [
//      kSecClass:              kSecClassGenericPassword,
//      kSecValuePersistentRef: ref as NSData,
//    ]
//    let attributesToUpdate: [CFString: AnyObject] = [
//      kSecAttrAccount: account as NSString,
//      kSecAttrLabel:   "\(service) (\(account))" as NSString,
//      kSecAttrService: service as NSString,
//      kSecValueData:   newValue.data(using: .utf8)! as NSData,
//    ]
//    let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
//    guard status == errSecSuccess else { return .invalid(Error.badStatus(status)) }
//    return .valid(())
    
    Self.delete(ref: ref).flatMap {
      Self.create(account: account, service: service, value: newValue)
    }
  }
  
  static func delete(ref: Data) -> Validated<Void, Swift.Error> {
    let query: [CFString: AnyObject] = [
      kSecClass:              kSecClassGenericPassword,
      kSecValuePersistentRef: ref as NSData,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess else { return .invalid(Error.badStatus(status)) }
    return .valid(())
  }
}
