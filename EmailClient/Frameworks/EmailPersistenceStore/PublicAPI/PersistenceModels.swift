import Foundation
import SwiftData

/// SwiftData model definitions for email persistence
/// Note: The actual SwiftData models are defined in SwiftDataModels.swift
/// This file now contains only the public API and conversion utilities

// MARK: - SwiftData Utilities

/// Public type aliases for SwiftData models
public typealias PersistedEmail = SwiftDataEmail
public typealias PersistedAccount = SwiftDataAccount
public typealias PersistedEmailAttachment = SwiftDataEmailAttachment

/// Extension to provide Core Data compatibility layer
public extension SwiftDataEmail {
    /// Converts SwiftData model to app Email model (alias for toDomainModel)
    func toEmail() -> Email {
        return toDomainModel()
    }
    
    /// Updates SwiftData model from app Email model (alias for updateFromDomainModel)
    func update(from email: Email) {
        updateFromDomainModel(email)
    }
}

/// Extension to provide Core Data compatibility layer
public extension SwiftDataEmailAttachment {
    /// Converts SwiftData model to app EmailAttachment model
    func toEmailAttachment() -> EmailAttachment {
        return EmailAttachment(
            id: id,
            filename: filename,
            mimeType: mimeType,
            size: size,
            attachmentId: attachmentId,
            downloadURL: downloadURL.flatMap(URL.init(string:))
        )
    }
    
    /// Updates SwiftData model from app EmailAttachment model
    func update(from attachment: EmailAttachment) {
        id = attachment.id
        filename = attachment.filename
        mimeType = attachment.mimeType
        size = attachment.size
        attachmentId = attachment.attachmentId
        downloadURL = attachment.downloadURL?.absoluteString
        isDownloaded = false
        localPath = nil
    }
}