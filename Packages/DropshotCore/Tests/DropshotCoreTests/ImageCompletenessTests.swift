import XCTest
@testable import DropshotCore

final class ImageCompletenessTests: XCTestCase {
    func testCompletePNG() {
        let tail = Data([1, 2, 3]) + ImageCompleteness.pngTrailer
        XCTAssertEqual(ImageCompleteness.isComplete(fileExtension: "PNG", tail: tail), true)
    }

    func testTruncatedPNG() {
        XCTAssertEqual(ImageCompleteness.isComplete(fileExtension: "png", tail: Data([1, 2, 3, 4])), false)
        XCTAssertEqual(ImageCompleteness.isComplete(
            fileExtension: "png", tail: ImageCompleteness.pngTrailer.dropLast()), false)
        XCTAssertEqual(ImageCompleteness.isComplete(fileExtension: "png", tail: Data()), false)
    }

    func testJPEG() {
        XCTAssertEqual(ImageCompleteness.isComplete(fileExtension: "jpg", tail: Data([9, 9, 0xFF, 0xD9])), true)
        XCTAssertEqual(ImageCompleteness.isComplete(fileExtension: "jpeg", tail: Data([0xFF, 0xD9, 0, 0])), true)
        XCTAssertEqual(ImageCompleteness.isComplete(fileExtension: "jpg", tail: Data([9, 9, 9, 9])), false)
    }

    func testUnknownFormatsAreUndecided() {
        XCTAssertNil(ImageCompleteness.isComplete(fileExtension: "heic", tail: Data([1])))
        XCTAssertNil(ImageCompleteness.isComplete(fileExtension: "tiff", tail: Data([1])))
    }

    func testTailOfRealFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ImageCompleteness.tail(ofFileAtPath: url.path))

        let body = Data(repeating: 0xAB, count: 5_000)
        try body.write(to: url)
        let partial = try XCTUnwrap(ImageCompleteness.tail(ofFileAtPath: url.path))
        XCTAssertEqual(partial.count, ImageCompleteness.tailLength)
        XCTAssertEqual(ImageCompleteness.isComplete(fileExtension: "png", tail: partial), false)

        try (body + ImageCompleteness.pngTrailer).write(to: url)
        let complete = try XCTUnwrap(ImageCompleteness.tail(ofFileAtPath: url.path))
        XCTAssertEqual(ImageCompleteness.isComplete(fileExtension: "png", tail: complete), true)

        try Data([1, 2]).write(to: url) // shorter than tailLength
        XCTAssertEqual(ImageCompleteness.tail(ofFileAtPath: url.path), Data([1, 2]))
    }
}
