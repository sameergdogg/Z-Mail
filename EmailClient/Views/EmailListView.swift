import SwiftUI

struct EmailListView: View {
    @EnvironmentObject var accountManager: AccountManager
    @StateObject private var emailService = EmailService(accountManager: AccountManager())
    @State private var showingFilters = false
    
    var body: some View {
        NavigationView {
            VStack {
                if emailService.isLoading {
                    ProgressView("Loading emails...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = emailService.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Unable to Load Emails")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(errorMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            Task {
                                await emailService.refreshEmails()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if emailService.filteredEmails.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No Emails")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Pull to refresh or check your filter settings")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(emailService.filteredEmails) { email in
                            NavigationLink(destination: EmailDetailView(email: email, emailService: emailService)) {
                                EmailRowView(email: email, emailService: emailService)
                            }
                        }
                    }
                    .refreshable {
                        await emailService.refreshEmails()
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingFilters = true
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await emailService.refreshEmails()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterView(emailService: emailService, accountManager: accountManager)
            }
        }
        .onAppear {
            Task {
                await emailService.refreshEmails()
            }
        }
    }
}

struct EmailRowView: View {
    let email: Email
    let emailService: EmailService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(email.sender.displayName)
                            .font(.headline)
                            .fontWeight(email.isRead ? .regular : .semibold)
                        
                        Spacer()
                        
                        if email.isStarred {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                        
                        Text(email.date, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(email.subject)
                        .font(.subheadline)
                        .fontWeight(email.isRead ? .regular : .medium)
                        .lineLimit(1)
                    
                    Text(email.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if !email.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }
            
            HStack {
                Text(email.accountEmail)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
                
                Spacer()
                
                ForEach(email.labels.prefix(2), id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.1))
                        .foregroundColor(.gray)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(action: {
                emailService.toggleStar(email)
            }) {
                Image(systemName: email.isStarred ? "star.slash" : "star")
            }
            .tint(.yellow)
            
            Button(action: {
                if !email.isRead {
                    emailService.markAsRead(email)
                }
            }) {
                Image(systemName: email.isRead ? "envelope.badge" : "envelope.open")
            }
            .tint(.blue)
        }
    }
}

#Preview {
    EmailListView()
        .environmentObject(AccountManager())
}