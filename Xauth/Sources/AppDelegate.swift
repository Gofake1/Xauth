//
//  AppDelegate.swift
//  Xauth
//
//  Created by David on 10/4/19.
//  Copyright © 2019 David Wu. All rights reserved.
//

import Combine
import ComposableArchitecture
import SwiftUI

private let appStore = Store(
  initialState: AppState(),
  reducer:      Reducer.combine(
    appReducer,
    Reducer { state, action, environment in
      switch action {
      case let .updateTime(date):
        mainWindowToolbarDelegate.updateCountdown(date)
        return .none
      default:
        return .none
      }
    }
  ),
  environment:  .init(
    keychain:     .real,
    keychainRefs: .real(.standard, key: "keychainRefs"),
    logging:      Logging.os_log().concatenate(logWindowLogging),
    makeUUID:     UUID.init,
    otpFactory:   .init(),
    otpList:      .init(makeDate: Date.init),
    qrScan:       qrScan,
    tokenCoding:  .otpAuthURL()
  )
)
private let appViewStore = ViewStore(appStore)
private let mainWindowToolbarDelegate = MainWindowToolbarDelegate()
private let mainWindow: NSWindow = {
  let appView = AppView(store: appStore).frame(minWidth: 200, minHeight: 200)
  let window  = NSWindow(title: "Xauth", styleMask: [.titled, .closable, .miniaturizable, .resizable])
  let toolbar = NSToolbar(identifier: "Xauth")
  toolbar.allowsUserCustomization = true
  toolbar.autosavesConfiguration  = true
  toolbar.delegate                = mainWindowToolbarDelegate
  toolbar.displayMode             = .iconOnly
  window.contentView               = NSHostingView(rootView: appView)
  window.isExcludedFromWindowsMenu = true
  window.toolbar                   = toolbar
  return window
}()
private let logWindowLogging = Logging {
  logWindowTextView.textStorage?.append(.init(string: $0))
  logWindowTextView.scrollToEndOfDocument(nil)
  logWindow.makeKeyAndOrderFront(nil)
}
private let logWindowTextView: NSTextView = {
  let view = NSTextView()
  view.autoresizingMask        = [.width]
  view.isEditable              = false
  view.isHorizontallyResizable = false
  view.isVerticallyResizable   = true
  return view
}()
private let logWindow: NSWindow = {
  let window     = NSWindow(contentRect: .init(x: 0, y: 0, width: 150, height: 100), title: "Xauth Log", styleMask: [.titled, .closable, .resizable])
  let scrollView = NSScrollView()
  scrollView.documentView        = logWindowTextView
  scrollView.hasVerticalScroller = true
  window.contentView               = scrollView
  window.isExcludedFromWindowsMenu = true
  return window
}()
private var cancellables: Set<AnyCancellable> = []
private var addTokenFormWindow: Window?
private var qrScanView: NSView?
private var qrScanWindow: Window?

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    appViewStore.send(.setup)
    
    WallClock_30_Seconds(now: Date())
      .sink { appViewStore.send(.updateTime($0)) }
      .store(in: &cancellables)
    
    appStore
      .scope(state: { $0.addTokenForm }, action: { AppAction.newToken(.addTokenForm($0)) })
      .ifLet(then: {
        let window = Window(title: "New Passcode", styleMask: [.titled, .closable, .resizable])
        window.contentView = NSHostingView(rootView: AddTokenFormView(store: $0))
        window.onClose     = { appViewStore.send(.closeWindow(.addTokenForm)) }
        window.makeKeyAndOrderFront(nil)
        addTokenFormWindow = window
      }, else: {
        addTokenFormWindow?.closeForReal()
        addTokenFormWindow = nil
      })
      .store(in: &cancellables)
    
    appStore
      .scope(state: { $0.qrScan })
      .ifLet(then: {
        let view   = NSHostingView(rootView: QRScanView(store: $0))
        let window = Window(title: "QR Code", styleMask: [.titled, .closable, .resizable])
        window.isOpaque        = false
        window.backgroundColor = .init(white: 0, alpha: 0.2)
        window.contentView     = view
        window.onClose         = { appViewStore.send(.closeWindow(.qrScan)) }
        window.makeKeyAndOrderFront(nil)
        qrScanView   = view
        qrScanWindow = window
      }, else: {
        qrScanWindow?.closeForReal()
        qrScanView   = nil
        qrScanWindow = nil
      })
      .store(in: &cancellables)
    
    appViewStore.publisher.passcodes
      .sink { mainWindow.subtitle = "\($0.count) passcodes" }
      .store(in: &cancellables)
    
    mainWindow.makeKeyAndOrderFront(nil)
  }
  
  @IBAction func newTokenAction(_ sender: NSMenuItem) {
    appViewStore.send(.showQRScan)
  }
  
  @IBAction func showXauthWindow(_ sender: NSMenuItem) {
    mainWindow.makeKeyAndOrderFront(sender)
  }
  
  @IBAction func showLogWindow(_ sender: NSMenuItem) {
    logWindow.makeKeyAndOrderFront(sender)
  }
}

extension NSWindow {
  fileprivate convenience init(contentRect: NSRect = .zero, title: String, styleMask: StyleMask) {
    self.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
    self.title = title
    self.isReleasedWhenClosed = false
    self.setFrameAutosaveName(title)
  }
}

private class Window: NSWindow {
  var onClose: () -> Void = {}
  
  // Don't let window state and app state go out of sync -- window state should be derived from app state
  override func close() {
    self.onClose()
  }
  
  func closeForReal() {
    super.close()
  }
}

