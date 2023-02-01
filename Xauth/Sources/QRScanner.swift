//
//  QRScanner.swift
//  Xauth
//
//  Created by David on 1/31/23.
//  Copyright © 2023 David Wu. All rights reserved.
//

import Dependencies

struct QRScanning {
  let scan: () throws -> String?
  
  func callAsFunction() throws -> String? {
    try self.scan()
  }
}

extension QRScanning: TestDependencyKey {
  static let testValue = Self(scan: XCTUnimplemented())
}

extension DependencyValues {
  var scanQR: QRScanning {
    get { self[QRScanning.self] }
    set { self[QRScanning.self] = newValue }
  }
}
