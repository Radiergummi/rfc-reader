import XCTest

/// The hand checks an iOS change asks for, run in the Simulator from outside the app
/// (#743): `make hand-check CHECK=<test name>`.
///
/// Each check launches the built app, taps, swipes and reads it as a person would,
/// and saves a screenshot at every step it names, which `make hand-check` exports to
/// `hand-checks/<name>/`. An assertion pins what the step should show; the
/// screenshots are what a person looks at. None of it runs in `make check` or CI.
@MainActor
final class HandChecks: XCTestCase {
  private let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
    // In English whatever the Simulator's language, so the labels below match.
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
  }

  // MARK: - The reader stack (#263)

  /// A citation pushes the cited RFC; the back button and the edge swipe pop it, and
  /// an edge swipe let go early leaves it where it is.
  func testReaderStackPushAndPop() throws {
    launch(opening: "rfc://8174")
    try skipUnlessCompact()
    waitForReader("RFC 8174")
    screenshot("1 RFC 8174")

    followCitation("RFC 2119")
    waitForReader("RFC 2119")
    screenshot("2 pushed RFC 2119")

    app.navigationBars["RFC 2119"].buttons["BackButton"].tap()
    waitForReader("RFC 8174")
    screenshot("3 back button")

    followCitation("RFC 2119")
    waitForReader("RFC 2119")
    swipeFromLeadingEdge(to: 0.15)
    // Once the cancelled pop has animated back, during which both bars are there.
    XCTAssertTrue(app.navigationBars["RFC 8174"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["RFC 2119"].exists)
    screenshot("4 edge swipe let go early")

    swipeFromLeadingEdge(to: 0.9)
    waitForReader("RFC 8174")
    screenshot("5 edge swipe")
  }

  /// A deep link while a stack is open replaces the stack: back from it leads to the
  /// list, not to the reader it replaced.
  func testDeepLinkReplacesTheStack() throws {
    launch(opening: "rfc://8174")
    try skipUnlessCompact()
    waitForReader("RFC 8174")
    followCitation("RFC 2119")
    waitForReader("RFC 2119")
    screenshot("1 stack of two")

    open("rfc://1149")
    waitForReader("RFC 1149")
    screenshot("2 deep link")

    app.navigationBars["RFC 1149"].buttons["BackButton"].tap()
    XCTAssertTrue(app.navigationBars["All RFCs"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.navigationBars["RFC 2119"].exists)
    XCTAssertFalse(app.navigationBars["RFC 8174"].exists)
    screenshot("3 back from the deep link")
  }

  // MARK: - Drafts (#728)

  /// A draft opened over an RFC row stays on screen, and so does an RFC opened over
  /// the draft: a draft has no row, and the list losing its selection must not take
  /// the reader back to the list. A draft opened from the list shows its reader as a
  /// row does, and Back from it leads to the list.
  ///
  /// Screenshots 2, 3 and 4 are where to look for a second bottom bar above the
  /// reader's, or an empty capsule, which the accessibility tree never shows: drawn
  /// there while the list's selection was cleared and the reader popped and pushed
  /// back at once (fixed 24 October 2026).
  func testDraftOverAnRFCRow() throws {
    launch(opening: "rfc://8174")
    try skipUnlessCompact()
    waitForReader("RFC 8174")
    screenshot("1 RFC 8174")

    open("rfc://draft-ietf-quic-http-34")
    waitForReader("draft-ietf-quic-http-34")
    screenshot("2 draft")
    // Long enough for a pop the list's selection asked for to have run.
    sleep(3)
    XCTAssertTrue(app.navigationBars["draft-ietf-quic-http-34"].exists, "the draft was hidden")
    screenshot("3 draft, still")

    open("rfc://8174")
    waitForReader("RFC 8174")
    sleep(3)
    XCTAssertTrue(app.navigationBars["RFC 8174"].exists, "the RFC was hidden")
    XCTAssertFalse(app.navigationBars["draft-ietf-quic-http-34"].exists)
    screenshot("4 RFC over the draft")

    app.navigationBars["RFC 8174"].buttons["BackButton"].tap()
    XCTAssertTrue(app.navigationBars["All RFCs"].waitForExistence(timeout: 5))
    open("rfc://draft-ietf-quic-http-34")
    waitForReader("draft-ietf-quic-http-34")
    screenshot("5 draft from the list")

    app.navigationBars["draft-ietf-quic-http-34"].buttons["BackButton"].tap()
    XCTAssertTrue(app.navigationBars["All RFCs"].waitForExistence(timeout: 5))
    screenshot("6 back to the list")
  }

  // MARK: - What a headless launch cannot do

  /// A long press on a citation shows its preview, and letting go keeps the reader.
  func testCitationLongPress() {
    launch(opening: "rfc://8174")
    waitForReader("RFC 8174")

    let link = citation("RFC 2119")
    XCTAssertTrue(link.waitForExistence(timeout: 30))
    link.press(forDuration: 1.5)
    XCTAssertTrue(app.buttons["Copy Link"].waitForExistence(timeout: 5), "no preview and menu")
    screenshot("1 long press")
    // Dismissed with a tap outside the preview, at the top of the screen.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    waitForReader("RFC 8174")
    screenshot("2 dismissed")
  }

  /// Turning on the bookmark notifications asks the system, and allowing it keeps the
  /// setting on, and the app still launches with it on. The system asks only once per
  /// install, which `make hand-check`'s first launch gives every run.
  func testNotificationPermission() {
    launch(opening: "rfc://8174")
    waitForReader("RFC 8174")
    app.buttons["Text Size"].tap()
    app.buttons["Reading Settings…"].tap()

    // The row's label is the title and the description below it; the switch is
    // the control inside the row.
    let row = app.switches.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Notify me about bookmarked RFCs")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    let toggle = row.switches.firstMatch
    screenshot("1 settings")
    toggle.tap()

    allowSystemAlert(screenshotName: "2 system asks")
    // The switch turns on as it is tapped, before the system answers; refused, it
    // turns off again and says so. So it is read once that answer had time to land.
    XCTAssertFalse(
      app.staticTexts["Notifications for RFC Reader are turned off in System Settings."]
        .waitForExistence(timeout: 3))
    XCTAssertEqual(toggle.value as? String, "1")
    screenshot("3 allowed")

    // The next launch, with the setting on, asks iOS for the daily refresh, which
    // crashed while that came before the scene that handles it (#980).
    app.terminate()
    launch(opening: "rfc://8174")
    waitForReader("RFC 8174")
    screenshot("4 relaunched")
    // Still on after the relaunch. Whether it asked iOS shows only in the log.
    app.buttons["Text Size"].tap()
    app.buttons["Reading Settings…"].tap()
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertEqual(row.switches.firstMatch.value as? String, "1")
    screenshot("5 still on")
  }

  // MARK: - Find (#943)

  /// More ▸ Find in Document is offered over a text and nowhere else: not over the
  /// page of a scan or of a text that only points to its original, though the
  /// pointer's Original Text is a text again.
  func testFindOnlyOverAText() {
    launch(opening: "rfc://8174")
    waitForReader("RFC 8174")
    XCTAssertTrue(citation("RFC 2119").waitForExistence(timeout: 30))
    XCTAssertTrue(findInDocument().isEnabled, "no Find over the rendered document")
    screenshot("1 rendered document")
    closeMenu()

    open("rfc://8")
    XCTAssertTrue(app.staticTexts["Published as PDF"].waitForExistence(timeout: 30))
    XCTAssertFalse(findInDocument().isEnabled, "Find over a scan's page")
    screenshot("2 scan")
    closeMenu()

    open("rfc://1119")
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Published as"))
        .firstMatch.waitForExistence(timeout: 30))
    XCTAssertFalse(findInDocument().isEnabled, "Find over a pointer's page")
    screenshot("3 pointer")

    app.buttons["Original Text"].tap()
    XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 30))
    let find = findInDocument()
    XCTAssertTrue(find.isEnabled, "no Find over the pointer's Original Text")
    screenshot("4 pointer's original text")
    find.tap()
    screenshot("5 find over the original text")
  }

  /// Opens More and returns its Find in Document.
  private func findInDocument() -> XCUIElement {
    app.buttons["More"].firstMatch.tap()
    let item = app.buttons["Find in Document"]
    XCTAssertTrue(item.waitForExistence(timeout: 5), "no Find in Document in More")
    return item
  }

  /// Dismisses an open menu with a tap outside it, at the top of the screen.
  private func closeMenu() {
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
  }

  // MARK: - The Info pane (#577)

  /// A long press on a format row offers Open, Share and Download; Download fetches
  /// the file and offers it to Save to Files, and once that is done, a Download from
  /// another row of the card offers its file in turn.
  func testFormatRowDownload() {
    launch(opening: "rfc://8174")
    waitForReader("RFC 8174")
    app.buttons["Info"].tap()

    // RFC 8174 is published as text and HTML only.
    let text = app.buttons["Plain Text"].firstMatch
    XCTAssertTrue(text.waitForExistence(timeout: 10), "no Plain Text row in the Info pane")
    // The Formats card is below the medium sheet's fold.
    for _ in 0..<5 where !text.isHittable {
      app.swipeUp()
    }
    text.press(forDuration: 1.5)
    XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5), "no menu")
    XCTAssertTrue(app.buttons["Share…"].exists)
    XCTAssertTrue(app.buttons["Download"].exists)
    screenshot("1 long press")

    for (step, row) in [(2, text), (4, app.buttons["HTML"].firstMatch)] {
      if step > 2 {
        row.press(forDuration: 1.5)
        XCTAssertTrue(app.buttons["Download"].waitForExistence(timeout: 5), "no menu on HTML")
      }
      app.buttons["Download"].tap()
      // Save to Files is the system's document picker, which saves with Save.
      let save = app.buttons["Save"].firstMatch
      XCTAssertTrue(save.waitForExistence(timeout: 30), "no Save to Files, step \(step)")
      screenshot("\(step) Save to Files")
      save.tap()
      XCTAssertTrue(save.waitForNonExistence(timeout: 10), "Save to Files stayed, step \(step)")
      screenshot("\(step + 1) saved")
    }
  }

  // MARK: - Go to RFC (#579)

  /// The library's # opens Go to RFC on a text keyboard; `BCP 14` lists its members
  /// and not RFC 14, and Open opens the first.
  func testGoToRFC() {
    app.launch()
    dismissStoreWarning()
    waitForIndex()
    // The bar's button, at the foot of the screen: the keyboard command of the same
    // name is listed too, at the screen's middle.
    let goTo = app.buttons.matching(identifier: "Go to RFC").allElementsBoundByIndex
      .max { $0.frame.minY < $1.frame.minY }
    goTo?.tap()

    let field = app.textFields["RFC number, BCP 14, or a link"]
    XCTAssertTrue(field.waitForExistence(timeout: 5), "no Go to RFC sheet")
    // A text keyboard: letters as well as digits.
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "no keyboard")
    XCTAssertTrue(app.keyboards.keys["q"].exists)
    screenshot("1 keyboard")

    field.typeText("BCP 14")
    XCTAssertTrue(
      app.buttons["RFC 2119"].waitForExistence(timeout: 5)
        || app.staticTexts["RFC 2119"].waitForExistence(timeout: 1), "RFC 2119 not listed")
    XCTAssertTrue(app.staticTexts["RFC 8174"].exists, "RFC 8174 not listed")
    XCTAssertFalse(app.staticTexts["RFC 14"].exists, "BCP 14 listed RFC 14")
    screenshot("2 typed BCP 14")

    app.buttons["Open"].tap()
    waitForReader("RFC 2119")
    screenshot("3 opened")
  }

  // MARK: - The References panel (#580)

  /// A long press on a References row shows its RFC's preview above the row's menu,
  /// as a citation's in the prose does.
  func testReferenceRowPreview() {
    launch(opening: "rfc://8174")
    waitForReader("RFC 8174")
    app.buttons["Contents"].firstMatch.tap()
    let references = app.buttons["References"].firstMatch
    XCTAssertTrue(references.waitForExistence(timeout: 10), "no References tab")
    references.tap()

    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "RFC 2119"))
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no RFC 2119 row in References")
    screenshot("1 references")
    row.press(forDuration: 1.5)
    XCTAssertTrue(app.buttons["Copy Link"].waitForExistence(timeout: 5), "no menu")
    // The preview is RFC 2119's, whose title is there once it has loaded.
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Requirement Levels"))
        .firstMatch.waitForExistence(timeout: 30), "no preview of RFC 2119")
    screenshot("2 long press")
  }

  // MARK: - Steps

  /// Launches the app, waits for its index, and opens `url` in it.
  private func launch(opening url: String) {
    app.launch()
    dismissStoreWarning()
    waitForIndex()
    open(url)
  }

  /// Opens a link through the system, as one from another app comes, in the running
  /// app. It goes to the app without the "Open in" prompt `xcrun simctl openurl`
  /// stops at. Not `app.open(_:)`, which launches the app anew, and loses what was
  /// open.
  private func open(_ url: String) {
    XCUIDevice.shared.system.open(URL(string: url)!)
    XCTAssertEqual(app.state, .runningForeground)
  }

  /// Waits for the RFC index, which the first launch downloads and reads, until the
  /// library shows how many RFCs there are ("9,848"), a count only the index gives.
  /// Every check starts from a first launch (`make hand-check`), and taps made while
  /// the index was still being read were lost or landed late: a long press that
  /// opened the link instead, a switch that never asked the system.
  private func waitForIndex() {
    let count = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES %@", "[0-9]{1,3}(,[0-9]{3})+")
    ).firstMatch
    XCTAssertTrue(count.waitForExistence(timeout: 120), "the index never loaded")
  }

  /// An unsigned build has no iCloud container, so its store falls back to memory and
  /// says so in an alert at launch (`AppData.storeWarning`). It is dismissed here
  /// rather than in every check, after a screenshot of it.
  private func dismissStoreWarning() {
    let alert = app.alerts["Your bookmarks couldn't be loaded"]
    guard alert.waitForExistence(timeout: 3) else { return }
    screenshot("store warning")
    alert.buttons.firstMatch.tap()
  }

  /// Taps the button of a system alert that allows, such as the notification
  /// permission's. The system's alerts are SpringBoard's, in the Simulator's language
  /// rather than the app's, so it is found by position: allowing is the last button.
  private func allowSystemAlert(screenshotName: String) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let alert = springboard.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 10), "the system never asked")
    XCTAssertTrue(alert.buttons.firstMatch.waitForExistence(timeout: 5))
    screenshot(screenshotName)
    alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
  }

  /// Skips a check of the reader stack outside compact width. In regular width, as on
  /// an iPad, the stack is the split view's detail column, beside the list: its root
  /// has no back button, and the screen's leading edge is the sidebar's.
  private func skipUnlessCompact() throws {
    try XCTSkipUnless(
      app.windows.firstMatch.horizontalSizeClass == .compact,
      "the reader stack is compact width's; this Simulator is in regular width")
  }

  private func waitForReader(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(
      app.navigationBars[title].waitForExistence(timeout: 30), "no reader titled \(title)",
      file: file, line: line)
  }

  /// Taps the first link to `label` in the reader's text, once the document has been
  /// built: the title is there before the text is.
  private func followCitation(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
    let link = citation(label)
    XCTAssertTrue(link.waitForExistence(timeout: 30), "no link to \(label)", file: file, line: line)
    link.tap()
  }

  /// The first link to `label` in the reader's text. The text joins "RFC" and its
  /// number with a no-break space, so `label` is written with a plain one and matched
  /// with that.
  private func citation(_ label: String) -> XCUIElement {
    app.links[label.replacingOccurrences(of: " ", with: "\u{00A0}")].firstMatch
  }

  /// Drags from the screen's leading edge to `fraction` of its width, the way a thumb
  /// starts the interactive pop.
  private func swipeFromLeadingEdge(to fraction: CGFloat) {
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
  }

  private func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
