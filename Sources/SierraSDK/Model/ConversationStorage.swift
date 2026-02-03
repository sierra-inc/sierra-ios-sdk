// Copyright Sierra

import Foundation

/// Manages conversation state storage with pluggable backing stores based on persistence mode.
///
/// - `none`: No storage, all operations are no-ops
/// - `memory`: In-memory cache only, state lost on app restart
/// - `disk`: In-memory cache backed by UserDefaults, state survives app restart
class ConversationStorage {
    private let mode: PersistenceMode
    private let storageKey: String
    private var cache: [String: String] = [:]

    init(mode: PersistenceMode, storageKey: String) {
        self.mode = mode
        self.storageKey = storageKey

        // Load from UserDefaults on init if DISK mode
        if mode == .disk {
            if let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
                cache = stored
            }
        }
    }

    /// Get a value from storage.
    /// - Parameter key: The key to look up
    /// - Returns: The stored value, or nil if not found or in `none` mode
    func getItem(_ key: String) -> String? {
        if mode == .none { return nil }
        return cache[key]
    }

    /// Store a value.
    /// - Parameters:
    ///   - key: The key to store under
    ///   - value: The value to store
    func setItem(_ key: String, _ value: String) {
        guard mode != .none else { return }
        cache[key] = value
        if mode == .disk {
            UserDefaults.standard.set(cache, forKey: storageKey)
        }
    }

    /// Clear all stored values.
    func clear() {
        cache.removeAll()
        if mode == .disk {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    /// Get all stored values as a dictionary.
    /// - Returns: A copy of all stored key-value pairs
    func getAll() -> [String: String] {
        return cache
    }
}
