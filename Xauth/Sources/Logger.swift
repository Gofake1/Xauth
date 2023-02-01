//
//  Logger.swift
//  Xauth
//
//  Created by David on 1/31/23.
//  Copyright © 2023 David Wu. All rights reserved.
//

import Dependencies
import os

struct Logging {
  let log: (String) -> Void
  
  func callAsFunction(_ message: String) {
    self.log(message)
  }
  
  func callAsFunction(errors: [Error]) {
    self.log("\(errors)")
  }
  
  func combine(_ other: Logging) -> Logging {
    .init {
      self.log($0)
      other.log($0)
    }
  }
  
  static func os() -> Logging {
    let logger = Logger()
    return .init {
      logger.log("\($0, privacy: .public)")
    }
  }
}

extension Logging: DependencyKey {
  static let liveValue = Logging.os()
}

extension DependencyValues {
  var log: Logging {
    get { self[Logging.self] }
    set { self[Logging.self] = newValue }
  }
}
