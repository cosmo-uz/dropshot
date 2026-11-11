import Foundation

/// Remembers recently handled keys so the same capture reported twice
/// (FSEvents create + rename, FSEvents + Spotlight, a wake-up rescan…) is processed once.
public struct EventDeduplicator<Key: Hashable & Sendable>: Sendable {
    public let ttl: TimeInterval
    public let capacity: Int
    private var seen: [Key: TimeInterval] = [:]

    public init(ttl: TimeInterval = 300, capacity: Int = 512) {
        self.ttl = ttl
        self.capacity = max(1, capacity)
    }

    public var count: Int { seen.count }

    /// Returns `true` the first time a key is seen within `ttl`, and records it.
    public mutating func shouldProcess(_ key: Key, at now: TimeInterval) -> Bool {
        if let last = seen[key], now - last < ttl { return false }
        prune(now: now)
        seen[key] = now
        return true
    }

    public func contains(_ key: Key, at now: TimeInterval) -> Bool {
        guard let last = seen[key] else { return false }
        return now - last < ttl
    }

    public mutating func forget(_ key: Key) {
        seen[key] = nil
    }

    private mutating func prune(now: TimeInterval) {
        seen = seen.filter { now - $0.value < ttl }
        if seen.count >= capacity {
            // Drop the oldest entries; a stale duplicate is far less likely than a new capture.
            let overflow = seen.count - capacity + 1
            for (key, _) in seen.sorted(by: { $0.value < $1.value }).prefix(overflow) {
                seen[key] = nil
            }
        }
    }
}
