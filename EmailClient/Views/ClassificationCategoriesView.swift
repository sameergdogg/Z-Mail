import SwiftUI

struct ClassificationCategoriesView: View {
    @EnvironmentObject var accountManager: AccountManagerImpl
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var emailService: EmailServiceImpl
    @Environment(\.appDataManager) var appDataManager
    @State private var categoryStats: [EmailCategory: CategoryStats] = [:]
    @State private var isLoading = true
    @State private var hasClassificationEnabled = false
    
    struct CategoryStats {
        let count: Int
        let unreadCount: Int
        let latestDate: Date?
    }
    
    init() {
        // Initialize with a temporary AccountManager - will be updated in onAppear
        self._emailService = StateObject(wrappedValue: EmailServiceAPI.create(with: AccountManagerAPI.shared) as! EmailServiceImpl)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email Categories")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("AI-classified email groups")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
                .background(Color(UIColor.systemGroupedBackground))
                
                if !hasClassificationEnabled {
                    // Classification not enabled state
                    VStack(spacing: 20) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 60))
                            .foregroundColor(.purple.opacity(0.6))
                        
                        VStack(spacing: 8) {
                            Text("AI Classification Not Enabled")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Enable AI email classification in Settings to see your emails organized by category.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        NavigationLink(destination: ClassificationSettingsView()) {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open Classification Settings")
                            }
                            .font(.body)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
                    
                } else if categoryStats.isEmpty && !isLoading {
                    // No classified emails state
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.6))
                        
                        VStack(spacing: 8) {
                            Text("No Classified Emails")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Your emails are being classified in the background. Check back in a few moments.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        Button("Refresh") {
                            Task {
                                await loadCategoryStatistics()
                            }
                        }
                        .font(.body)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
                    
                } else {
                    // Categories list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(EmailCategory.allCases, id: \.self) { category in
                                if let stats = categoryStats[category], stats.count > 0 {
                                    CategoryRowView(
                                        category: category,
                                        stats: stats,
                                        emailService: emailService
                                    )
                                }
                            }
                            
                            // Show empty categories at the bottom if needed
                            ForEach(EmailCategory.allCases, id: \.self) { category in
                                if categoryStats[category] == nil || categoryStats[category]?.count == 0 {
                                    EmptyCategoryRowView(category: category)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                    .background(Color(UIColor.systemGroupedBackground))
                }
            }
        }
        .onAppear {
            emailService.updateAccountManager(accountManager)
            hasClassificationEnabled = SecureConfigurationManager.shared.hasOpenAIAPIKey()
            
            if hasClassificationEnabled {
                Task {
                    await loadCategoryStatistics()
                }
            }
        }
        .refreshable {
            if hasClassificationEnabled {
                await loadCategoryStatistics()
            }
        }
    }
    
    private func loadCategoryStatistics() async {
        isLoading = true
        
        guard let modelContext = appDataManager.modelContext else {
            isLoading = false
            return
        }
        
        do {
            let emails = emailService.emails // Get current emails from service
            var newCategoryStats: [EmailCategory: CategoryStats] = [:]
            
            for category in EmailCategory.allCases {
                let categoryEmails = emails.filter { email in
                    email.classificationCategory == category.rawValue && email.isClassified
                }
                
                if !categoryEmails.isEmpty {
                    let unreadCount = categoryEmails.filter { !$0.isRead }.count
                    let latestDate = categoryEmails.map { $0.date }.max()
                    
                    newCategoryStats[category] = CategoryStats(
                        count: categoryEmails.count,
                        unreadCount: unreadCount,
                        latestDate: latestDate
                    )
                }
            }
            
            await MainActor.run {
                self.categoryStats = newCategoryStats
                self.isLoading = false
            }
            
        } catch {
            print("❌ Failed to load category statistics: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

struct CategoryRowView: View {
    let category: EmailCategory
    let stats: ClassificationCategoriesView.CategoryStats
    let emailService: EmailServiceImpl
    
    private var categoryColor: Color {
        switch category.color {
        case "orange": return .orange
        case "brown": return .brown
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }
    
    var body: some View {
        NavigationLink(destination: CategoryEmailsView(category: category, emailService: emailService)) {
            HStack(spacing: 16) {
                // Category icon
                Image(systemName: category.iconName)
                    .font(.title2)
                    .foregroundColor(categoryColor)
                    .frame(width: 32, height: 32)
                    .background(categoryColor.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(category.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(stats.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            if stats.unreadCount > 0 {
                                Text("\(stats.unreadCount) unread")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    HStack {
                        Text(categoryDescription(for: category))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let latestDate = stats.latestDate {
                            Text(latestDate.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical, 4)
    }
    
    private func categoryDescription(for category: EmailCategory) -> String {
        switch category {
        case .promotions:
            return "Marketing emails, deals, newsletters"
        case .orderHistory:
            return "Purchase receipts, shipping updates"
        case .finance:
            return "Banking, bills, payments"
        case .personal:
            return "Personal communication, family, friends"
        case .work:
            return "Work emails, meetings, projects"
        case .appointments:
            return "Scheduling, reminders, calendar invites"
        case .signInAlerts:
            return "Security alerts, login notifications"
        case .other:
            return "Everything else"
        }
    }
}

struct EmptyCategoryRowView: View {
    let category: EmailCategory
    
    private var categoryColor: Color {
        switch category.color {
        case "orange": return .orange
        case "brown": return .brown
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Category icon (dimmed)
            Image(systemName: category.iconName)
                .font(.title2)
                .foregroundColor(categoryColor.opacity(0.3))
                .frame(width: 32, height: 32)
                .background(categoryColor.opacity(0.05))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(category.displayName)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("0")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Text("No emails in this category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(0.7)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(UIColor.systemBackground).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.1), lineWidth: 0.5)
        )
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ClassificationCategoriesView()
            .environmentObject(AccountManagerAPI.shared as! AccountManagerImpl)
            .environmentObject(SettingsManager())
    }
}