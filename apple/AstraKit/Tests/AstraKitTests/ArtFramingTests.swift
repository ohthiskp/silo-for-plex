import XCTest

@testable import AstraKit

final class ArtFramingTests: XCTestCase {
  /// A 16:9 backdrop on a 390 pt iPhone, art area 410 pt, logo at 341 pt.
  private func frame(_ focus: CGRect?) -> CGRect {
    ArtFraming.frame(
      boxWidth: 390, zoneHeight: 410, aspect: 16.0 / 9.0, limitY: 341, topOffset: 20, minTop: 100, focus: focus)
  }

  func testNoFocusCoversTheArtAreaCentred() {
    let r = frame(nil)
    XCTAssertEqual(r.minY, 20, accuracy: 0.001)
    XCTAssertEqual(r.height, 390, accuracy: 0.001)
    XCTAssertEqual(r.midX, 195, accuracy: 0.001)
  }

  func testFacesLowInTheArtEndAboveTheLogo() {
    // Faces down to 84 % of the picture (Mario's Luigi).
    let focus = CGRect(x: 0.3, y: 0.15, width: 0.4, height: 0.69)
    let r = frame(focus)
    XCTAssertLessThanOrEqual(r.minY + focus.maxY * r.height, 341.5)
    // Still edge to edge across the screen.
    XCTAssertLessThanOrEqual(r.minX, 0)
    XCTAssertGreaterThanOrEqual(r.maxX, 390)
  }

  func testFacesAreCentredAcross() {
    let focus = CGRect(x: 0.6, y: 0.2, width: 0.1, height: 0.2)
    let r = frame(focus)
    let faceX = r.minX + focus.midX * r.width
    XCTAssertEqual(faceX, 195, accuracy: 1)
  }

  func testWideSpreadOfFacesKeepsThePictureCentred() {
    // Rosalina at the left, Peach at the right, Mario in the middle.
    let focus = CGRect(x: 0.05, y: 0.2, width: 0.6, height: 0.5)
    let r = frame(focus)
    XCTAssertEqual(r.midX, 195, accuracy: 0.5)
  }

  func testNeverLeavesAGapAtTheSides() {
    let focus = CGRect(x: 0.95, y: 0.2, width: 0.05, height: 0.2)
    let r = frame(focus)
    XCTAssertGreaterThanOrEqual(r.maxX, 390 - 0.001)
    XCTAssertLessThanOrEqual(r.minX, 0.001)
  }

  func testSlidesUpButKeepsFacesBelowTheTopBar() {
    // Faces fill the whole height: shrinking alone can't clear the logo.
    let focus = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.69)
    let r = frame(focus)
    XCTAssertGreaterThanOrEqual(r.minY + focus.minY * r.height, 100 - 0.001)
  }

  func testFacesClearTheBigHeroLogo() {
    // KP (2026-11-14): iPhone hero, 700 pt art area, the bigger logo's top at
    // 354 pt; Mario's faces run down to 84 % of the picture.
    let focus = CGRect(x: 0.3, y: 0.15, width: 0.4, height: 0.69)
    let r = ArtFraming.frame(
      boxWidth: 393, zoneHeight: 700, aspect: 16.0 / 9.0, limitY: 354, topOffset: 24, minTop: 110, focus: focus)
    XCTAssertLessThanOrEqual(r.minY + focus.maxY * r.height, 354.5)
    XCTAssertLessThanOrEqual(r.minX, 0)
    XCTAssertGreaterThanOrEqual(r.maxX, 393)
  }

  func testBadInputGivesZero() {
    XCTAssertEqual(ArtFraming.frame(boxWidth: 0, zoneHeight: 410, aspect: 1.7, limitY: 300), .zero)
  }

  // MARK: Apple TV hero (KP, 2026-11-16): logo left, art right, faces clear of the logo.

  private func side(_ focus: CGRect?) -> CGRect {
    ArtFraming.side(
      boxWidth: 1920, boxHeight: 900, aspect: 16.0 / 9.0, clearX: 1080, minX: 240, maxX: 760, defaultX: 420,
      focus: focus)
  }

  func testTVHeroWithoutFacesSitsRightOfCentre() {
    let r = side(nil)
    XCTAssertEqual(r.minX, 420, accuracy: 0.001)
    XCTAssertEqual(r.height, 900, accuracy: 0.001)
    XCTAssertEqual(r.width, 1600, accuracy: 0.001)
  }

  func testTVHeroFaceInTheMiddleClearsTheLogo() {
    // One face around the picture's centre.
    let focus = CGRect(x: 0.42, y: 0.2, width: 0.16, height: 0.3)
    let r = side(focus)
    XCTAssertGreaterThanOrEqual(r.minX + focus.minX * r.width, 1080 - 0.5)
    XCTAssertLessThanOrEqual(r.minX + focus.maxX * r.width, 1880 + 0.5)
  }

  func testTVHeroFaceAlreadyOnTheRightStaysPut() {
    // Faces on the right of the art: no reason to push it further right.
    let focus = CGRect(x: 0.65, y: 0.2, width: 0.15, height: 0.3)
    XCTAssertEqual(side(focus).minX, 420, accuracy: 0.001)
  }

  func testTVHeroFaceAtTheRightEdgeStaysOnScreen() {
    let focus = CGRect(x: 0.85, y: 0.2, width: 0.12, height: 0.3)
    let r = side(focus)
    XCTAssertLessThanOrEqual(r.minX + focus.maxX * r.width, 1880 + 0.5)
    XCTAssertGreaterThanOrEqual(r.minX, 240)
  }

  func testTVHeroNeverPushedAllTheWayRight() {
    // A face at the far left of the picture would need a huge shift: capped.
    let focus = CGRect(x: 0.02, y: 0.2, width: 0.1, height: 0.3)
    XCTAssertEqual(side(focus).minX, 760, accuracy: 0.001)
  }

  func testTVHeroWideGroupIsCentredRightOfTheLogo() {
    let focus = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.5)
    let r = side(focus)
    let mid = r.minX + focus.midX * r.width
    XCTAssertEqual(mid, 1480, accuracy: 0.5)
  }
}
