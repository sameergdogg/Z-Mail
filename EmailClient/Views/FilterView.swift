import SwiftUI

struct FilterView: View {
    let emailService: EmailServiceProtocol
    let accountManager: AccountManagerProtocol
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        NavigationView {
            List {
                statusFilterSection
                accountFilterSection
                emailSortSection
                senderSortSection
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

#Preview {
    // Use testing API for preview
    FilterView(
        emailService: EmailServiceAPI.createForTesting(accountManager: AccountManagerAPI.shared),
        accountManager: AccountManagerAPI.shared
    )
    .environmentObject(SettingsManager())
}