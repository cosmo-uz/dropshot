import XCTest
@testable import DropshotCore

final class CaptureClassifierTests: XCTestCase {
    func testTemporaryFilesAreIgnored() {
        XCTAssertTrue(CaptureClassifier.isTemporary(fileName: ".Screenshot 2026-11-11 at 15.41.07.png-Ab3d"))
        XCTAssertTrue(CaptureClassifier.isTemporary(fileName: ".DS_Store"))
        XCTAssertTrue(CaptureClassifier.isTemporary(fileName: "recording.mov.tmp"))
        XCTAssertTrue(CaptureClassifier.isTemporary(fileName: "shot.png.sb-1a2b3c-XyZ"))
        XCTAssertTrue(CaptureClassifier.isTemporary(fileName: ""))
        XCTAssertFalse(CaptureClassifier.isTemporary(fileName: "Screenshot 2026-11-11 at 15.41.07.png"))
    }

    func testKinds() {
        XCTAssertEqual(CaptureClassifier.kind(forFileName: "Screenshot.png"), .image)
        XCTAssertEqual(CaptureClassifier.kind(forFileName: "Screenshot.JPG"), .image)
        XCTAssertEqual(CaptureClassifier.kind(forFileName: "Screenshot.heic"), .image)
        XCTAssertEqual(CaptureClassifier.kind(forFileName: "Screen Recording.mov"), .recording)
        XCTAssertNil(CaptureClassifier.kind(forFileName: "notes.txt"))
        XCTAssertNil(CaptureClassifier.kind(forFileName: ".hidden.png"))
        XCTAssertNil(CaptureClassifier.kind(forFileName: "2026"))
    }

    func testOnlyDirectChildrenOfRootAreConsidered() {
        let root = URL(fileURLWithPath: "/Users/t/Pictures/Screenshots", isDirectory: true)
        XCTAssertTrue(CaptureClassifier.isDirectChild(
            URL(fileURLWithPath: "/Users/t/Pictures/Screenshots/a.png"), of: root))
        XCTAssertFalse(CaptureClassifier.isDirectChild(
            URL(fileURLWithPath: "/Users/t/Pictures/Screenshots/2026/11/11/a.png"), of: root))
        XCTAssertFalse(CaptureClassifier.isDirectChild(
            URL(fileURLWithPath: "/Users/t/Pictures/a.png"), of: root))
    }

    func testPrivatePrefixIsNormalised() {
        let root = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        XCTAssertTrue(CaptureClassifier.isDirectChild(
            URL(fileURLWithPath: "/private/tmp/shots/a.png"), of: root))
    }

    func testFlaggedFilesAlwaysQualify() {
        let now = Date()
        XCTAssertTrue(CaptureClassifier.isCapture(
            fileName: "Снимок экрана 2026-11-11 в 15.41.07.png", hasScreenCaptureFlag: true,
            lastWritten: now.addingTimeInterval(-9_999), now: now, live: false))
    }

    func testUnflaggedFileNeedsRecencyNameAndLiveEvent() {
        let now = Date()
        let recent = now.addingTimeInterval(-2)
        XCTAssertTrue(CaptureClassifier.isCapture(
            fileName: "Screenshot 2026-11-11 at 15.41.07.png", hasScreenCaptureFlag: false,
            lastWritten: recent, now: now, live: true))
        // Old file dragged into the folder.
        XCTAssertFalse(CaptureClassifier.isCapture(
            fileName: "Screenshot 2020-01-01 at 10.00.00.png", hasScreenCaptureFlag: false,
            lastWritten: now.addingTimeInterval(-600), now: now, live: true))
        // Someone exporting an unrelated image into the folder.
        XCTAssertFalse(CaptureClassifier.isCapture(
            fileName: "logo-final.png", hasScreenCaptureFlag: false,
            lastWritten: recent, now: now, live: true))
        // Catch-up sweeps never guess.
        XCTAssertFalse(CaptureClassifier.isCapture(
            fileName: "Screenshot 2026-11-11 at 15.41.07.png", hasScreenCaptureFlag: false,
            lastWritten: recent, now: now, live: false))
    }

