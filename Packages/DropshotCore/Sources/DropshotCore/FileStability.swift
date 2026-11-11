import Foundation

/// State machine answering "has this file finished being written?".
///
/// Feed it periodic size observations. A file is stable once its size has been
/// non-zero and unchanged for `requiredStableReads` consecutive observations.
public struct StabilityTracker: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        case waiting
        case stable(size: Int64)
        /// The file vanished (deleted or moved away) while we were waiting.
        case missing
        case timedOut
    }

    public let requiredStableReads: Int
    public let missingTolerance: Int
    public let timeout: TimeInterval

    private var startTime: TimeInterval?
    private var lastSize: Int64?
    private var stableReads = 0
    private var missingReads = 0

    public init(requiredStableReads: Int = 2, missingTolerance: Int = 3, timeout: TimeInterval = 60) {
        self.requiredStableReads = max(1, requiredStableReads)
        self.missingTolerance = max(1, missingTolerance)
        self.timeout = timeout
    }

    /// - Parameters:
    ///   - size: current size in bytes, or `nil` if the file does not exist.
    ///   - time: a monotonic timestamp in seconds.
    public mutating func observe(size: Int64?, at time: TimeInterval) -> Verdict {
        let start = startTime ?? time
        startTime = start

        guard let size else {
            missingReads += 1
            stableReads = 0
            lastSize = nil
            return missingReads >= missingTolerance ? .missing : .waiting
        }
        missingReads = 0

        if size > 0, size == lastSize {
            stableReads += 1
        } else {
            stableReads = size > 0 ? 1 : 0
        }
        lastSize = size

        if stableReads >= requiredStableReads { return .stable(size: size) }
        if time - start >= timeout { return .timedOut }
        return .waiting
    }
}

public enum FileStability {
    /// Size of the regular file at `path`, or `nil` when it is missing or not a regular file.
    public static func fileSize(atPath path: String) -> Int64? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Int64(info.st_size)
    }

    /// Polls `size` until the tracker reaches a final verdict.
    public static func waitUntilStable(
        tracker: StabilityTracker = StabilityTracker(),
        pollInterval: Duration = .milliseconds(100),
        size: @Sendable () -> Int64?,
        now: @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> StabilityTracker.Verdict {
        var tracker = tracker
        while true {
            let verdict = tracker.observe(size: size(), at: now())
            if verdict != .waiting { return verdict }
            if Task.isCancelled { return .timedOut }
            await sleep(pollInterval)
        }
    }
}
