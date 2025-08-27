// Copyright Sierra

import Foundation

/// The type of user attachment
public enum UserAttachmentType: String, CaseIterable {
    // file and email are also possible types, but not supported right now.
    case custom = "custom"
}

/// Represents a user attachment that can be sent to the agent.
/// Matches the web SDK's RawMessageAttachment format.
public struct UserAttachment {
    /// The type of attachment
    public let type: UserAttachmentType
    
    /// The attachment data as a dictionary
    public let data: [String: Any]
    
    /// Creates a new UserAttachment
    /// - Parameters:
    ///   - type: The attachment type
    ///   - data: The attachment data
    public init(type: UserAttachmentType, data: [String: Any]) {
        self.type = type
        self.data = data
    }
    
    /// Creates a custom attachment (the most common type)
    /// - Parameter data: The custom attachment data
    /// - Returns: A UserAttachment with type .custom
    public static func custom(data: [String: Any]) -> UserAttachment {
        return UserAttachment(type: .custom, data: data)
    }
}
