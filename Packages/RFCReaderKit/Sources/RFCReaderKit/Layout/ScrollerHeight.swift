import CoreGraphics
import Foundation

/// The document height the scroller's knob is drawn against, which follows the
/// `HeightModel` without ever jumping under the reader: frozen while they scroll or
/// drag the knob, eased to the model's total over `easeDuration` once they stop,
/// and moved at once by a change of column.
public struct ScrollerHeight: Sendable, Equatable {
  public static let easeDuration: TimeInterval = 0.15

  public private(set) var shown: CGFloat
  private var target: CGFloat
  private var easeFrom: CGFloat
  private var easeStart: TimeInterval?
  private var isInteracting = false

  public init(total: CGFloat) {
    shown = total
    target = total
    easeFrom = total
  }

  public var isEasing: Bool { easeStart != nil }

  public mutating func modelChanged(to total: CGFloat, now: TimeInterval) {
    target = total
    guard !isInteracting, total != shown else { return }
    easeFrom = shown
    easeStart = now
  }

  public mutating func columnChanged(to total: CGFloat) {
    target = total
    shown = total
    easeStart = nil
  }

  /// Freezes the knob's height where it is.
  public mutating func interactionBegan() {
    isInteracting = true
    easeStart = nil
  }

  public mutating func interactionEnded(now: TimeInterval) {
    guard isInteracting else { return }
    isInteracting = false
    guard target != shown else { return }
    easeFrom = shown
    easeStart = now
  }

  public mutating func advance(to now: TimeInterval) {
    guard let easeStart else { return }
    let progress = min(1, max(0, (now - easeStart) / Self.easeDuration))
    let eased = 1 - pow(1 - progress, 3)
    shown = easeFrom + (target - easeFrom) * CGFloat(eased)
    if progress >= 1 {
      shown = target
      self.easeStart = nil
    }
  }
}
