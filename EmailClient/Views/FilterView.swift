import SwiftUI

struct FilterView: View {
    let emailService: EmailServiceImpl
    let accountManager: AccountManagerImpl
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        NavigationView {
            ZStack {
                // Liquid Glass background
                Color.clear.background(.ultraThinMaterial)
                List {
                    statusFilterSection
                    accountFilterSection
                    categoryFilterSection
                    emailSortSection
                    senderSortSection
                }
                .scrollContentBackground(.hidden) // Hide default list background so glass shows through
            }
            .navigationTitle("Filters & Sorting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var statusFilterSection: some View {
        Section("Filter by Status") {
            FilterOptionView(
                title: "All Emails",
                isSelected: isSelected(.all),
                action: { emailService.applyFilter(.all) }
            )
            
            FilterOptionView(
                title: "Unread",
                isSelected: isSelected(.unread),
                action: { emailService.applyFilter(.unread) }
            )
            
            FilterOptionView(
                title: "Starred",
                isSelected: isSelected(.starred),
                action: { emailService.applyFilter(.starred) }
            )

            FilterOptionView(
                title: "Security PIN Emails",
                isSelected: isSelected(.label("security_pin")),
                action: { emailService.applyFilter(.label("security_pin")) }
            )
        }
    }
    
    private var accountFilterSection: some View {
        Section("Filter by Account") {
            ForEach(accountManager.accounts) { account in
                FilterOptionView(
                    title: account.email,
                    isSelected: isSelected(.account(account.email)),
                    action: { emailService.applyFilter(.account(account.email)) }
                )
            }
        }
    }
    
    private var categoryFilterSection: some View {
        Section("Filter by Category") {
            FilterOptionView(
                title: "All Categories",
                isSelected: !isAnySpecificCategorySelected(),
                action: { emailService.applyFilter(.all) }
            )
            
            ForEach(availableClassifications(), id: \.self) { category in
                CategoryFilterOptionView(
                    category: category,
                    emailCount: getCategoryEmailCount(category),
                    isSelected: isSelected(.classification(category.rawValue)),
                    action: { emailService.applyFilter(.classification(category.rawValue)) }
                )
            }
        }
    }
    
    private var emailSortSection: some View {
        Section("Email Sort Order") {
            SortOptionView(
                title: "Date (Newest First)",
                isSelected: emailService.sortOrder == .dateDescending,
                action: { emailService.applySortOrder(.dateDescending) }
            )
            
            SortOptionView(
                title: "Date (Oldest First)",
                isSelected: emailService.sortOrder == .dateAscending,
                action: { emailService.applySortOrder(.dateAscending) }
            )
            
            SortOptionView(
                title: "Sender (A-Z)",
                isSelected: emailService.sortOrder == .senderAscending,
                action: { emailService.applySortOrder(.senderAscending) }
            )
            
            SortOptionView(
                title: "Sender (Z-A)",
                isSelected: emailService.sortOrder == .senderDescending,
                action: { emailService.applySortOrder(.senderDescending) }
            )
        }
    }
    
    private var senderSortSection: some View {
        Section("Sender List Sort Order") {
            ForEach(LegacySenderSortOrder.allCases, id: \.rawValue) { sortOrder in
                SenderSortOptionView(
                    title: sortOrder.rawValue,
                    iconName: "arrow.up.arrow.down",
                    isSelected: settingsManager.senderSortOrder == sortOrder,
                    action: { settingsManager.senderSortOrder = sortOrder }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func availableClassifications() -> [EmailCategory] {
        // Return categories that have emails
        let allEmails = emailService.emails
        let categoriesWithEmails = Set<EmailCategory>(allEmails.compactMap { email in
            guard email.isClassified, let categoryString = email.classificationCategory else { return nil }
            return EmailCategory(rawValue: categoryString)
        })
        
        // Return sorted categories that have emails
        return EmailCategory.allCases.filter { categoriesWithEmails.contains($0) }
    }
    
    private func getCategoryEmailCount(_ category: EmailCategory) -> Int {
        let allEmails = emailService.emails
        return allEmails.filter { email in
            email.isClassified && email.classificationCategory == category.rawValue
        }.count
    }
    
    private func isAnySpecificCategorySelected() -> Bool {
        switch emailService.currentFilter {
        case .classification:
            return true
        default:
            return false
        }
    }
    
    private func isSelected(_ filter: EmailFilter) -> Bool {
        switch (emailService.currentFilter, filter) {
        case (.all, .all),
             (.unread, .unread),
             (.starred, .starred):
            return true
        case (.account(let current), .account(let new)):
            return current == new
        case (.label(let current), .label(let new)):
            return current == new
        case (.classification(let current), .classification(let new)):
            return current == new
        default:
            return false
        }
    }
}

// MARK: - Supporting Views

struct FilterOptionView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct SortOptionView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct SenderSortOptionView: View {
    let title: String
    let iconName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct CategoryFilterOptionView: View {
    let category: EmailCategory
    let emailCount: Int
    let isSelected: Bool
    let action: () -> Void
    
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
        Button(action: action) {
            HStack {
                Image(systemName: category.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(categoryColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .foregroundColor(.primary)
                    
                    Text("\(emailCount) email\(emailCount != 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

#Preview {
    // Use testing API for preview
    FilterView(
        emailService: EmailServiceImpl(accountManager: AccountManagerImpl.shared),
        accountManager: AccountManagerImpl.shared
    )
    .environmentObject(SettingsManager())
}
