import SwiftUI

struct SenderListView: View {
    let emailService: EmailServiceImpl
    @State private var senders: [EmailSender] = []
    @State private var filteredSenders: [EmailSender] = []
    @State private var searchText = ""
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        List {
            ForEach(filteredSenders) { sender in
                NavigationLink(destination: SenderEmailListView(sender: sender, emailService: emailService)) {
                    SenderRowView(sender: sender)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search senders...")
        .onAppear {
            loadSenders()
        }
        .onChange(of: emailService.emails) { _ in
            loadSenders()
        }
        .onChange(of: emailService.filteredEmails) { _ in
            loadSenders()
        }
        .onChange(of: emailService.currentFilter) { _ in
            loadSenders()
        }
        .onChange(of: searchText) { _ in
            filterSenders()
        }
        .onChange(of: settingsManager.senderSortOrder) { _ in
            filterSenders()
        }
    }
    
    private func loadSenders() {
        senders = emailService.getUniqueSenders()
        filterSenders()
    }
    
    private func filterSenders() {
        // First filter by search text
        let filtered = if searchText.isEmpty {
            senders
        } else {
            senders.filter { sender in
                sender.displayName.localizedCaseInsensitiveContains(searchText) ||
                sender.email.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Then sort according to selected sort order
        filteredSenders = sortSenders(filtered)
    }
    
    private func sortSenders(_ senders: [EmailSender]) -> [EmailSender] {
        switch settingsManager.senderSortOrder {
        case .alphabeticalAscending:
            return senders.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .alphabeticalDescending:
            return senders.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        case .emailCountAscending:
            return senders.sorted { $0.emailCount < $1.emailCount }
        case .emailCountDescending:
            return senders.sorted { $0.emailCount > $1.emailCount }
        case .conversationCountAscending:
            // For now, use email count as a proxy for conversation count
            // TODO: Implement actual conversation counting logic
            return senders.sorted { getConversationCount(for: $0) < getConversationCount(for: $1) }
        case .conversationCountDescending:
            // For now, use email count as a proxy for conversation count
            // TODO: Implement actual conversation counting logic
            return senders.sorted { getConversationCount(for: $0) > getConversationCount(for: $1) }
        }
    }
    
    private func getConversationCount(for sender: EmailSender) -> Int {
        // TODO: Implement actual conversation counting by analyzing email threads
        // For now, we'll use a simple heuristic: email count / 2 (assuming some back-and-forth)
        return max(1, sender.emailCount / 2)
    }
}

struct SenderRowView: View {
    let sender: EmailSender
    @State private var logoImage: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Smart avatar system
            SmartAvatarView(
                sender: sender,
                logoImage: $logoImage
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(cleanDisplayName(sender.displayName))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(sender.email)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Additional metadata
                senderMetadata
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Enhanced email count badge
                enhancedCountBadge
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            loadSenderLogo()
        }
    }
    
    
    @ViewBuilder
    private var senderMetadata: some View {
        HStack(spacing: 8) {
            // Domain indicator
            Text("@\(getDomain())")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blue)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.1))
                )
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var enhancedCountBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "envelope")
                .font(.system(size: 10))
                .foregroundColor(.white)
            
