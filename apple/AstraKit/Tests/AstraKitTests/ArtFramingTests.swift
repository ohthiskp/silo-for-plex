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

  func testBadInputGivesZero() {
    XCTAssertEqual(ArtFraming.frame(boxWidth: 0, zoneHeight: 410, aspect: 1.7, limitY: 300), .zero)
  }
}
