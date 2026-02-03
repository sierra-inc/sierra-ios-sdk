// Copyright Sierra

import Foundation

/// Controls how conversation state is persisted across navigation and app restarts.
public enum PersistenceMode: String {
    /// No persistence. Conversation state is lost when the chat view is destroyed.
    case none

    /// In-memory persistence. Conversation survives navigation and view recreation,
    /// but is lost on app restart. This is the default.
    case memory

    /// Disk persistence. Conversation survives app restart.
    /// Data is stored in the app's private UserDefaults.
    case disk
}
