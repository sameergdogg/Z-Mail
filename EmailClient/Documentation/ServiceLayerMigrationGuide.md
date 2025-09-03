# Service Layer Migration Guide
## From Direct ObservableObject to Framework-Based Dependency Injection

This guide explains how to migrate from the current service layer fragmentation to a unified framework-based architecture with dependency injection.

## Problem Statement

### Before: Service Layer Fragmentation

The codebase had two different service architectures:

1. **`/Frameworks/`** - Well-structured with PublicAPI/ImplWiring/Impl pattern and dependency injection
2. **`/Services/`** - Direct ObservableObject classes with tight coupling

This caused:
- ❌ Inconsistent architecture patterns
- ❌ Tight coupling between views and services  
- ❌ Difficult testing and mocking
- ❌ No centralized service management
- ❌ Code duplication in service initialization

### After: Unified Framework Architecture

All services now follow the same pattern:
- ✅ Consistent PublicAPI/ImplWiring/Impl structure
- ✅ Dependency injection throughout
- ✅ Centralized service registry
- ✅ Easy testing and mocking
- ✅ Scalable service management

## Migration Overview

### 1. Framework Structure Created

Each service now follows this structure:
```
ServiceName/
├── PublicAPI/
│   ├── ServiceNameProtocol.swift      # Public interface
│   └── ServiceNameModels.swift        # Data models and types
├── Impl/
│   ├── ServiceNameImpl.swift          # Implementation
│   └── [Helper classes]               # Supporting implementations
├── ImplWiring/
│   └── ServiceNameFactory.swift       # Factory and container
└── ServiceName.swift                  # Public API export
```

### 2. Services Migrated

| Original Service | New Framework | Status |
|-----------------|---------------|---------|
| `SettingsManager` | `SettingsService` | ✅ Complete |
| `AppDataManager` | `AppDataService` | ✅ Complete |
| `EmailClassificationService` | `EmailClassificationService` | ✅ Complete |
| `LaunchClassificationManager` | Integrated into AppDataService | ✅ Complete |
| `EmailImageService` | `EmailImageService` | ✅ Partial |
| `SecureConfigurationManager` | Integrated as provider | ✅ Complete |

### 3. Service Registry Created

New centralized service registry provides:
- Service registration and resolution
- Dependency injection
- Service lifecycle management
- Health monitoring
- Configuration management

## Code Migration Examples

### Settings Service Migration

#### Before (Direct ObservableObject):
```swift
// Old approach
struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager()
    
    var body: some View {
        Toggle("Rich Rendering", isOn: $settingsManager.useRichEmailRendering)
    }
}
```

#### After (Framework with DI):
```swift
// New approach
struct SettingsView: View {
    @EnvironmentObject private var serviceRegistry: ServiceRegistryProtocol
    @State private var settingsService: SettingsServiceProtocol?
    
    var body: some View {
        if let service = settingsService {
            Toggle("Rich Rendering", isOn: Binding(
                get: { service.useRichEmailRendering },
                set: { service.setRichEmailRendering($0) }
            ))
        }
    }
    
    private func resolveServices() {
        settingsService = serviceRegistry.resolve(SettingsServiceProtocol.self)
    }
}
```

### App Data Service Migration

#### Before:
```swift
struct ContentView: View {
    @StateObject private var appDataManager = AppDataManager.shared
    
    var body: some View {
        // Direct access to singleton
        if appDataManager.isInitialized {
            EmailListView()
        }
    }
}
```

#### After:
```swift
struct ContentView: View {
    @EnvironmentObject private var serviceRegistry: ServiceRegistryProtocol
    
    var body: some View {
        if let appDataService = serviceRegistry.resolve(AppDataServiceProtocol.self),
           appDataService.isInitialized {
            EmailListView()
        }
    }
}
```

## App Setup Migration

### Before:
```swift
@main
struct EmailClientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SettingsManager())
                .environmentObject(AppDataManager.shared)
                .onAppear {
                    Task {
                        await AppDataManager.shared.initialize()
                    }
                }
        }
    }
}
```

