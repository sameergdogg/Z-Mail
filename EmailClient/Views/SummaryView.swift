import SwiftUI
import Foundation

struct SummaryView: View {
    let emailService: EmailServiceImpl
    @State private var selectedDate: Date = Date()
    @State private var dailyDigest: DailyDigest?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private var hasEmailsForSelectedDate: Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        return emailService.filteredEmails.contains { email in
            email.date >= startOfDay && email.date < endOfDay
        }
    }
    
    var body: some View {
        ZStack {
            // White background
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Date selector header
                DateSelectorView(selectedDate: $selectedDate)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                // Digest content
                ScrollView {
                    if isLoading {
                        LoadingDigestView()
                    } else if let digest = dailyDigest {
                        DigestContentView(digest: digest)
                    } else if let error = errorMessage {
                        ErrorDigestView(message: error, onRetry: generateDigestManually)
                    } else {
                        EmptyDigestView(hasEmails: hasEmailsForSelectedDate, onGenerate: generateDigestManually)
                    }
                }
            }
        }
        .onAppear {
            loadDigestForDate()
        }
        .onChange(of: selectedDate) { _ in
            loadDigestForDate()
        }
    }
    
    private func loadDigestForDate() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // First check if we have a persisted digest for this date
                if let persistedDigest = emailService.loadDigest(for: selectedDate) {
                    await MainActor.run {
                        dailyDigest = persistedDigest
                        isLoading = false
                    }
                    print("📊 Loaded persisted digest for \(selectedDate)")
                    return
                }
                
                // No persisted digest found, create sample or generate new one
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: selectedDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
                
                let dayEmails = emailService.filteredEmails.filter { email in
                    email.date >= startOfDay && email.date < endOfDay
                }
                
                guard !dayEmails.isEmpty else {
                    await MainActor.run {
                        dailyDigest = nil
                        isLoading = false
                    }
                    return
                }
                
                // Get API key from secure configuration
                guard let apiKey = SecureConfigurationManager.shared.getOpenAIAPIKey() else {
                    // For demo purposes, create a sample digest when no API key is available
                    let sampleDigest = createSampleDigest(for: selectedDate, emailCount: dayEmails.count)
                    await MainActor.run {
                        dailyDigest = sampleDigest
                        isLoading = false
                    }
                    return
                }
                
                // Generate digest automatically for today and yesterday only
                if !calendar.isDateInToday(selectedDate) && !calendar.isDateInYesterday(selectedDate) {
                    await MainActor.run {
                        dailyDigest = nil
                        isLoading = false
                    }
                    return
                }
                
                await generateDigest(for: selectedDate, dayEmails: dayEmails, apiKey: apiKey)
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func generateDigestManually() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Get API key from secure configuration
                guard let apiKey = SecureConfigurationManager.shared.getOpenAIAPIKey() else {
                    await MainActor.run {
                        errorMessage = "Please configure your OpenAI API key in Settings first."
                        isLoading = false
                    }
                    return
                }
                
                // Filter emails for the selected date
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: selectedDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
                
                let dayEmails = emailService.filteredEmails.filter { email in
                    email.date >= startOfDay && email.date < endOfDay
                }
                
                guard !dayEmails.isEmpty else {
                    await MainActor.run {
                        errorMessage = "No emails found for the selected date."
                        isLoading = false
                    }
                    return
                }
                
                await generateDigest(for: selectedDate, dayEmails: dayEmails, apiKey: apiKey)
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func generateDigest(for date: Date, dayEmails: [Email], apiKey: String) async {
        do {
            guard let context = AppDataManager.shared.modelContext else {
                throw ClassificationError.classificationFailed("ModelContext not available")
            }
            let classificationService = ClassificationService(modelContext: context)

            // Build ClassifiedEmail list from already-classified emails
            var finalClassifiedEmails: [ClassifiedEmail] = dayEmails.compactMap { email in
                guard let category = email.classificationCategory,
                      let confidence = email.classificationConfidence else { return nil }

                let domain = email.senderEmail.components(separatedBy: "@").last ?? ""
                let bodyExcerpt = String(email.body.prefix(200))

                return ClassifiedEmail(
                    id: email.id,
                    sender: email.senderEmail,
                    domain: domain,
                    subject: email.subject,
                    date: ISO8601DateFormatter().string(from: email.date),
                    category: category,
                    confidence: confidence,
                    summary: email.classificationSummary,
                    bodyExcerpt: bodyExcerpt,
                    threadKey: email.threadId,
                    entities: nil
                )
            }

            // Generate digest
            let calendar = Calendar.current
            let period = calendar.isDateInToday(date) ? "today" : "on \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))"
            let digest = try await classificationService.generateDailyDigest(finalClassifiedEmails, period: period, apiKey: apiKey)

            // Save digest to persistence
            let accountEmails = Set(dayEmails.map { $0.accountEmail }).sorted()
            try emailService.saveDigest(digest, for: date, emailCount: dayEmails.count, accountEmails: accountEmails)

            await MainActor.run {
                dailyDigest = digest
                isLoading = false
            }

            print("Generated and saved digest for \(date)")

        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func createSampleDigest(for date: Date, emailCount: Int) -> DailyDigest {
        let isToday = Calendar.current.isDateInToday(date)
        let dayName = isToday ? "today" : DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        
        return DailyDigest(
            headline: emailCount > 0 ? "You have been connected, progress flows" : "A quiet day unfolds, ready for focus",
            pillars: DigestPillars(
                power: emailCount > 0 ? ["New opportunities in routine communications", "Building momentum through consistent email management"] : ["Clarity in digital stillness"],
                pressure: emailCount > 5 ? ["High email volume demanding attention", "Multiple threads requiring responses"] : [],
                trouble: emailCount > 10 ? ["Inbox overflow creating overwhelm"] : []
            ),
            highlights: createSampleHighlights(emailCount: emailCount),
            actions: createSampleActions(emailCount: emailCount),
            money: DigestMoney(
                charges: [],
                payouts: [],
                billsDue: [],
                balances: []
            ),
            packages: [],
            calendar: [],
            security: [],
            stats: DigestStats(
                totals: [:],
                topSenders: emailCount > 0 ? [
                    DigestSender(sender: "notifications@github.com", count: 3),
                    DigestSender(sender: "team@slack.com", count: 2)
                ] : [],
                threads: max(1, emailCount / 2)
            ),
            narrative: DigestNarrative(
                long: emailCount > 0 ? "Today brings \(emailCount) email\(emailCount == 1 ? "" : "s") to your attention. Each message represents a connection point in your digital ecosystem. Your heightened awareness today can help you navigate these communications with purpose and clarity." : "In the absence of digital noise, there's space for deeper focus. Use this quiet moment to reflect on your priorities and prepare for upcoming challenges.",
                microcopy: DigestMicrocopy(
                    power: "Steady progress",
                    pressure: "Manage flow",
                    trouble: "Stay grounded"
                )
            )
        )
    }
    
    private func createSampleHighlights(emailCount: Int) -> [DigestHighlight] {
        guard emailCount > 0 else { return [] }
        
        var highlights: [DigestHighlight] = []
        
        if emailCount >= 1 {
            highlights.append(DigestHighlight(
                summary: "Project update from development team",
                category: "work",
                source: "team@company.com",
                id: "highlight-1"
            ))
        }
        
        if emailCount >= 3 {
            highlights.append(DigestHighlight(
                summary: "Weekly newsletter with industry insights",
                category: "promotions",
                source: "newsletter@industry.com",
                id: "highlight-2"
            ))
        }
        
        if emailCount >= 5 {
            highlights.append(DigestHighlight(
                summary: "Calendar invite for important meeting",
                category: "appointments",
                source: "calendar@company.com",
                id: "highlight-3"
            ))
        }
        
        return highlights
    }
    
    private func createSampleActions(emailCount: Int) -> [DigestAction] {
        guard emailCount > 0 else { return [] }
        
        var actions: [DigestAction] = []
        
        if emailCount >= 2 {
            actions.append(DigestAction(
                title: "Reply to team discussion",
                due: nil,
                source: "team@company.com",
                msgIds: ["msg-1"],
                priority: .med
            ))
        }
        
        if emailCount >= 4 {
            actions.append(DigestAction(
                title: "Review and approve document",
                due: "Tomorrow",
                source: "manager@company.com",
                msgIds: ["msg-2"],
                priority: .high
            ))
        }
        
        if emailCount >= 6 {
            actions.append(DigestAction(
                title: "Schedule follow-up meeting",
                due: "This week",
                source: "client@external.com",
                msgIds: ["msg-3"],
                priority: .low
            ))
        }
        
        return actions
    }
    
    static func colorFromString(_ colorString: String) -> Color {
        switch colorString.lowercased() {
        case "orange":
            return .orange
        case "brown":
            return .brown
        case "green":
            return .green
        case "blue":
            return .blue
        case "purple":
            return .purple
        case "red":
            return .red
        case "yellow":
            return .yellow
        case "gray":
            return .gray
        default:
            return .gray
        }
    }
}

struct DateSelectorView: View {
    @Binding var selectedDate: Date
    private let calendar = Calendar.current
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(-7...0, id: \.self) { dayOffset in
                    let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
                    DateButton(
                        date: date,
                        isSelected: calendar.isDate(selectedDate, inSameDayAs: date),
                        action: {
                            selectedDate = date
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct DateButton: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'TODAY'"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'YESTERDAY'"
        } else {
            formatter.dateFormat = "EEE"
        }
        return formatter
    }
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(dateFormatter.string(from: date))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .blue : .primary)
                
                Text(dayFormatter.string(from: date))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .blue : .primary)
            }
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DigestContentView: View {
    let digest: DailyDigest
    
    var body: some View {
        VStack(spacing: 24) {
            // Main headline card
            DigestHeadlineCard(headline: digest.headline, narrative: digest.narrative)
            
            // Pillars section
            DigestPillarsCard(pillars: digest.pillars)
            
            // Highlights section
            if !digest.highlights.isEmpty {
                DigestHighlightsCard(highlights: digest.highlights)
            }
            
            // Actions section
            if !digest.actions.isEmpty {
                DigestActionsCard(actions: digest.actions)
            }
            
            // Money section
            if hasMoneyData(digest.money) {
                DigestMoneyCard(money: digest.money)
            }
            
            // Stats section
            DigestStatsCard(stats: digest.stats)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func hasMoneyData(_ money: DigestMoney) -> Bool {
        return !money.charges.isEmpty || !money.payouts.isEmpty || !money.billsDue.isEmpty || !money.balances.isEmpty
    }
}

struct DigestHeadlineCard: View {
    let headline: String
    let narrative: DigestNarrative
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(headline)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Text(narrative.long)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

struct DigestPillarsCard: View {
    let pillars: DigestPillars
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Power section
            if !pillars.power.isEmpty {
                PillarSection(
                    emoji: "🚀",
                    title: "Power",
                    items: pillars.power,
                    color: .green
                )
            }
            
            // Pressure section
            if !pillars.pressure.isEmpty {
                PillarSection(
                    emoji: "🔥",
                    title: "Pressure",
                    items: pillars.pressure,
                    color: .orange
                )
            }
            
            // Trouble section
            if !pillars.trouble.isEmpty {
                PillarSection(
                    emoji: "🚫",
                    title: "Trouble",
                    items: pillars.trouble,
                    color: .red
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

struct PillarSection: View {
    let emoji: String
    let title: String
    let items: [String]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.title3)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

struct DigestHighlightsCard: View {
    let highlights: [DigestHighlight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            ForEach(highlights.prefix(8), id: \.id) { highlight in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlight.summary)
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        Text(highlight.category.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

struct DigestActionsCard: View {
    let actions: [DigestAction]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            ForEach(actions.prefix(8), id: \.title) { action in
                HStack(spacing: 12) {
                    Image(systemName: priorityIcon(action.priority))
                        .foregroundColor(priorityColor(action.priority))
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        if let due = action.due {
                            Text("Due: \(due)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    Text(action.priority.rawValue.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(priorityColor(action.priority))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
        )
    }
    
    private func priorityIcon(_ priority: ActionPriority) -> String {
        switch priority {
        case .high:
            return "exclamationmark.triangle.fill"
        case .med:
            return "clock.fill"
        case .low:
            return "info.circle.fill"
        }
    }
    
    private func priorityColor(_ priority: ActionPriority) -> Color {
        switch priority {
        case .high:
            return .red
        case .med:
            return .orange
        case .low:
            return .blue
        }
    }
}

struct DigestMoneyCard: View {
    let money: DigestMoney
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Money")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            if !money.charges.isEmpty {
                MoneySection(title: "Charges", items: money.charges, color: .red)
            }
            
            if !money.billsDue.isEmpty {
                MoneySection(title: "Bills Due", items: money.billsDue, color: .orange)
            }
            
            if !money.payouts.isEmpty {
                MoneySection(title: "Payouts", items: money.payouts, color: .green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

struct MoneySection: View {
    let title: String
    let items: [DigestMoneyItem]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
            
            ForEach(items.prefix(3), id: \.description) { item in
                HStack {
                    if let amount = item.amount, let currency = item.currency {
                        Text("\(currency)\(amount, specifier: "%.2f")")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(color)
                    }
                    
                    if let description = item.description {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                }
            }
        }
    }
}

struct DigestStatsCard: View {
    let stats: DigestStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            HStack(spacing: 24) {
                StatItem(title: "Threads", value: "\(stats.threads)")
                
                if !stats.topSenders.isEmpty {
                    StatItem(title: "Top Sender", value: stats.topSenders[0].sender)
                }
            }
            
            if stats.topSenders.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Senders:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ForEach(stats.topSenders.prefix(3), id: \.sender) { sender in
                        HStack {
                            Text(sender.sender)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("\(sender.count)")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

struct StatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct LoadingDigestView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            Text("Generating your digest...")
                .font(.title3)
                .foregroundColor(.primary)
            
            Text("Analyzing your emails with AI")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

struct ErrorDigestView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Unable to Generate Digest")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: onRetry) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(.orange)
                )
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

struct EmptyDigestView: View {
    let hasEmails: Bool
    let onGenerate: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasEmails ? "doc.text.magnifyingglass" : "tray")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text(hasEmails ? "No Digest Available" : "No Emails Today")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(hasEmails ? "Generate a daily digest for your emails from this date" : "Your daily digest will appear here when you have emails")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if hasEmails {
                Button(action: onGenerate) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Generate Digest")
                    }
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(.blue)
                    )
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Supporting Types

struct DateGroup {
    let date: Date
    let emails: [Email]
}

#Preview {
    SummaryView(emailService: EmailServiceImpl(accountManager: AccountManagerImpl.shared))
}
