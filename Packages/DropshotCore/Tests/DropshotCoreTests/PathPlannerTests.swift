import XCTest
@testable import DropshotCore

final class PathPlannerTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Users/test/Pictures/Screenshots", isDirectory: true)
    private var utc: Calendar { PathPlanner.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!) }

    /// 2026-11-11 15:41:07 UTC
    private var date: Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 11
        parts.hour = 15; parts.minute = 41; parts.second = 7
        return utc.date(from: parts)!
    }

    private func planner(_ folder: FolderPattern, _ rename: RenamePattern = .original) -> PathPlanner {
        PathPlanner(root: root, folderPattern: folder, renamePattern: rename, calendar: utc)
    }

    // MARK: Dated paths

    func testYearMonthDayFolder() {
        XCTAssertEqual(planner(.yearMonthDay).directory(for: date).path,
                       "/Users/test/Pictures/Screenshots/2026/11/11")
    }

    func testYearMonthFolder() {
        XCTAssertEqual(planner(.yearMonth).directory(for: date).path,
                       "/Users/test/Pictures/Screenshots/2026-11")
    }

    func testFlatFolderIsRoot() {
        XCTAssertEqual(planner(.flat).directory(for: date).path, root.path)
    }

    func testSingleDigitMonthAndDayAreZeroPadded() {
        var parts = DateComponents()
        parts.year = 2027; parts.month = 3; parts.day = 5; parts.hour = 1
        let early = utc.date(from: parts)!
        XCTAssertEqual(planner(.yearMonthDay).subfolderComponents(for: early), ["2027", "03", "05"])
        XCTAssertEqual(planner(.yearMonth).subfolderComponents(for: early), ["2027-03"])
    }

    func testFolderFollowsTimeZone() {
        // 23:30 UTC on the 11th is already the 12th in Tashkent (UTC+5).
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 11; parts.hour = 23; parts.minute = 30
        let lateUTC = utc.date(from: parts)!
        let tashkent = PathPlanner.defaultCalendar(timeZone: TimeZone(identifier: "Asia/Tashkent")!)
        let local = PathPlanner(root: root, folderPattern: .yearMonthDay, calendar: tashkent)
        XCTAssertEqual(local.subfolderComponents(for: lateUTC), ["2026", "11", "12"])
        XCTAssertEqual(planner(.yearMonthDay).subfolderComponents(for: lateUTC), ["2026", "11", "11"])
    }

    func testNonGregorianUserCalendarDoesNotLeakIntoFolders() {
        // The default calendar is always Gregorian, whatever the system calendar is.
        XCTAssertEqual(PathPlanner.defaultCalendar().identifier, .gregorian)
    }

    // MARK: Rename patterns

    func testOriginalNameIsKept() {
        let name = "Screenshot 2026-11-11 at 15.41.07.png"
        XCTAssertEqual(planner(.flat, .original).fileName(originalName: name, date: date), name)
    }

    func testCompactName() {
        XCTAssertEqual(
            planner(.flat, .compact).fileName(originalName: "Screenshot 2026-11-11 at 15.41.07.png", date: date),
            "2026-11-11_15-41-07.png")
    }

    func testCompactNameKeepsAndLowercasesExtension() {
        XCTAssertEqual(
            planner(.flat, .compact).fileName(originalName: "Screen Recording 2026-11-11 at 15.41.07.MOV", date: date),
            "2026-11-11_15-41-07.mov")
    }

    func testCompactNameWithoutExtension() {
        XCTAssertEqual(planner(.flat, .compact).fileName(originalName: "capture", date: date),
                       "2026-11-11_15-41-07")
    }

    // MARK: Destination + collisions

    func testDestinationCombinesFolderAndName() {
        let url = planner(.yearMonthDay, .compact)
            .destination(originalName: "Screenshot.png", date: date) { _ in false }
        XCTAssertEqual(url.path, "/Users/test/Pictures/Screenshots/2026/11/11/2026-11-11_15-41-07.png")
    }

    func testDestinationNeverOverwrites() {
        let taken: Set<String> = [
            "/Users/test/Pictures/Screenshots/2026-11/shot.png",
            "/Users/test/Pictures/Screenshots/2026-11/shot 2.png",
        ]
        let url = planner(.yearMonth).destination(originalName: "shot.png", date: date) {
            taken.contains($0.path)
        }
        XCTAssertEqual(url.path, "/Users/test/Pictures/Screenshots/2026-11/shot 3.png")
    }

    func testCollisionSuffixWithoutExtension() {
        let url = planner(.flat).destination(originalName: "shot", date: date) {
            $0.lastPathComponent == "shot"
        }
        XCTAssertEqual(url.lastPathComponent, "shot 2")
    }

    func testTwoCapturesInSameSecondGetDistinctCompactNames() {
        var taken = Set<String>()
        let plan = planner(.yearMonthDay, .compact)
        let first = plan.destination(originalName: "a.png", date: date) { taken.contains($0.path) }
        taken.insert(first.path)
        let second = plan.destination(originalName: "b.png", date: date) { taken.contains($0.path) }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "2026-11-11_15-41-07 2.png")
    }
}
