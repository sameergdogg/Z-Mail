import SwiftUI

/// Example of how to update a view to use the new framework services
/// This demonstrates the migration from direct ObservableObject usage to dependency injection
struct ExampleUpdatedSettingsView: View {
    
    // MARK: - Service Dependencies (New Approach)
    
    @EnvironmentObject private var serviceRegistry: ServiceRegistryProtocol
    
    // MARK: - State
    
    @State private var settingsService: SettingsServiceProtocol?
    @State private var appDataService: AppDataServiceProtocol?
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            Form {
                if let settingsService = settingsService {
                    settingsSection(settingsService)
                }
                
                if let appDataService = appDataService {
                    dataSection(appDataService)
                }
                
                debugSection
            }
            .navigationTitle("Settings")
            .onAppear {
                resolveServices()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - View Sections
    
    @ViewBuilder
    private func settingsSection(_ service: SettingsServiceProtocol) -> some View {
        Section("Email Rendering") {
            Toggle("Rich Email Rendering", isOn: Binding(
                get: { service.useRichEmailRendering },
                set: { service.setRichEmailRendering($0) }
            ))
            
            Picker("Sender Sort Order", selection: Binding(
                get: { service.senderSortOrder },
                set: { service.setSenderSortOrder($0) }
            )) {
                ForEach(SenderSortOrder.allCases, id: \.self) { order in
                    Label(order.displayName, systemImage: order.iconName)
                        .tag(order)
                }
            }
        }
        
        Section {
            Button("Reset to Defaults") {
                service.resetToDefaults()
            }
            .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private func dataSection(_ service: AppDataServiceProtocol) -> some View {
        Section("Data Management") {
            HStack {
                Text("Initialization Status")
                Spacer()
                Image(systemName: service.isInitialized ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(service.isInitialized ? .green : .red)
                Text(service.isInitialized ? "Ready" : "Not Ready")
                    .foregroundColor(.secondary)
            }
            
            if let modelContext = service.modelContext {
                Button("Save Changes") {
                    do {
                        try service.save()
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
            
            Button("Reset Database") {
                Task {
                    do {
                        try await service.resetDatabase()
                    } catch {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                }
            }
            .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private var debugSection: some View {
        Section("Debug") {
            if let registeredTypes = serviceRegistry?.getRegisteredServiceTypes() {
                ForEach(registeredTypes, id: \.self) { serviceType in
                    HStack {
                        Image(systemName: "gear")
                            .foregroundColor(.blue)
                        Text(serviceType)
                        Spacer()
                        Text("Registered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func resolveServices() {
        // Resolve services from the registry
        settingsService = serviceRegistry.resolve(SettingsServiceProtocol.self)
        appDataService = serviceRegistry.resolve(AppDataServiceProtocol.self)
        
        // Handle missing services
        if settingsService == nil {
            errorMessage = "SettingsService not available"
            showingError = true
        }
        
        if appDataService == nil {
            errorMessage = "AppDataService not available"
            showingError = true
        }
    }
}

// MARK: - Migration Guide

/*
 MIGRATION FROM OLD TO NEW APPROACH:

 OLD APPROACH (Direct ObservableObject):
 ```swift
 struct OldSettingsView: View {
     @StateObject private var settingsManager = SettingsManager()
     @EnvironmentObject var appDataManager: AppDataManager
     
     var body: some View {
         // Direct access to managers
         Toggle("Setting", isOn: $settingsManager.useRichEmailRendering)
     }
 }
 ```

 NEW APPROACH (Dependency Injection):
 ```swift
 struct NewSettingsView: View {
     @EnvironmentObject private var serviceRegistry: ServiceRegistryProtocol
     @State private var settingsService: SettingsServiceProtocol?
     
     var body: some View {
         // Access through service registry
         if let service = settingsService {
             Toggle("Setting", isOn: Binding(
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

 BENEFITS OF NEW APPROACH:
 1. ✅ Loose coupling between views and services
 2. ✅ Easy testing with mock services
 3. ✅ Consistent service lifecycle management
 4. ✅ Better error handling and fallbacks
 5. ✅ Centralized configuration management
 6. ✅ Service health monitoring
 7. ✅ Scalable architecture for future services

 SETUP IN APP:
 ```swift
 @main
 struct EmailClientApp: App {
     @StateObject private var serviceRegistry: ServiceRegistryProtocol
     
     init() {
         // Initialize service registry with all services
         let modelContext = // ... create SwiftData context
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
*/

#Preview {
    // For preview, we need to create a mock service registry
    let mockRegistry = MockServiceRegistry()
    return ExampleUpdatedSettingsView()
        .environmentObject(mockRegistry)
}

// MARK: - Mock for Preview

private class MockServiceRegistry: ServiceRegistryProtocol, ObservableObject {
    private var services: [String: Any] = [:]
    
    func register<T>(_ service: T, for type: T.Type) {
        services[String(describing: type)] = service
    }
    
    func resolve<T>(_ type: T.Type) -> T? {
        return services[String(describing: type)] as? T
    }
    
    func isRegistered<T>(_ type: T.Type) -> Bool {
        return services[String(describing: type)] != nil
    }
    
    func unregister<T>(_ type: T.Type) {
        services.removeValue(forKey: String(describing: type))
    }
    
    func clearAll() {
        services.removeAll()
    }
    
    func getRegisteredServiceTypes() -> [String] {
        return Array(services.keys)
    }
}