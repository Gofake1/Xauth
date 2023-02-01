//
//  AppModel.swift
//  Xauth
//
//  Created by David on 1/31/23.
//  Copyright © 2023 David Wu. All rights reserved.
//

import Dependencies
import Foundation

class AppModel {
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
  @Dependency(\.date) var makeDate
  private var passcodeCache: [UUID: Passcode] = [:]
  
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

extension AppModel: DependencyKey {
  static let liveValue = AppModel()
}

extension DependencyValues {
  var appModel: AppModel {
    get { self[AppModel.self] }
    set { self[AppModel.self] = newValue }
  }
}
