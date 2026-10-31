import CoreGraphics
import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Geometry: note markers")
struct NoteMarkerGeometryTests {
  private let first = UUID()
  private let second = UUID()
  private let third = UUID()

  @Test func `a marker is level with the line of its fragment that holds it`() {
    // A paragraph of two lines, at storage offset 100: the lines count from its start.
    let paragraph = NSAttributedString(string: "0123456789abcdefgh\n")
    let lines = [
      NSTextLineFragment(attributedString: paragraph, range: NSRange(location: 0, length: 10)),
      NSTextLineFragment(attributedString: paragraph, range: NSRange(location: 10, length: 8)),
    ]
    let fragment = FragmentLines(range: NSRange(location: 100, length: 19), lines: lines)
    #expect(FragmentGeometry.noteMarkerLine(at: 115, in: fragment) === lines[1])
    #expect(FragmentGeometry.noteMarkerLine(at: 100, in: fragment) === lines[0])
    // Past its lines, on the paragraph's closing newline: its first line.
    #expect(FragmentGeometry.noteMarkerLine(at: 118, in: fragment) === lines[0])
    #expect(
      FragmentGeometry.noteMarkerLine(at: 100, in: FragmentLines(range: fragment.range, lines: []))
        == nil)
  }

  @Test func `a marker stands level with its line`() {
    let markers = FragmentGeometry.noteMarkers(
      [FragmentGeometry.NoteLine(note: first, y: 120, height: 20, isLaidOut: true)],
      visible: 0...1000)
    #expect(markers == [FragmentGeometry.NoteMarker(notes: [first], y: 120, lineHeight: 20)])
  }

  @Test func `the notes of one line share a marker`() {
    let markers = FragmentGeometry.noteMarkers(
      [
        FragmentGeometry.NoteLine(note: first, y: 120, height: 20, isLaidOut: true),
        FragmentGeometry.NoteLine(note: second, y: 120.4, height: 20, isLaidOut: true),
      ], visible: 0...1000)
    #expect(markers.map(\.notes) == [[first, second]])
  }

  @Test func `a marker that would overlap the one above stacks beneath it`() {
    let markers = FragmentGeometry.noteMarkers(
      [
        FragmentGeometry.NoteLine(note: second, y: 130, height: 20, isLaidOut: true),
        FragmentGeometry.NoteLine(note: first, y: 120, height: 20, isLaidOut: true),
        FragmentGeometry.NoteLine(note: third, y: 400, height: 20, isLaidOut: true),
      ], visible: 0...1000)
    let below = 120 + FragmentGeometry.noteMarkerSize + FragmentGeometry.noteMarkerSpacing
    #expect(markers.map(\.notes) == [[first], [second], [third]])
    #expect(markers.map(\.y) == [120, below, 400])
  }

  @Test func `no marker stands on an estimate, or outside what is placed`() {
    let markers = FragmentGeometry.noteMarkers(
      [
        FragmentGeometry.NoteLine(note: first, y: 120, height: 20, isLaidOut: false),
        FragmentGeometry.NoteLine(note: second, y: 5000, height: 20, isLaidOut: true),
        FragmentGeometry.NoteLine(note: third, y: 300, height: 20, isLaidOut: true),
      ], visible: 0...1000)
    #expect(markers.map(\.notes) == [[third]])
  }

  @Test func `a marker sits in the trailing gutter, inside the view`() {
    let marker = FragmentGeometry.NoteMarker(notes: [first], y: 100, lineHeight: 22)
    let wide = FragmentGeometry.noteMarkerFrame(
      marker, containerOrigin: CGPoint(x: 80, y: 10), columnWidth: 600, viewWidth: 760)
    #expect(wide.minX == 684)
    #expect(wide.midY == CGFloat(10 + 100 + 11))
    let narrow = FragmentGeometry.noteMarkerFrame(
      marker, containerOrigin: CGPoint(x: 8, y: 10), columnWidth: 360, viewWidth: 376)
    #expect(narrow.maxX == 376)
  }
}
