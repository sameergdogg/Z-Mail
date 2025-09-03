import Foundation
import SwiftUI
import Combine

/// Implementation of the Settings Service protocol
/// Follows MVVM + Service Layer architecture from CLAUDE.md
internal class SettingsServiceImpl: SettingsServiceProtocol {
    
    // MARK: - Published Properties
    
    @Published public var useRichEmailRendering: Bool {
        didSet {
            if dependencies.configuration.autoSave {
                saveRichRenderingSetting()
            }
            settingsChangesSubject.send(.richRenderingChanged(useRichEmailRendering))
        }
    }
    
    @Published public var senderSortOrder: SenderSortOrder {
        didSet {
            if dependencies.configuration.autoSave {
                saveSenderSortOrderSetting()
            }
            settingsChangesSubject.send(.senderSortOrderChanged(senderSortOrder))
        }
    }
    
    // MARK: - Private Properties
    
    private let dependencies: SettingsServiceDependencies
    private let settingsChangesSubject = PassthroughSubject<SettingsChangeEvent, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    public var settingsChanges: AnyPublisher<SettingsChangeEvent, Never> {
        settingsChangesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    internal init(dependencies: SettingsServiceDependencies) {
        self.dependencies = dependencies
        
        // Load initial values from persistence
        self.useRichEmailRendering = dependencies.persistence.value(
            forKey: SettingsDefaults.Keys.useRichEmailRendering,
            defaultValue: SettingsDefaults.useRichEmailRendering
        )
        
        let sortOrderRawValue: String = dependencies.persistence.value(
            forKey: SettingsDefaults.Keys.senderSortOrder,
            defaultValue: SettingsDefaults.senderSortOrder.rawValue
        )
        self.senderSortOrder = SenderSortOrder(rawValue: sortOrderRawValue) ?? SettingsDefaults.senderSortOrder
        
        if dependencies.configuration.enableDebugLogging {
            setupDebugLogging()
        }
    }
    
    // MARK: - Public Methods
    
    public func setRichEmailRendering(_ enabled: Bool) {
        useRichEmailRendering = enabled
    }
    
    public func setSenderSortOrder(_ order: SenderSortOrder) {
        senderSortOrder = order
    }
    
    public func resetToDefaults() {
        useRichEmailRendering = SettingsDefaults.useRichEmailRendering
        senderSortOrder = SettingsDefaults.senderSortOrder
        
        // Clear from persistence if auto-save is disabled
        if !dependencies.configuration.autoSave {
            dependencies.persistence.removeValue(forKey: SettingsDefaults.Keys.useRichEmailRendering)
            dependencies.persistence.removeValue(forKey: SettingsDefaults.Keys.senderSortOrder)
            dependencies.persistence.synchronize()
        }
        
        settingsChangesSubject.send(.settingsReset)
        
        if dependencies.configuration.enableDebugLogging {
            print("⚙️ Settings reset to defaults")
        }
    }
    
    // MARK: - Private Methods
    
    private func saveRichRenderingSetting() {
        dependencies.persistence.setValue(useRichEmailRendering, forKey: SettingsDefaults.Keys.useRichEmailRendering)
        
        if dependencies.configuration.enableDebugLogging {
            print("⚙️ Rich rendering setting saved: \(useRichEmailRendering)")
        }
    }
    
    private func saveSenderSortOrderSetting() {
        dependencies.persistence.setValue(senderSortOrder.rawValue, forKey: SettingsDefaults.Keys.senderSortOrder)
        
        if dependencies.configuration.enableDebugLogging {
            print("⚙️ Sender sort order saved: \(senderSortOrder.displayName)")
        }
    }
    
    private func setupDebugLogging() {
        settingsChanges
            .sink { [weak self] event in
                guard let self = self else { return }
                switch event {
                case .richRenderingChanged(let enabled):
                    print("⚙️ Rich rendering changed: \(enabled)")
                case .senderSortOrderChanged(let order):
                    print("⚙️ Sender sort order changed: \(order.displayName)")
                case .settingsReset:
                    print("⚙️ Settings reset to defaults")
                }
            }
            .store(in: &cancellables)
    }
}