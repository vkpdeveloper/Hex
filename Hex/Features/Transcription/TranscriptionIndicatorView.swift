//
//  TranscriptionIndicatorView.swift
//  Hex
//
//  Created by Kit Langton on 1/25/25.
//  Redesigned as a Wispr Flow-style pill with a live waveform.

import Inject
import Pow
import SwiftUI

struct TranscriptionIndicatorView: View {
  @ObserveInjection var inject

  enum Status {
    case hidden
    case optionKeyPressed
    case recording
    case transcribing
    case prewarming
  }

  var status: Status
  var meter: Meter

  /// Optional interactive affordances. When `nil`, the buttons render as
  /// purely decorative (see `InvisibleWindow` hit-testing for how clicks are
  /// routed only over the pill).
  var onCancel: (() -> Void)? = nil
  var onConfirm: (() -> Void)? = nil
  /// Reports the pill's on-screen frame so the host window can constrain mouse
  /// events to the pill and keep the rest of the screen click-through.
  var pillFrameHolder: PillFrameHolder? = nil

  // MARK: - Layout constants

  private let pillHeight: CGFloat = 28
  private let buttonSize: CGFloat = 18

  private var isExpanded: Bool {
    status == .recording || status == .transcribing || status == .prewarming
  }

  private var isProcessing: Bool {
    status == .transcribing || status == .prewarming
  }

  @State private var transcribeEffect = 0

  var body: some View {
    ZStack {
      Group {
        if isExpanded {
          expandedPill
        } else {
          // optionKeyPressed (and the shape `hidden` animates out from):
          // a tiny dark lozenge.
          Capsule()
            .fill(Color(white: 0.08).opacity(0.95))
            .frame(width: 16, height: 6)
        }
      }
      .opacity(status == .hidden ? 0 : 1)
      .scaleEffect(status == .hidden ? 0.5 : 1, anchor: .bottom)
      .blur(radius: status == .hidden ? 6 : 0)
      .animation(.spring(response: 0.35, dampingFraction: 0.75), value: status)

      // Show tooltip when prewarming
      if status == .prewarming {
        Text("Model prewarming...")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(Color.black.opacity(0.8))
          )
          .offset(y: -28)
          .transition(.opacity)
          .zIndex(2)
      }
    }
    .enableInjection()
  }

  // MARK: - Pill

  private var expandedPill: some View {
    HStack(spacing: 8) {
      circleButton(
        systemName: "xmark",
        foreground: .white,
        background: Color(white: 0.25),
        action: onCancel
      )

      WaveformView(meter: meter, mode: isProcessing ? .processing : .live)
        .padding(.horizontal, 2)

      circleButton(
        systemName: "checkmark",
        foreground: .black,
        background: .white,
        action: onConfirm
      )
    }
    .padding(.horizontal, 6)
    .frame(height: pillHeight)
    .background(pillBackground)
    .changeEffect(.shine(angle: .degrees(0), duration: 0.6), value: transcribeEffect)
    .compositingGroup()
    .background(frameReporter)
    .task(id: status == .transcribing) {
      while status == .transcribing, !Task.isCancelled {
        transcribeEffect += 1
        try? await Task.sleep(for: .seconds(0.25))
      }
    }
  }

  private var pillBackground: some View {
    Capsule()
      .fill(Color(white: 0.08).opacity(0.95))
      .overlay(
        Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
  }

  /// Publishes the pill's global frame to the host window so mouse events can
  /// be constrained to the pill (keeps the rest of the screen click-through).
  private var frameReporter: some View {
    GeometryReader { proxy in
      Color.clear
        .onAppear { pillFrameHolder?.frame = proxy.frame(in: .global) }
        .onChange(of: proxy.frame(in: .global)) { _, frame in
          pillFrameHolder?.frame = frame
        }
        .onDisappear { pillFrameHolder?.frame = .zero }
    }
  }

  private func circleButton(
    systemName: String,
    foreground: Color,
    background: Color,
    action: (() -> Void)?
  ) -> some View {
    Button {
      action?()
    } label: {
      ZStack {
        Circle().fill(background)
        Image(systemName: systemName)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(foreground)
      }
      .frame(width: buttonSize, height: buttonSize)
    }
    .buttonStyle(.plain)
    .allowsHitTesting(action != nil)
  }
}

// MARK: - Waveform

/// A scrolling live waveform of vertical bars. In `.live` mode the bars react to
/// the mic meter and scroll left; in `.processing` mode they animate a gentle
/// left-to-right sweep. All state is UI-local — no reducer state is touched.
private struct WaveformView: View {
  enum Mode { case live, processing }

  var meter: Meter
  var mode: Mode

  private let barCount = 14
  private let minHeight: CGFloat = 3
  private let maxHeight: CGFloat = 16

  @State private var bars: [CGFloat] = Array(repeating: 3, count: 14)

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
        Capsule()
          .fill(Color.white.opacity(mode == .processing ? 0.8 : 0.95))
          .frame(width: 2, height: height)
      }
    }
    .frame(height: maxHeight)
    .animation(.smooth(duration: 0.12), value: bars)
    .onChange(of: meter) { _, newValue in
      guard mode == .live else { return }
      let level = min(1, max(newValue.averagePower * 3, newValue.peakPower * 3 * 0.6))
      pushLive(CGFloat(level))
    }
    .task(id: mode) {
      guard mode == .processing else { return }
      var phase = 0.0
      while !Task.isCancelled {
        phase += 0.35
        bars = (0 ..< barCount).map { index in
          let s = sin(phase + Double(index) * 0.5)
          return minHeight + CGFloat((s + 1) / 2) * (maxHeight - minHeight) * 0.7
        }
        try? await Task.sleep(for: .seconds(0.08))
      }
    }
  }

  private func pushLive(_ level: CGFloat) {
    var next = bars
    next.removeFirst()
    // Tiny jitter floor so silence still shows faint bars.
    let jitter = CGFloat.random(in: 0 ... 0.06)
    let normalized = max(level, jitter)
    next.append(minHeight + normalized * (maxHeight - minHeight))
    bars = next
  }
}

#Preview("HEX") {
  VStack(spacing: 16) {
    TranscriptionIndicatorView(status: .hidden, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .optionKeyPressed, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .recording, meter: .init(averagePower: 0.4, peakPower: 0.6))
    TranscriptionIndicatorView(status: .transcribing, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .prewarming, meter: .init(averagePower: 0, peakPower: 0))
  }
  .padding(40)
  .background(Color.gray.opacity(0.3))
}