    func testCustomScreenshotNamePrefix() {
        let now = Date()
        XCTAssertTrue(CaptureClassifier.isCapture(
            fileName: "Shot 2026-11-11 at 15.41.07.png", hasScreenCaptureFlag: false,
            lastWritten: now, now: now, live: true, customPrefix: "Shot"))
    }

    func testNonMediaIsNeverACapture() {
        let now = Date()
        XCTAssertFalse(CaptureClassifier.isCapture(
            fileName: "Screenshot.txt", hasScreenCaptureFlag: true, lastWritten: now, now: now, live: true))
    }
}

final class StabilityTrackerTests: XCTestCase {
    func testStableAfterTwoEqualReads() {
        var tracker = StabilityTracker(requiredStableReads: 2)
        XCTAssertEqual(tracker.observe(size: 1_000, at: 0.0), .waiting)
        XCTAssertEqual(tracker.observe(size: 1_000, at: 0.1), .stable(size: 1_000))
    }

    func testGrowingFileKeepsWaiting() {
        var tracker = StabilityTracker(requiredStableReads: 2)
        XCTAssertEqual(tracker.observe(size: 100, at: 0.0), .waiting)
        XCTAssertEqual(tracker.observe(size: 200, at: 0.1), .waiting)
        XCTAssertEqual(tracker.observe(size: 300, at: 0.2), .waiting)
        XCTAssertEqual(tracker.observe(size: 300, at: 0.3), .stable(size: 300))
    }

    func testEmptyFileIsNeverStable() {
        var tracker = StabilityTracker(requiredStableReads: 2)
        for step in 0..<5 {
            XCTAssertEqual(tracker.observe(size: 0, at: Double(step) * 0.1), .waiting)
        }
        XCTAssertEqual(tracker.observe(size: 42, at: 0.6), .waiting)
        XCTAssertEqual(tracker.observe(size: 42, at: 0.7), .stable(size: 42))
    }

    func testRequiresConfiguredNumberOfReads() {
        var tracker = StabilityTracker(requiredStableReads: 4)
        XCTAssertEqual(tracker.observe(size: 9, at: 0), .waiting)
        XCTAssertEqual(tracker.observe(size: 9, at: 1), .waiting)
        XCTAssertEqual(tracker.observe(size: 9, at: 2), .waiting)
        XCTAssertEqual(tracker.observe(size: 9, at: 3), .stable(size: 9))
    }

    func testMissingFileIsReportedAfterTolerance() {
        var tracker = StabilityTracker(missingTolerance: 3)
        XCTAssertEqual(tracker.observe(size: nil, at: 0.0), .waiting)
        XCTAssertEqual(tracker.observe(size: nil, at: 0.1), .waiting)
        XCTAssertEqual(tracker.observe(size: nil, at: 0.2), .missing)
    }

    func testBriefDisappearanceResetsButRecovers() {
        var tracker = StabilityTracker(requiredStableReads: 2, missingTolerance: 3)
        XCTAssertEqual(tracker.observe(size: 500, at: 0.0), .waiting)
        XCTAssertEqual(tracker.observe(size: nil, at: 0.1), .waiting)
        XCTAssertEqual(tracker.observe(size: 500, at: 0.2), .waiting)
        XCTAssertEqual(tracker.observe(size: 500, at: 0.3), .stable(size: 500))
    }

    func testTimesOutWhenItNeverSettles() {
        var tracker = StabilityTracker(requiredStableReads: 2, timeout: 1)
        XCTAssertEqual(tracker.observe(size: 1, at: 0.0), .waiting)
        XCTAssertEqual(tracker.observe(size: 2, at: 0.5), .waiting)
        XCTAssertEqual(tracker.observe(size: 3, at: 1.0), .timedOut)
    }

