import Foundation
import SwiftUI
import Combine

/// Implementation of the Service Registry protocol
/// Provides centralized service management with dependency injection
internal class ServiceRegistryImpl: ServiceRegistryProtocol {
    
    // MARK: - Published Properties
    
    @Published public private(set) var isInitialized = false
    
    // MARK: - Private Properties
    
    private let dependencies: ServiceRegistryDependencies
    private var services: [String: ServiceDescriptor] = [:]
    private let lock = NSRecursiveLock()
    private let changeEventsSubject = PassthroughSubject<ServiceRegistryChangeEvent, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var healthCheckTimer: Timer?
    
    public var changeEvents: AnyPublisher<ServiceRegistryChangeEvent, Never> {
        changeEventsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    internal init(dependencies: ServiceRegistryDependencies) {
        self.dependencies = dependencies
        
        if dependencies.configuration.enableDebugLogging {
            setupDebugLogging()
        }
        
        if dependencies.configuration.enableHealthMonitoring {
            setupHealthMonitoring()
        }
        
        if dependencies.configuration.enableAutoInitialization {
            Task {
                await initialize()
            }
        }
    }
    
    deinit {
        healthCheckTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    public func register<T>(_ service: T, for type: T.Type) {
        let typeName = String(describing: type)
        
        lock.lock()
        defer { lock.unlock() }
        
        if services[typeName] != nil {
            if dependencies.configuration.enableDebugLogging {
                print("⚠️ Service already registered, replacing: \(typeName)")
            }
        }
        
        let configuration = dependencies.configurationManager.getConfiguration(for: typeName)
        let descriptor = ServiceDescriptor(typeName: typeName, instance: service, configuration: configuration)
        services[typeName] = descriptor
        
        if dependencies.configuration.enableDebugLogging {
            print("✅ Registered service: \(typeName)")
        }
        
        changeEventsSubject.send(.serviceRegistered(typeName))
        
        // Initialize the service if it supports lifecycle management
        if let lifecycleService = service as? LifecycleAwareService {
            Task {
                try await initializeService(lifecycleService, typeName: typeName)
            }
        }
    }
    
    public func resolve<T>(_ type: T.Type) -> T? {
        let typeName = String(describing: type)
        
        lock.lock()
        defer { lock.unlock() }
        
        guard let descriptor = services[typeName] else {
            if dependencies.configuration.enableDebugLogging {
                print("⚠️ Service not found: \(typeName)")
            }
            return nil
        }
        
        return descriptor.instance as? T
    }
    
    public func isRegistered<T>(_ type: T.Type) -> Bool {
        let typeName = String(describing: type)
        
        lock.lock()
        defer { lock.unlock() }
        
        return services[typeName] != nil
    }
    
    public func unregister<T>(_ type: T.Type) {
        let typeName = String(describing: type)
        
        lock.lock()
        defer { lock.unlock() }
        
        guard let descriptor = services.removeValue(forKey: typeName) else {
            if dependencies.configuration.enableDebugLogging {
                print("⚠️ Service not registered for unregistration: \(typeName)")
            }
            return
        }
        
        // Stop the service if it supports lifecycle management
        if let lifecycleService = descriptor.instance as? LifecycleAwareService {
            Task {
                try await stopService(lifecycleService, typeName: typeName)
            }
        }
        
        if dependencies.configuration.enableDebugLogging {
            print("✅ Unregistered service: \(typeName)")
        }
        
        changeEventsSubject.send(.serviceUnregistered(typeName))
    }
    
    public func clearAll() {
        lock.lock()
        let serviceTypes = Array(services.keys)
        lock.unlock()
        
        // Stop all services first
        Task {
            for typeName in serviceTypes {
                if let descriptor = services[typeName],
                   let lifecycleService = descriptor.instance as? LifecycleAwareService {
                    try? await stopService(lifecycleService, typeName: typeName)
                }
            }
            
            await MainActor.run {
                self.lock.lock()
                self.services.removeAll()
                self.lock.unlock()
                
                if self.dependencies.configuration.enableDebugLogging {
                    print("✅ Cleared all services")
                }
                
                self.changeEventsSubject.send(.allServicesCleared)
            }
        }
    }
    
    public func getRegisteredServiceTypes() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(services.keys).sorted()
    }
    
    // MARK: - Private Methods
    
    private func initialize() async {
        guard !isInitialized else { return }
        
        do {
            await dependencies.lifecycleManager.initializeServices()
            isInitialized = true
            
            if dependencies.configuration.enableDebugLogging {
                print("✅ Service Registry initialized")
            }
        } catch {
            if dependencies.configuration.enableDebugLogging {
                print("❌ Failed to initialize Service Registry: \(error)")
            }
        }
    }
    
    private func initializeService(_ service: LifecycleAwareService, typeName: String) async throws {
        do {
            try await service.initialize()
            
            if dependencies.configuration.enableDebugLogging {
                print("✅ Initialized service: \(typeName)")
            }
            
            changeEventsSubject.send(.serviceInitialized(typeName))
            
            // Start the service after initialization
            try await service.start()
            
            if dependencies.configuration.enableDebugLogging {
                print("✅ Started service: \(typeName)")
            }
            
            changeEventsSubject.send(.serviceStarted(typeName))
            
        } catch {
            if dependencies.configuration.enableDebugLogging {
                print("❌ Failed to initialize service \(typeName): \(error)")
            }
            throw ServiceRegistryError.initializationFailed("\(typeName): \(error.localizedDescription)")
        }
    }
    
    private func stopService(_ service: LifecycleAwareService, typeName: String) async throws {
        do {
            try await service.stop()
            
            if dependencies.configuration.enableDebugLogging {
                print("✅ Stopped service: \(typeName)")
            }
            
            changeEventsSubject.send(.serviceStopped(typeName))
            
        } catch {
            if dependencies.configuration.enableDebugLogging {
                print("❌ Failed to stop service \(typeName): \(error)")
            }
        }
    }
    
    private func setupDebugLogging() {
        changeEvents
            .sink { event in
                switch event {
                case .serviceRegistered(let type):
                    print("🔧 Service registered: \(type)")
                case .serviceUnregistered(let type):
                    print("🔧 Service unregistered: \(type)")
                case .serviceInitialized(let type):
                    print("🔧 Service initialized: \(type)")
                case .serviceStarted(let type):
                    print("🔧 Service started: \(type)")
                case .serviceStopped(let type):
                    print("🔧 Service stopped: \(type)")
                case .serviceHealthChanged(let type, let status):
                    print("🔧 Service health changed: \(type) -> \(status.displayName)")
                case .allServicesCleared:
                    print("🔧 All services cleared")
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupHealthMonitoring() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: dependencies.configuration.healthCheckInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performHealthChecks()
            }
        }
    }
    
    private func performHealthChecks() async {
        lock.lock()
        let serviceDescriptors = Array(services.values)
        lock.unlock()
        
        for descriptor in serviceDescriptors {
            if let healthCheckableService = descriptor.instance as? HealthCheckableService {
                let healthStatus = await healthCheckableService.performHealthCheck()
                changeEventsSubject.send(.serviceHealthChanged(descriptor.typeName, healthStatus))
            }
        }
    }
}

// MARK: - Default Implementations

/// Default implementation of ServiceConfigurationManagerProtocol
internal class DefaultServiceConfigurationManager: ServiceConfigurationManagerProtocol {
    
