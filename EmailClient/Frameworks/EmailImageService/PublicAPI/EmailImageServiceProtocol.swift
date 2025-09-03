import Foundation
import SwiftUI
import UIKit
import GoogleSignIn
import Combine

/// Public API protocol for email image service operations
/// Follows MVVM + Service Layer architecture from CLAUDE.md
public protocol EmailImageServiceProtocol: ObservableObject {
    /// Loads an image from Gmail attachment
    /// - Parameters:
    ///   - attachmentId: Gmail attachment ID
    ///   - messageId: Gmail message ID
    ///   - user: Authenticated Google user
    /// - Returns: UIImage if successful, nil otherwise
    func loadImage(attachmentId: String, messageId: String, user: GIDGoogleUser) async -> UIImage?
    
    /// Preloads images for better performance
    /// - Parameters:
    ///   - attachments: List of email attachments to preload
    ///   - user: Authenticated Google user
    func preloadImages(attachments: [ImageServiceAttachment], user: GIDGoogleUser) async
    
    /// Clears cached images
    func clearCache()
    
    /// Clears cached images older than specified time interval
    /// - Parameter timeInterval: Time interval for cache expiry
    func clearCache(olderThan timeInterval: TimeInterval)
    
    /// Gets current cache size in bytes
    /// - Returns: Cache size in bytes
    func getCacheSize() -> Int
    
    /// Gets cache statistics
    /// - Returns: Cache statistics
    func getCacheStatistics() -> ImageCacheStatistics
}

/// Email attachment data model for image service
public struct ImageServiceAttachment: Identifiable, Hashable {
    public let id: String
    public let messageId: String
    public let filename: String?
    public let mimeType: String
    public let size: Int
    public let isImage: Bool
    
    public init(id: String, messageId: String, filename: String?, mimeType: String, size: Int) {
        self.id = id
        self.messageId = messageId
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.isImage = mimeType.hasPrefix("image/")
    }
}

/// Image cache statistics
public struct ImageCacheStatistics {
    public let totalItems: Int
    public let totalSize: Int
    public let hitCount: Int
    public let missCount: Int
    public let evictionCount: Int
    
    public init(totalItems: Int, totalSize: Int, hitCount: Int, missCount: Int, evictionCount: Int) {
        self.totalItems = totalItems
        self.totalSize = totalSize
        self.hitCount = hitCount
        self.missCount = missCount
        self.evictionCount = evictionCount
    }
    
    public var hitRatio: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0.0 }
        return Double(hitCount) / Double(total)
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}

/// Configuration options for email image service behavior
public struct EmailImageServiceConfiguration {
    /// Maximum number of cached items (default: 100)
    public let maxCacheItems: Int
    
    /// Maximum cache size in bytes (default: 50MB)
    public let maxCacheSize: Int
    
    /// Request timeout in seconds (default: 30.0)
    public let requestTimeout: TimeInterval
    
    /// Maximum concurrent image downloads (default: 3)
    public let maxConcurrentDownloads: Int
    
    /// Enable debug logging (default: false)
    public let enableDebugLogging: Bool
    
    /// Cache expiry time in seconds (default: 1 hour)
    public let cacheExpiryTime: TimeInterval
    
    /// Retry count for failed downloads (default: 2)
    public let maxRetryCount: Int
    
    public init(
        maxCacheItems: Int = 100,
        maxCacheSize: Int = 50 * 1024 * 1024, // 50MB
        requestTimeout: TimeInterval = 30.0,
        maxConcurrentDownloads: Int = 3,
        enableDebugLogging: Bool = false,
        cacheExpiryTime: TimeInterval = 3600, // 1 hour
        maxRetryCount: Int = 2
    ) {
        self.maxCacheItems = maxCacheItems
        self.maxCacheSize = maxCacheSize
        self.requestTimeout = requestTimeout
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.enableDebugLogging = enableDebugLogging
        self.cacheExpiryTime = cacheExpiryTime
        self.maxRetryCount = maxRetryCount
    }
}

/// Email image service specific errors
public enum EmailImageServiceError: Error, LocalizedError {
    case invalidURL(String)
    case networkError(String)
    case authenticationError(String)
    case decodingError(String)
    case cacheError(String)
    case timeout
    case unsupportedFormat(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .decodingError(let message):
            return "Failed to decode image: \(message)"
        case .cacheError(let message):
            return "Cache error: \(message)"
        case .timeout:
            return "Request timed out"
        case .unsupportedFormat(let format):
            return "Unsupported image format: \(format)"
        }
    }
}

/// Change events for reactive updates
public enum EmailImageChangeEvent {
    case imageLoaded(String, UIImage)
    case imageFailed(String, Error)
    case cacheCleared
    case cacheSizeChanged(Int)
    case preloadStarted([String])
    case preloadCompleted([String])
}