    func testAsyncWaitPollsUntilStable() async {
        let sizes = Sequence([10, 20, 30, 30, 30])
        let verdict = await FileStability.waitUntilStable(
            tracker: StabilityTracker(requiredStableReads: 2),
            pollInterval: .milliseconds(1),
            size: { sizes.next() },
            sleep: { _ in })
        XCTAssertEqual(verdict, .stable(size: 30))
        XCTAssertEqual(sizes.consumed, 4)
    }

    func testAsyncWaitReportsMissing() async {
        let verdict = await FileStability.waitUntilStable(
            tracker: StabilityTracker(missingTolerance: 2),
            size: { nil },
            sleep: { _ in })
        XCTAssertEqual(verdict, .missing)
    }

    func testFileSizeOfRealFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropshot-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(FileStability.fileSize(atPath: url.path))
        try Data(repeating: 7, count: 1234).write(to: url)
        XCTAssertEqual(FileStability.fileSize(atPath: url.path), 1234)
        // Directories are not regular files.
        XCTAssertNil(FileStability.fileSize(atPath: FileManager.default.temporaryDirectory.path))
    }

    /// Thread-safe scripted size provider.
    private final class Sequence: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int64]
        private(set) var consumed = 0
        init(_ values: [Int64]) { self.values = values }
        func next() -> Int64? {
            lock.lock(); defer { lock.unlock() }
            consumed += 1
            return values.isEmpty ? nil : values.removeFirst()
        }
    }
}

final class EventDeduplicatorTests: XCTestCase {
    func testFirstEventPassesDuplicatesAreFiltered() {
        var dedupe = EventDeduplicator<String>(ttl: 10)
        XCTAssertTrue(dedupe.shouldProcess("a", at: 0))
        XCTAssertFalse(dedupe.shouldProcess("a", at: 0.2))
        XCTAssertFalse(dedupe.shouldProcess("a", at: 9.9))
    }

    func testDifferentKeysAreIndependent() {
        var dedupe = EventDeduplicator<String>(ttl: 10)
        XCTAssertTrue(dedupe.shouldProcess("a", at: 0))
        XCTAssertTrue(dedupe.shouldProcess("b", at: 0))
    }

    func testKeyIsAcceptedAgainAfterTTL() {
        var dedupe = EventDeduplicator<String>(ttl: 10)
        XCTAssertTrue(dedupe.shouldProcess("a", at: 0))
        XCTAssertTrue(dedupe.shouldProcess("a", at: 10))
    }

    func testForgetAllowsReprocessing() {
        var dedupe = EventDeduplicator<String>(ttl: 10)
        XCTAssertTrue(dedupe.shouldProcess("a", at: 0))
        dedupe.forget("a")
        XCTAssertTrue(dedupe.shouldProcess("a", at: 1))
    }

    func testExpiredEntriesArePruned() {
        var dedupe = EventDeduplicator<Int>(ttl: 5)
        for key in 0..<100 { _ = dedupe.shouldProcess(key, at: 0) }
        XCTAssertEqual(dedupe.count, 100)
        _ = dedupe.shouldProcess(1_000, at: 6)
        XCTAssertEqual(dedupe.count, 1)
    }

    func testCapacityBoundsMemoryAndKeepsNewest() {
        var dedupe = EventDeduplicator<Int>(ttl: 1_000, capacity: 10)
        for key in 0..<50 { _ = dedupe.shouldProcess(key, at: Double(key)) }
        XCTAssertLessThanOrEqual(dedupe.count, 10)
        XCTAssertTrue(dedupe.contains(49, at: 50))
        XCTAssertFalse(dedupe.contains(0, at: 50))
    }

    func testBurstOfIdenticalEventsYieldsOne() {
        var dedupe = EventDeduplicator<String>(ttl: 300)
        let accepted = (0..<20).filter { dedupe.shouldProcess("dev1:ino42", at: Double($0) * 0.01) }
        XCTAssertEqual(accepted.count, 1)
    }
}