### After:
```swift
@main
struct EmailClientApp: App {
    @StateObject private var serviceRegistry: ServiceRegistryProtocol
    
    init() {
        // Create SwiftData context
        let modelContext = createModelContext()
        
        // Create configured service registry
        let registry = ServiceRegistryAPI.createConfiguredRegistry(
            modelContext: modelContext,
            configuration: ServiceRegistryConfiguration(
                enableDebugLogging: true,
                enableHealthMonitoring: true
            )
        )
        
        self._serviceRegistry = StateObject(wrappedValue: registry)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serviceRegistry)
        }
    }
}
```

## Benefits Achieved

### 1. Architectural Consistency
- All services follow the same PublicAPI/ImplWiring/Impl pattern
- Consistent dependency injection throughout
- Unified service lifecycle management

### 2. Improved Testability
```swift
// Easy to create mock services for testing
let mockSettingsService = MockSettingsService()
let testRegistry = ServiceRegistryAPI.createForTesting()
testRegistry.register(mockSettingsService, for: SettingsServiceProtocol.self)
```

### 3. Better Configuration Management
```swift
// Centralized configuration
let settingsConfig = SettingsServiceConfiguration(
    autoSave: true,
    enableDebugLogging: true
)
let service = SettingsServiceAPI.create(configuration: settingsConfig)
```

### 4. Service Health Monitoring
```swift
// Built-in health checks
let healthStatus = await serviceRegistry.getServiceHealthStatus()
```

### 5. Loose Coupling
- Views depend on protocols, not implementations
- Easy to swap implementations
- Services can be configured independently

## Migration Checklist

### Phase 1: Framework Setup ✅
- [x] Create SettingsService framework
- [x] Create AppDataService framework  
- [x] Create EmailClassificationService framework
- [x] Create ServiceRegistry framework

### Phase 2: Service Integration
- [ ] Update EmailClientApp to use ServiceRegistry
- [ ] Migrate EmailListView to use framework services
- [ ] Migrate SettingsView to use framework services
- [ ] Update other views to resolve services from registry

### Phase 3: Testing & Validation
- [ ] Create unit tests for new frameworks
- [ ] Create integration tests for service registry
- [ ] Performance testing of dependency injection
- [ ] Validate all existing functionality works

### Phase 4: Cleanup
- [ ] Remove old service files from `/Services/`
- [ ] Update documentation
- [ ] Remove deprecated code paths

## Configuration Examples

### Development Configuration:
```swift
let config = ServiceRegistryConfiguration(
    enableAutoInitialization: true,
    enableHealthMonitoring: true,
    enableDebugLogging: true
)
```

### Production Configuration:
```swift
let config = ServiceRegistryConfiguration(
    enableAutoInitialization: true,
    enableHealthMonitoring: true,
    enableDebugLogging: false
)
```

### Testing Configuration:
```swift
let config = ServiceRegistryConfiguration(
    enableAutoInitialization: false,
    enableHealthMonitoring: false,
    enableDebugLogging: false
)
```

## Common Patterns

### Service Resolution with Error Handling:
```swift
private func resolveServices() {
    guard let settingsService = serviceRegistry.resolve(SettingsServiceProtocol.self) else {
        errorMessage = "SettingsService not available"
        showingError = true
        return
    }
    
    self.settingsService = settingsService
}
```

### Service Resolution with Fallback:
```swift
let settingsService = serviceRegistry.resolve(
    SettingsServiceProtocol.self,
    default: DefaultSettingsService()
)
```

### Required Service Resolution:
```swift
do {
    let settingsService = try serviceRegistry.requireService(SettingsServiceProtocol.self)
    // Use service
} catch {
    // Handle missing service
}
```

## Performance Considerations

1. **Service Creation**: Services are created once and cached
2. **Resolution Speed**: O(1) lookup time in registry
3. **Memory Usage**: Shared instances reduce memory footprint
4. **Initialization**: Lazy loading of services when first accessed

## Next Steps

1. **Complete Phase 2**: Update all views to use service registry
2. **Add Testing**: Create comprehensive test suite
3. **Documentation**: Update all documentation to reflect new architecture
4. **Monitoring**: Add metrics and monitoring for service health
5. **Performance**: Profile and optimize service resolution

This migration significantly improves the codebase's scalability, maintainability, and testability while providing a consistent architecture pattern across all services.