    private var configurations: [String: [String: Any]]
    private let lock = NSLock()
    
    internal init(configurations: [String: [String: Any]] = [:]) {
        self.configurations = configurations
        
        // Set default configurations for known services
        for (serviceType, defaultConfig) in [
            "SettingsService": ServiceConfigurations.settingsService,
            "AppDataService": ServiceConfigurations.appDataService,
            "EmailClassificationService": ServiceConfigurations.emailClassificationService,
            "EmailImageService": ServiceConfigurations.emailImageService
        ] {
            if configurations[serviceType] == nil {
                self.configurations[serviceType] = defaultConfig
            }
        }
    }
    
    func getConfiguration(for serviceType: String) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        
        return configurations[serviceType] ?? ServiceConfigurations.defaultConfiguration(for: serviceType)
    }
    
    func setConfiguration(_ configuration: [String: Any], for serviceType: String) {
        lock.lock()
        defer { lock.unlock() }
        
        configurations[serviceType] = configuration
    }
    
    func resetConfiguration(for serviceType: String) {
        lock.lock()
        defer { lock.unlock() }
        
        configurations[serviceType] = ServiceConfigurations.defaultConfiguration(for: serviceType)
    }
}

/// Default implementation of ServiceLifecycleManagerProtocol
internal class DefaultServiceLifecycleManager: ServiceLifecycleManagerProtocol {
    
    func initializeServices() async {
        // This would contain logic to initialize all services in the correct order
        // For now, this is a placeholder
    }
    
    func startServices() async {
        // Logic to start all services
    }
    
    func stopServices() async {
        // Logic to stop all services
    }
    
    func restartService(_ serviceType: String) async {
        // Logic to restart a specific service
    }
    
    func getServiceHealthStatus() -> [String: ServiceHealthStatus] {
        // Return health status of all services
        return [:]
    }
}