private class CountdownView: NSView {
  private let backgroundRing: CAShapeLayer = {
    let layer = CAShapeLayer()
    layer.fillColor = nil
    layer.lineWidth = 2
    layer.path      = CGPath(ellipseIn: .init(x: 1, y: 1, width: 16, height: 16), transform: nil)
    return layer
  }()
  private let foregroundRing: CAShapeLayer = {
    let rotation   = CGAffineTransform(rotationAngle: 3/2 * .pi)
    let reflection = CGAffineTransform(scaleX: 1, y: -1)
    var transform  = rotation.concatenating(reflection)
    
    let layer = CAShapeLayer()
    layer.fillColor = nil
    layer.lineWidth = 2
    withUnsafePointer(to: &transform) {
      layer.path = CGPath(ellipseIn: .init(x: 1, y: 1, width: 16, height: 16), transform: $0)
    }
    return layer
  }()
  
  override var intrinsicContentSize: NSSize { .init(width: 18, height: 18) }
  override var wantsUpdateLayer:     Bool   { true }
  
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    self.needsDisplay = true
  }
  
  override func updateLayer() {
    self.backgroundRing.strokeColor = NSColor.controlColor.cgColor
    self.foregroundRing.strokeColor = NSColor.controlTextColor.cgColor
  }
  
  func setup() {
    self.wantsLayer = true
    self.layer?.addSublayer(self.backgroundRing)
    self.layer?.addSublayer(self.foregroundRing)
  }
  
  func startAnimation(_ beginTime: CFTimeInterval) {
    let animation = CABasicAnimation(keyPath: #keyPath(CAShapeLayer.strokeStart))
    animation.duration              = 30
    animation.fromValue             = 0
    animation.toValue               = 1
    animation.beginTime             = beginTime
    animation.isRemovedOnCompletion = false // The expanded search field can push the countdown out of the toolbar and stop its animation
    self.foregroundRing.removeAnimation(forKey: "countdown")
    self.foregroundRing.add(animation, forKey: "countdown")
  }
}

private class MainWindowToolbarDelegate: NSObject, NSToolbarDelegate, NSSearchFieldDelegate {
  private let countdownView: CountdownView = {
    let view = CountdownView()
    view.setup()
    return view
  }()
  
  func updateCountdown(_ startDate: Date) {
    let beginTime = CACurrentMediaTime() + startDate.timeIntervalSinceNow
    self.countdownView.startAnimation(beginTime)
  }
  
  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    if itemIdentifier.rawValue == "countdown" {
      let item = NSToolbarItem(itemIdentifier: .init("countdown"))
      item.label = "Countdown"
      item.view  = self.countdownView
      return item
    } else if itemIdentifier.rawValue == "search" {
      let searchField = NSSearchField()
      searchField.delegate = self
      let item = NSSearchToolbarItem(itemIdentifier: .init("search"))
      item.searchField = searchField // TODO: fix ambiguous size
      return item
    }
    return nil
  }
  
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.init("countdown"), .init("search")]
  }
  
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.init("countdown"), .init("search")]
  }
  
  func controlTextDidChange(_ obj: Notification) {
    guard let searchField = obj.object as? NSSearchField else { return }
    appViewStore.send(.updateFilterText(searchField.stringValue))
  }
}

private class WallClock_30_Seconds: Publisher {
  typealias Output  = Date
  typealias Failure = Never
  
  private let subject: CurrentValueSubject<Date, Never>
  private let runloop: RunLoop
  
  init(now: Date, calendar: Calendar = .current, runloop: RunLoop = .main) {
    let nowSecond  = calendar.dateComponents([.second], from: now).second!
    let nextSecond = ((nowSecond / 30) * 30 + 30) % 60
    let fireDate   = calendar.nextDate(after: now, matching: .init(second: nextSecond), matchingPolicy: .nextTime)!
    self.subject = .init(fireDate - 30)
    self.runloop = runloop
    self.runloop.add(
      .init(fireAt: fireDate, interval: 0, target: self, selector: #selector(fire), userInfo: nil, repeats: false),
      forMode: .common
    )
  }
  
  func receive<S>(subscriber: S) where S: Subscriber, S.Input == Date, S.Failure == Never {
    self.subject.receive(subscriber: subscriber)
  }
  
  @objc private func fire() {
    self.subject.value += 30
    self.runloop.add(
      .init(fireAt: self.subject.value + 30, interval: 0, target: self, selector: #selector(fire), userInfo: nil, repeats: false),
      forMode: .common
    )
  }
}

private let qrScan: () -> String? = {
  let rectInDisplaySpace: (CGRect, CGDirectDisplayID) -> CGRect = {
    let displayBounds = CGDisplayBounds($1)
    return .init(
      origin: .init(
        x: $0.origin.x,
        y: displayBounds.maxY - $0.maxY
      ),
      size: $0.size
    )
  }
  
  guard let window = qrScanWindow, let view = qrScanView else { return nil }
  let rectInScreenSpace = window.convertToScreen(view.convert(view.frame, to: nil))
  var displayId: CGDirectDisplayID = 0
  var displayCount: UInt32 = 0
  let status = CGGetDisplaysWithRect(rectInScreenSpace, 1, &displayId, &displayCount)
  guard status == .success else {
    fatalError("1") //*
  }
  let rect = rectInDisplaySpace(rectInScreenSpace, displayId)
  guard let image = CGDisplayCreateImage(displayId, rect: rect) else {
    fatalError("2") //*
  }
  let qrDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
  let features   = qrDetector.features(in: CIImage(cgImage: image))
  let messages   = features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
  return messages.first
}
