import SwiftUI

struct EmailDetailView: View {
    let email: Email
    let emailService: EmailService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EmailHeaderView(email: email, emailService: emailService)
                EmailContentRenderer(email: email)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !email.isRead {
                emailService.markAsRead(email)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { }) {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }

                    Button(action: { }) {
                        Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                    }

                    Button(action: { }) {
                        Label("Forward", systemImage: "arrowshape.turn.up.right")
                    }

                    Divider()

                    Button(action: { }) {
                        Label("Archive", systemImage: "archivebox")
                    }

                    Button(action: { }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

struct EmailHeaderView: View {
    let email: Email
    let emailService: EmailService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(email.subject)
                .font(.title2)
                .fontWeight(.bold)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("From:")
                            .fontWeight(.semibold)
                        Text(email.sender.displayName)
                    }
                    .font(.subheadline)

                    if !email.recipients.isEmpty {
                        HStack {
                            Text("To:")
                                .fontWeight(.semibold)
                            Text(email.recipients.map { $0.displayName }.joined(separator: ", "))
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                    }

                    Text(email.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    emailService.toggleStar(email)
                }) {
                    Image(systemName: email.isStarred ? "star.fill" : "star")
                        .foregroundColor(email.isStarred ? .yellow : .gray)
                        .font(.title2)
                }
            }

            if !email.labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(email.labels, id: \.self) { label in
                            Text(label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .foregroundColor(.gray)
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationView {
        EmailDetailView(
            email: Email(
                id: "1",
                subject: "Sample Email",
                sender: EmailAddress(name: "John Doe", email: "john@example.com"),
                recipients: [EmailAddress(name: nil, email: "user@gmail.com")],
                body: "This is a sample email body with some content to demonstrate how the email detail view looks.",
                htmlBody: "<h2>Sample HTML Email</h2><p>This is a <strong>sample email</strong> with HTML content.</p>",
                date: Date(),
                accountEmail: "user@gmail.com",
                attachments: [
                    EmailAttachment(
                        id: "1",
                        filename: "document.pdf",
                        mimeType: "application/pdf",
                        size: 1024000,
                        attachmentId: nil,
                        downloadURL: nil
                    )
                ],
                isHTMLContent: true
            ),
            emailService: EmailService(accountManager: AccountManager())
        )
    }
}