            Text("\(sender.emailCount)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(getCountBadgeColor())
        )
    }
    
    
    // MARK: - Helper Methods
    
    private func cleanDisplayName(_ name: String) -> String {
        var cleanName = name
        
        // Remove surrounding quotes
        if cleanName.hasPrefix("\"") && cleanName.hasSuffix("\"") {
            cleanName = String(cleanName.dropFirst().dropLast())
        }
        
        // Remove surrounding single quotes
        if cleanName.hasPrefix("'") && cleanName.hasSuffix("'") {
            cleanName = String(cleanName.dropFirst().dropLast())
        }
        
        // Remove surrounding parentheses if they wrap the entire name
        if cleanName.hasPrefix("(") && cleanName.hasSuffix(")") {
            cleanName = String(cleanName.dropFirst().dropLast())
        }
        
        // Trim whitespace
        cleanName = cleanName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanName.isEmpty ? name : cleanName
    }
    
    private func loadSenderLogo() {
        Task {
            if let image = await fetchSenderLogo() {
                await MainActor.run {
                    self.logoImage = image
                }
            }
        }
    }
    
    private func fetchSenderLogo() async -> UIImage? {
        let domain = getDomain()
        
        // Check for known company logos first
        if let knownLogo = getKnownCompanyLogo(domain: domain) {
            return knownLogo
        }
        
        // Try to fetch favicon
        return await fetchFavicon(domain: domain)
    }
    
    private func getKnownCompanyLogo(domain: String) -> UIImage? {
        switch domain.lowercased() {
        case "gmail.com", "google.com":
            return UIImage(systemName: "envelope.circle.fill")
        case "outlook.com", "hotmail.com", "live.com", "microsoft.com":
            return UIImage(systemName: "envelope.circle")
        case "apple.com", "icloud.com":
            return UIImage(systemName: "applelogo")
        case "amazon.com":
            return UIImage(systemName: "shippingbox.fill")
        case "netflix.com":
            return UIImage(systemName: "tv.fill")
        case "linkedin.com":
            return UIImage(systemName: "person.2.fill")
        case "facebook.com", "meta.com":
            return UIImage(systemName: "person.3.fill")
        case "twitter.com", "x.com":
            return UIImage(systemName: "bubble.left.and.bubble.right.fill")
        default:
            return nil
        }
    }
    
    private func fetchFavicon(domain: String) async -> UIImage? {
        let faviconURL = "https://\(domain)/favicon.ico"
        
        guard let url = URL(string: faviconURL) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
    
    private func getDomain() -> String {
        let components = sender.email.components(separatedBy: "@")
        return components.count > 1 ? components[1] : sender.email
    }
    
    private func getSenderType() -> SenderType {
        let domain = getDomain().lowercased()
        let email = sender.email.lowercased()
        
        // Business domains
        if domain.contains("noreply") || domain.contains("no-reply") || email.contains("noreply") {
            return .automated
        }
        
        // Known business domains
        let businessDomains = ["gmail.com", "outlook.com", "company.com", "corp.com"]
        if businessDomains.contains(where: { domain.contains($0) }) {
            return sender.emailCount > 10 ? .business : .personal
        }
        
        // Newsletter patterns
        if email.contains("newsletter") || email.contains("marketing") || email.contains("promo") {
            return .newsletter
        }
        
        // High volume = likely business/promotional
        if sender.emailCount > 20 {
            return .business
        } else if sender.emailCount > 5 {
            return .frequent
        }
        
        return .personal
    }
    
    private func getCountBadgeColor() -> Color {
        switch sender.emailCount {
        case 0...5:
            return .blue
        case 6...20:
            return .orange
        default:
            return .red
        }
    }
    
}

// MARK: - Smart Avatar View

struct SmartAvatarView: View {
    let sender: EmailSender
    @Binding var logoImage: UIImage?
    
