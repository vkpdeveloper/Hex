//
//  InvisibleWindow.swift
//  Hex
//
//  Created by Kit Langton on 1/24/25.
//

import AppKit
import SwiftUI

/// Shared holder for the recording pill's on-screen frame (in SwiftUI `.global`
/// coordinates). The SwiftUI view writes to it; `PassthroughHostingView` reads
/// it during hit-testing so only the pill captures mouse events.
final class PillFrameHolder {
  var frame: CGRect = .zero
}

/// An `NSHostingView` that is click-through everywhere except over the pill's
/// reported frame. Returning `nil` from `hitTest` lets clicks fall through to
/// whatever app is behind the invisible window. If the frame is unset (`.zero`)
/// the entire view is transparent to the mouse — so we never block the screen.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
  var frameHolder: PillFrameHolder?

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let reported = frameHolder?.frame, reported.width > 1, reported.height > 1 else {
      return nil
    }

    let local = convert(point, from: superview)

    // SwiftUI `.global` frames use a top-left origin. `NSHostingView` is usually
    // flipped to match, but guard against both to stay robust across OS versions.
    let target: CGRect
    if isFlipped {
      target = reported
    } else {
      target = CGRect(
        x: reported.origin.x,
        y: bounds.height - reported.origin.y - reported.height,
        width: reported.width,
        height: reported.height
      )
    }

    return target.insetBy(dx: -6, dy: -6).contains(local) ? super.hitTest(point) : nil
  }
}

/// This allows us to render SwiftUI views anywhere on the screen, without dealing with the awkward
/// rendering issues that come with normal MacOS windows. Essentially, we create one giant invisible
/// window that covers the entire screen, and render our SwiftUI views into it.
///
/// I'm pretty sure this is what CleanShot X and other apps do to render their floating widgets.
/// But if there's a better way to do this, I'd love to know!
class InvisibleWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  /// When set, the window accepts mouse events only while the cursor is over
  /// the pill's frame. It must stay `ignoresMouseEvents = true` the rest of the
  /// time: once `ignoresMouseEvents` is false, macOS routes every click on the
  /// (full-screen) window to us — returning nil from hitTest does NOT pass
  /// clicks through to apps behind. See #freeze regression after pill redesign.
  var pillFrameHolder: PillFrameHolder?

  private var currentScreen: NSScreen?
  private var mouseMonitor: Any?
  private var localMouseMonitor: Any?

  init() {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let styleMask: NSWindow.StyleMask = [.fullSizeContentView, .borderless, .utilityWindow, .nonactivatingPanel]

    super.init(contentRect: screen.frame,
               styleMask: styleMask,
               backing: .buffered,
               defer: false)

    level = .statusBar
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    ignoresMouseEvents = true
    hidesOnDeactivate = false // Prevent hiding when app loses focus
    canHide = false
    collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]

    // Set initial frame
    updateToScreenWithMouse()

    // Start observing screen changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenDidChange),
      name: NSWindow.didChangeScreenNotification,
      object: nil
    )

    // Also observe screen parameters for resolution changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenDidChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )

    // Monitor mouse movements to detect screen boundary crossings and to
    // toggle interactivity when hovering the pill.
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
      self?.checkForScreenChange()
      self?.updateInteractivityForMouseLocation()
    }
    // Global monitors don't fire while the event lands in our own window, so a
    // local monitor is needed to notice the cursor leaving the pill.
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
      self?.updateInteractivityForMouseLocation()
      return event
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    if let monitor = mouseMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = localMouseMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  /// Accept mouse events only while the cursor is inside the pill's frame
  /// (with a small grace margin). Everywhere else the window must ignore mouse
  /// events entirely so clicks reach the apps behind it.
  private func updateInteractivityForMouseLocation() {
    guard let holder = pillFrameHolder else { return }
    let pill = holder.frame
    guard pill.width > 1, pill.height > 1 else {
      if !ignoresMouseEvents { ignoresMouseEvents = true }
      return
    }

    // NSEvent.mouseLocation is bottom-left screen coords; the pill frame is
    // SwiftUI .global (top-left, window-local). Convert mouse into that space.
    let mouse = NSEvent.mouseLocation
    let localX = mouse.x - frame.origin.x
    let localTopY = frame.height - (mouse.y - frame.origin.y)
    let hovering = pill.insetBy(dx: -8, dy: -8).contains(CGPoint(x: localX, y: localTopY))

    if ignoresMouseEvents == hovering {
      ignoresMouseEvents = !hovering
    }
  }

  private func updateToScreenWithMouse() {
    let mouseLocation = NSEvent.mouseLocation
    guard let screenWithMouse = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }
    currentScreen = screenWithMouse
    setFrame(screenWithMouse.frame, display: true)
  }

  private func checkForScreenChange() {
    let mouseLocation = NSEvent.mouseLocation
    guard let newScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }
    
    // Only update if screen actually changed
    if newScreen !== currentScreen {
      currentScreen = newScreen
      setFrame(newScreen.frame, display: true)
    }
  }

  @objc private func screenDidChange(_: Notification) {
    updateToScreenWithMouse()
  }
}

extension InvisibleWindow: NSWindowDelegate {
  static func fromView<V: View>(_ view: V) -> InvisibleWindow {
    let window = InvisibleWindow()
    window.contentView = NSHostingView(rootView: view)
    window.delegate = window
    return window
  }

  /// Interactive variant: the window stays `ignoresMouseEvents = true` except
  /// while the cursor hovers the pill's frame (see
  /// `updateInteractivityForMouseLocation`). `PassthroughHostingView` then
  /// confines hit-testing to the pill itself as a second layer of safety.
  static func fromView<V: View>(_ view: V, frameHolder: PillFrameHolder) -> InvisibleWindow {
    let window = InvisibleWindow()
    let hostingView = PassthroughHostingView(rootView: view)
    hostingView.frameHolder = frameHolder
    window.contentView = hostingView
    window.pillFrameHolder = frameHolder
    window.delegate = window
    return window
  }
}
