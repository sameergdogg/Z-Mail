import SwiftUI

struct SenderListView: View {
    let emailService: EmailServiceProtocol
    @State private var senders: [EmailSender] = []
    @State private var filteredSenders: [EmailSender] = []
    @State private var searchText = ""
    
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
        .onChange(of: searchText) { _ in
            filterSenders()
        }
    }
    
    private func loadSenders() {
        senders = emailService.getUniqueSenders()
        filterSenders()
    }
    
    private func filterSenders() {
        if searchText.isEmpty {
            filteredSenders = senders
        } else {
            filteredSenders = senders.filter { sender in
                sender.displayName.localizedCaseInsensitiveContains(searchText) ||
                sender.email.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct SenderRowView: View {
    let sender: EmailSender
    
    var body: some View {
        HStack {
            // Sender avatar/initial
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(senderInitial)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(sender.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(sender.email)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Email count badge
            Text("\(sender.emailCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue)
                )
        }
        .padding(.vertical, 4)
    }
    
    private var senderInitial: String {
        if let name = sender.name, !name.isEmpty {
            return String(name.prefix(1).uppercased())
        } else {
            return String(sender.email.prefix(1).uppercased())
        }
    }
}

struct SenderEmailListView: View {
    let sender: EmailSender
    let emailService: EmailServiceProtocol
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
    let emailService: EmailServiceProtocol
    
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
        SenderListView(emailService: EmailServiceAPI.createForTesting(accountManager: AccountManagerAPI.shared))
    }
}