    var body: some View {
        ZStack {
            // Background circle with smart coloring
            Circle()
                .fill(getAvatarBackgroundColor())
                .frame(width: 48, height: 48)
            
            if let logoImage = logoImage {
                // Company logo or favicon
                Image(uiImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                // Fallback to styled initials
                Text(senderInitial)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(getInitialTextColor())
            }
        }
        .overlay(
            // Activity indicator ring
            Circle()
                .stroke(getActivityRingColor(), lineWidth: 2)
                .frame(width: 50, height: 50)
                .opacity(0.8)
        )
    }
    
    private var senderInitial: String {
        if let name = sender.name, !name.isEmpty {
            let cleanName = cleanDisplayName(name)
            return String(cleanName.prefix(1).uppercased())
        } else {
            return String(sender.email.prefix(1).uppercased())
        }
    }
    
    private func cleanDisplayName(_ name: String) -> String {
        var cleanName = name
        
        // Remove surrounding quotes
        if cleanName.hasPrefix("\"") && cleanName.hasSuffix("\"") {
            cleanName = String(cleanName.dropFirst().dropLast())
        }
        
        // Remove surrounding single quotes
        if cleanName.hasPrefix("'") && cleanName.hasSuffix("'") {
            cleanName = String(cleanName.dropFirst().dropLast())
        }
        
        // Remove surrounding parentheses if they wrap the entire name
        if cleanName.hasPrefix("(") && cleanName.hasSuffix(")") {
            cleanName = String(cleanName.dropFirst().dropLast())
        }
        
        // Trim whitespace
        cleanName = cleanName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanName.isEmpty ? name : cleanName
    }
    
    private func getAvatarBackgroundColor() -> Color {
        let type = getSenderType()
        switch type {
        case .personal:
            return .blue.opacity(0.2)
        case .business:
            return .purple.opacity(0.2)
        case .newsletter:
            return .orange.opacity(0.2)
        case .automated:
            return .gray.opacity(0.2)
        case .frequent:
            return .green.opacity(0.2)
        case .unknown:
            return .blue.opacity(0.2)
        }
    }
    
    private func getInitialTextColor() -> Color {
        let type = getSenderType()
        switch type {
        case .personal:
            return .blue
        case .business:
            return .purple
        case .newsletter:
            return .orange
        case .automated:
            return .gray
        case .frequent:
            return .green
        case .unknown:
            return .blue
        }
    }
    
    private func getActivityRingColor() -> Color {
        if sender.emailCount > 10 {
            return .green
        } else if sender.emailCount > 3 {
            return .orange
        } else {
            return .clear
        }
    }
    
    private func getSenderType() -> SenderType {
        let domain = sender.email.components(separatedBy: "@")[1].lowercased()
        let email = sender.email.lowercased()
        
        if domain.contains("noreply") || domain.contains("no-reply") || email.contains("noreply") {
            return .automated
        }
        
        if email.contains("newsletter") || email.contains("marketing") || email.contains("promo") {
            return .newsletter
        }
        
        if sender.emailCount > 20 {
            return .business
        } else if sender.emailCount > 5 {
            return .frequent
        }
        
        return .personal
    }
}

// MARK: - Supporting Types

enum SenderType {
    case personal, business, newsletter, automated, frequent, unknown
    
    var label: String {
        switch self {
        case .personal: return "Personal"
        case .business: return "Business"
        case .newsletter: return "Newsletter"
        case .automated: return "Auto"
        case .frequent: return "Frequent"
        case .unknown: return ""
        }
    }
    
    var iconName: String {
        switch self {
        case .personal: return "person.fill"
        case .business: return "building.2.fill"
        case .newsletter: return "newspaper.fill"
        case .automated: return "gear.circle.fill"
        case .frequent: return "star.fill"
        case .unknown: return ""
        }
    }
    
    var color: Color {
        switch self {
        case .personal: return .blue
        case .business: return .purple
        case .newsletter: return .orange
        case .automated: return .gray
        case .frequent: return .green
        case .unknown: return .clear
        }
    }
}

struct SenderEmailListView: View {
    let sender: EmailSender
    let emailService: EmailServiceImpl
    @State private var senderEmails: [Email] = []
    
    var body: some View {
        List {
            ForEach(senderEmails) { email in
                NavigationLink(destination: EmailDetailView(email: email, emailService: emailService)) {
                    SenderEmailRowView(email: email, emailService: emailService)
                }
            }
        }
        .navigationTitle(sender.displayName)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadSenderEmails()
        }
        .onChange(of: emailService.emails) { _ in
            loadSenderEmails()
        }
    }
    
    private func loadSenderEmails() {
        senderEmails = emailService.getEmailsFromSender(sender)
    }
}

struct SenderEmailRowView: View {
    let email: Email
    let emailService: EmailServiceImpl
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Read status indicator
            Circle()
                .fill(email.isRead ? Color.clear : Color.blue)
                .frame(width: 8, height: 8)
                .padding(.top, 8)
            
            VStack(alignment: .leading, spacing: 4) {
                // Subject
                Text(email.subject.isEmpty ? "No Subject" : email.subject)
                    .font(.system(size: 16, weight: email.isRead ? .regular : .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // Preview text
                Text(email.body)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Date and star
                HStack {
                    Text(formatDate(email.date))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if email.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(action: {
                Task {
                    await emailService.toggleStar(email)
                }
            }) {
                Image(systemName: email.isStarred ? "star.slash" : "star.fill")
            }
            .tint(email.isStarred ? .gray : .yellow)
            
            Button(action: {
                if !email.isRead {
                    Task {
                        await emailService.markAsRead(email)
                    }
                }
            }) {
                Image(systemName: email.isRead ? "envelope.badge" : "envelope.open")
            }
            .tint(email.isRead ? .orange : .blue)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationView {
        SenderListView(emailService: EmailServiceImpl(accountManager: AccountManagerImpl.shared))
    }
}