import SwiftUI

struct CategoryEmailsView: View {
    let category: EmailCategory
    let emailService: EmailServiceImpl
    
    @State private var categoryEmails: [Email] = []
    @State private var isLoading = true
    @State private var showingFilters = false
    @State private var selectedFilter: CategoryFilter = .all
    
    enum CategoryFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case recent = "Recent"
        case highConfidence = "High Confidence"
        
        var icon: String {
            switch self {
            case .all: return "tray"
            case .unread: return "envelope.badge"
            case .recent: return "clock"
            case .highConfidence: return "checkmark.seal"
            }
        }
    }
    
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
    
    private var filteredEmails: [Email] {
        var emails = categoryEmails
        
        switch selectedFilter {
        case .all:
            break
        case .unread:
            emails = emails.filter { !$0.isRead }
        case .recent:
            let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            emails = emails.filter { $0.date > oneWeekAgo }
        case .highConfidence:
            emails = emails.filter { ($0.classificationConfidence ?? 0) > 0.8 }
        }
        
        return emails
    }
    
    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
            VStack(spacing: 0) {
                // Category header
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        // Category icon
                        Image(systemName: category.iconName)
                            .font(.title)
                            .foregroundColor(categoryColor)
                            .frame(width: 44, height: 44)
                            .background(categoryColor.opacity(0.1))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.displayName)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(categoryDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Filter button
                        Button(action: {
                            showingFilters.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: selectedFilter.icon)
                                Text(selectedFilter.rawValue)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.systemGray5))
                            .cornerRadius(16)
                        }
                        .foregroundColor(.primary)
                    }
                    
                    // Stats row
                    HStack(spacing: 16) {
                        StatView(
                            icon: "envelope",
                            value: "\(categoryEmails.count)",
                            label: "Total"
                        )
                        
                        StatView(
                            icon: "envelope.badge",
                            value: "\(categoryEmails.filter { !$0.isRead }.count)",
                            label: "Unread"
                        )
                        
                        if let avgConfidence = averageConfidence {
                            StatView(
                                icon: "brain",
                                value: String(format: "%.0f%%", avgConfidence * 100),
                                label: "Confidence"
                            )
                        }
                        
                        Spacer()
                    }
                }
                .padding()
                .background(Color(UIColor.systemGroupedBackground))
                
                // Emails list
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Loading emails...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
                    
                } else if filteredEmails.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: category.iconName)
                            .font(.system(size: 50))
                            .foregroundColor(categoryColor.opacity(0.6))
                        
                        Text("No emails found")
                            .font(.title3)
                            .fontWeight(.medium)
                        
                        Text(emptyStateMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
                    
                } else {
                    List {
                        ForEach(filteredEmails, id: \.id) { email in
                            NavigationLink(destination: EmailDetailView(email: email, emailService: emailService).environmentObject(SettingsManager())) {
                                CategoryEmailRowView(email: email, showConfidence: true)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(email.isRead ? "Mark Unread" : "Mark Read") {
                                    toggleReadStatus(for: email)
                                }
                                .tint(email.isRead ? .orange : .blue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button(email.isStarred ? "Unstar" : "Star") {
                                    toggleStarStatus(for: email)
                                }
                                .tint(.yellow)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(PlainListStyle())
                    .background(Color(UIColor.systemGroupedBackground))
                    .refreshable {
                        await loadCategoryEmails()
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFilters) {
            FilterSelectionSheet(selectedFilter: $selectedFilter)
        }
        .onAppear {
            Task {
                await loadCategoryEmails()
            }
        }
    }
    
    private var categoryDescription: String {
        switch category {
        case .promotions:
            return "Marketing emails, deals, newsletters, advertisements"
        case .orderHistory:
            return "Purchase receipts, shipping updates, order confirmations"
        case .finance:
            return "Banking, bills, payments, investments"
        case .personal:
            return "Personal communication, family, friends"
        case .work:
            return "Work emails, meetings, projects"
        case .appointments:
            return "Scheduling, reminders, calendar invites"
        case .signInAlerts:
            return "Security alerts, login notifications, account access"
        case .other:
            return "Everything else"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedFilter {
        case .all:
            return "No emails have been classified in this category yet."
        case .unread:
            return "All emails in this category have been read."
        case .recent:
            return "No emails from the past week in this category."
        case .highConfidence:
            return "No emails with high classification confidence in this category."
        }
    }
    
    private var averageConfidence: Double? {
        let confidenceValues = categoryEmails.compactMap { $0.classificationConfidence }
        guard !confidenceValues.isEmpty else { return nil }
        return confidenceValues.reduce(0, +) / Double(confidenceValues.count)
    }
    
    private func loadCategoryEmails() async {
        isLoading = true
        
        // Filter emails from the service by category
        let allEmails = emailService.emails
        let filtered = allEmails.filter { email in
            email.classificationCategory == category.rawValue && email.isClassified
        }
        
        await MainActor.run {
            self.categoryEmails = filtered.sorted { $0.date > $1.date }
            self.isLoading = false
        }
    }
    
    private func toggleReadStatus(for email: Email) {
        // Update read status through email service
        Task {
            if email.isRead {
                await emailService.markAsUnread(email)
            } else {
                await emailService.markAsRead(email)
            }
            await loadCategoryEmails() // Refresh the list
        }
    }
    
    private func toggleStarStatus(for email: Email) {
        // Update star status through email service
        Task {
            await emailService.toggleStar(email)
            await loadCategoryEmails() // Refresh the list
        }
    }
}

struct CategoryEmailRowView: View {
    let email: Email
    let showConfidence: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(email.sender.displayName)
                        .font(.headline)
                        .foregroundColor(email.isRead ? .secondary : .primary)
                        .lineLimit(1)
                    
                    Text(email.subject)
                        .font(.subheadline)
                        .foregroundColor(email.isRead ? .secondary : .primary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(email.date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        if !email.isRead {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                        }
                        
                        if email.isStarred {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        
                        if showConfidence, let confidence = email.classificationConfidence {
                            Text("\(Int(confidence * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            if !email.body.isEmpty {
                Text(email.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

struct StatView: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.primary)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct FilterSelectionSheet: View {
    @Binding var selectedFilter: CategoryEmailsView.CategoryFilter
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(CategoryEmailsView.CategoryFilter.allCases, id: \.rawValue) { filter in
                    Button(action: {
                        selectedFilter = filter
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: filter.icon)
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text(filter.rawValue)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedFilter == filter {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Filter Emails")
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
}

#Preview {
    NavigationStack {
        CategoryEmailsView(
            category: .work,
            emailService: EmailServiceAPI.shared(with: AccountManagerAPI.shared) as! EmailServiceImpl
        )
    }
}
