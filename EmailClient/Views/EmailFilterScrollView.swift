import SwiftUI

struct EmailFilterScrollView: View {
    @Binding var selectedFilter: TopLevelFilter
    let emailService: EmailServiceProtocol
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TopLevelFilter.allCases, id: \.self) { filter in
                    FilterButton(
                        title: filter.displayName,
                        isSelected: selectedFilter == filter,
                        action: {
                            selectedFilter = filter
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 4)
        .background(Color(UIColor.systemBackground))
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(UIColor.systemGray5))
                        .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 3 : 1, x: 0, y: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

enum TopLevelFilter: String, CaseIterable {
    case inbox = "inbox"
    case senders = "senders"
    case categories = "categories"
    case summary = "summary"
    
    var displayName: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .senders:
            return "Senders"
        case .categories:
            return "Categories"
        case .summary:
            return "Summary"
        }
    }
}

#Preview {
    EmailFilterScrollView(
        selectedFilter: .constant(.inbox),
        emailService: EmailServiceAPI.createForTesting(accountManager: AccountManagerAPI.shared)
    )
}