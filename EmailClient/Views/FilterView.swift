import SwiftUI

struct FilterView: View {
    let emailService: EmailService
    let accountManager: AccountManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
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
                
                Section("Filter by Account") {
                    ForEach(accountManager.accounts) { account in
                        FilterOptionView(
                            title: account.email,
                            isSelected: isSelected(.account(account.email)),
                            action: { emailService.applyFilter(.account(account.email)) }
                        )
                    }
                }
                
                Section("Sort Order") {
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
        default:
            return false
        }
    }
}

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

#Preview {
    FilterView(
        emailService: EmailService(accountManager: AccountManager()),
        accountManager: AccountManager()
    )
}