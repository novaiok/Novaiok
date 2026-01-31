import Foundation

/// Simple in-memory ETag cache keyed by URL string with LRU eviction.
actor ETagCache {
    /// Maximum number of entries to retain. Oldest entries are evicted when exceeded.
    private let maxEntries: Int

    private var store: [String: (etag: String, data: Data)] = [:]
    /// Tracks access order for LRU eviction (most recent at end)
    private var accessOrder: [String] = []
    private var rateLimitedUntil: Date?

    init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
    }

    func cached(for url: URL) -> (etag: String, data: Data)? {
        let key = url.absoluteString
        guard let value = self.store[key] else { return nil }
        // Move to end of access order (most recently used)
        if let index = self.accessOrder.firstIndex(of: key) {
            self.accessOrder.remove(at: index)
            self.accessOrder.append(key)
        }
        return value
    }

    func save(url: URL, etag: String?, data: Data) {
        guard let etag else { return }
        let key = url.absoluteString

        // If key already exists, remove from access order (will re-add at end)
        if self.store[key] != nil {
            if let index = self.accessOrder.firstIndex(of: key) {
                self.accessOrder.remove(at: index)
            }
        }

        // Evict oldest entries if at capacity
        while self.store.count >= self.maxEntries, let oldest = self.accessOrder.first {
            self.accessOrder.removeFirst()
            self.store.removeValue(forKey: oldest)
        }

        self.store[key] = (etag, data)
        self.accessOrder.append(key)
    }

    func setRateLimitReset(date: Date) {
        self.rateLimitedUntil = date
    }

    func rateLimitUntil(now: Date = Date()) -> Date? {
        guard let until = self.rateLimitedUntil else { return nil }
        if until <= now {
            self.rateLimitedUntil = nil
            return nil
        }
        return until
    }

    func isRateLimited(now: Date = Date()) -> Bool {
        guard let until = self.rateLimitUntil(now: now) else { return false }
        return until > now
    }

    func clear() {
        self.store.removeAll()
        self.accessOrder.removeAll()
        self.rateLimitedUntil = nil
    }

    func count() -> Int {
        self.store.count
    }
}
