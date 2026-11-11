import XCTest
@testable import DropshotCore

private final class FakePreferences: PreferenceStore {
    var values: [String: PreferenceValue] = [:]
    var writes = 0
    func value(forKey key: String) -> PreferenceValue? { values[key] }
    func setValue(_ value: PreferenceValue?, forKey key: String) {
        writes += 1
        values[key] = value
    }
}

private final class FakeBackup: BackupStorage {
    var data: Data?
    func loadBackup() -> Data? { data }
    func saveBackup(_ data: Data?) { self.data = data }
}

final class ScreenCaptureDefaultsTests: XCTestCase {
    private var system = FakePreferences()
    private var backup = FakeBackup()
    private var defaults: ScreenCaptureDefaults { ScreenCaptureDefaults(system: system, backup: backup) }

    override func setUp() {
        system = FakePreferences()
        backup = FakeBackup()
    }

    func testApplyThenRestoreReturnsPreviousValue() {
        system.values["location"] = .string("/Users/t/Desktop/shots")
        let sut = defaults

        XCTAssertTrue(sut.apply(.string("/Users/t/Pictures/Screenshots"), to: .location))
        XCTAssertEqual(system.values["location"], .string("/Users/t/Pictures/Screenshots"))
        XCTAssertTrue(sut.isManaged(.location))
        XCTAssertEqual(sut.previousValue(of: .location), .string("/Users/t/Desktop/shots"))

        XCTAssertTrue(sut.restore(.location))
        XCTAssertEqual(system.values["location"], .string("/Users/t/Desktop/shots"))
        XCTAssertFalse(sut.isManaged(.location))
    }

    func testRestoreRemovesKeyThatDidNotExistBefore() {
        let sut = defaults
        sut.apply(.string("/x"), to: .location)
        sut.apply(.bool(false), to: .showThumbnail)

        XCTAssertEqual(Set(sut.restoreAll()), [.location, .showThumbnail])
        XCTAssertNil(system.values["location"], "key must be deleted, not set to a default")
        XCTAssertNil(system.values["show-thumbnail"])
        XCTAssertFalse(sut.hasAnythingToRestore)
        XCTAssertNil(backup.data, "backup record is cleared once everything is restored")
    }

    func testApplyingTwiceKeepsTheOriginalBackup() {
        system.values["location"] = .string("/original")
        let sut = defaults
        sut.apply(.string("/first"), to: .location)
        sut.apply(.string("/second"), to: .location)
        XCTAssertEqual(system.values["location"], .string("/second"))

        sut.restore(.location)
        XCTAssertEqual(system.values["location"], .string("/original"))
    }

    func testBackupSurvivesRelaunch() {
        system.values["show-thumbnail"] = .bool(true)
        defaults.apply(.bool(false), to: .showThumbnail)

        // New instance = app relaunch; only the persisted backup carries over.
        let relaunched = defaults
        XCTAssertTrue(relaunched.isManaged(.showThumbnail))
        XCTAssertTrue(relaunched.restore(.showThumbnail))
        XCTAssertEqual(system.values["show-thumbnail"], .bool(true))
    }

    func testUserChangeAfterApplyIsRespectedOnRestore() {
        system.values["location"] = .string("/original")
        let sut = defaults
        sut.apply(.string("/dropshot"), to: .location)
        // The user picks another folder in the Cmd+Shift+5 options.
        system.values["location"] = .string("/users-own-choice")

        XCTAssertFalse(sut.restore(.location))
        XCTAssertEqual(system.values["location"], .string("/users-own-choice"))
        XCTAssertFalse(sut.isManaged(.location))
    }

    func testRestoreWithoutApplyIsANoOp() {
        system.values["location"] = .string("/original")
        let sut = defaults
        XCTAssertFalse(sut.restore(.location))
        XCTAssertTrue(sut.restoreAll().isEmpty)
        XCTAssertEqual(system.values["location"], .string("/original"))
        XCTAssertEqual(system.writes, 0)
    }

    func testApplyingTheExistingValueDoesNotWriteButIsStillManaged() {
        system.values["show-thumbnail"] = .bool(false)
        let sut = defaults
        XCTAssertFalse(sut.apply(.bool(false), to: .showThumbnail))
        XCTAssertEqual(system.writes, 0)
        XCTAssertTrue(sut.isManaged(.showThumbnail))
        XCTAssertFalse(sut.restore(.showThumbnail))
        XCTAssertEqual(system.values["show-thumbnail"], .bool(false))
    }

    func testSettingsAreRestoredIndependently() {
        system.values["location"] = .string("/original")
        let sut = defaults
        sut.apply(.string("/dropshot"), to: .location)
        sut.apply(.bool(false), to: .showThumbnail)

        sut.restore(.showThumbnail)
        XCTAssertEqual(system.values["location"], .string("/dropshot"))
        XCTAssertNil(system.values["show-thumbnail"])
        XCTAssertTrue(sut.isManaged(.location))
        XCTAssertTrue(sut.hasAnythingToRestore)
    }

    func testFullRoundTripLeavesSystemExactlyAsFound() {
        system.values = ["location": .string("~/Desktop"), "show-thumbnail": .bool(true), "type": .string("jpg")]
        let before = system.values
        let sut = defaults
        sut.apply(.string("/dropshot"), to: .location)
        sut.apply(.bool(false), to: .showThumbnail)
        sut.restoreAll()
        XCTAssertEqual(system.values, before)
    }

    func testCorruptBackupIsIgnored() {
        backup.data = Data("not json".utf8)
        let sut = defaults
        XCTAssertFalse(sut.hasAnythingToRestore)
        XCTAssertTrue(sut.apply(.string("/x"), to: .location))
    }
}
