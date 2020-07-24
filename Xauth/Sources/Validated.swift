//
//  Validated.swift
//  Xauth
//
//  Created by David on 2/10/20.
//  Copyright © 2020 David Wu. All rights reserved.
//

precedencegroup ForwardApplication {
  associativity: left
}
infix operator |>: ForwardApplication
public func |> <A, B>(x: A, f: (A) -> B) -> B {
  return f(x)
}

enum Validated<A, E> {
  case valid(A)
  case invalid([E])
  
  var valid: A? {
    switch self {
    case let .valid(valid): return valid
    case .invalid:          return nil
    }
  }
  
  var invalid: [E]? {
    switch self {
    case .valid:               return nil
    case let .invalid(errors): return errors
    }
  }
  
  static func invalid(_ error: E) -> Self {
    return .invalid([error])
  }
  
//  func map<B>(_ f: (A) -> B) -> Validated<B, E> {
//    switch self {
//    case let .valid(a):   return .valid(f(a))
//    case let .invalid(e): return .invalid(e)
//    }
//  }
  
  func flatMap<B>(_ f: (A) -> Validated<B, E>) -> Validated<B, E> {
    switch self {
    case let .valid(a):
      switch f(a) {
      case let .valid(b):   return .valid(b)
      case let .invalid(e): return .invalid(e)
      }
    case let .invalid(e):
      return .invalid(e)
    }
  }
}

func map<A, B, E>(_ f: @escaping (A) -> B) -> (Validated<A, E>) -> Validated<B, E> {
  return {
    switch $0 {
    case let .valid(a):   return .valid(f(a))
    case let .invalid(e): return .invalid(e)
    }
  }
}

func zip<A, B, E>(_ a: Validated<A, E>, _ b: Validated<B, E>) -> Validated<(A, B), E> {
  switch (a, b) {
  case let (.valid(a), .valid(b)):       return .valid((a, b))
  case let (.valid, .invalid(e)):        return .invalid(e)
  case let (.invalid(e), .valid):        return .invalid(e)
  case let (.invalid(e1), .invalid(e2)): return .invalid(e1 + e2)
  }
}

func zip<A, B, C, E>(with f: @escaping (A, B) -> C) -> (Validated<A, E>, Validated<B, E>) -> Validated<C, E> {
  return { zip($0, $1) |> map(f) }
}

//func zip<A, B, C, E>(_ a: Validated<A, E>, _ b: Validated<B, E>, _ c: Validated<C, E>) -> Validated<(A, B, C), E> {
//  return zip(a, zip2(b, c)) |> map { a, bc in (a, bc.0, bc.1) }
//}

//func zip<A, B, C, D, E>(with f: @escaping (A, B, C) -> D) -> (Validated<A, E>, Validated<B, E>, Validated<C, E>) -> Validated<D, E> {
//    return { zip($0, $1, $2) |> map(f) }
//}

func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
  guard let unwrappedA = a, let unwrappedB = b else { return nil }
  return (unwrappedA, unwrappedB)
}
