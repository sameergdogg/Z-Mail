import SwiftUI
import WebKit

struct EmailDetailView: View {
    let email: Email
    let emailService: EmailService
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(email.subject)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
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
                        
                        VStack {
                            Button(action: {
                                emailService.toggleStar(email)
                            }) {
                                Image(systemName: email.isStarred ? "star.fill" : "star")
                                    .foregroundColor(email.isStarred ? .yellow : .gray)
                                    .font(.title2)
                            }
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
                                        .background(.gray.opacity(0.1))
                                        .foregroundColor(.gray)
                                        .cornerRadius(6)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding()
                .background(.gray.opacity(0.05))
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Message")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    EmailContentView(email: email)
                }
                .padding()
                
                Spacer()
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
                    Button(action: {
                        
                    }) {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    
                    Button(action: {
                        
                    }) {
                        Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                    }
                    
                    Button(action: {
                        
                    }) {
                        Label("Forward", systemImage: "arrowshape.turn.up.right")
                    }
                    
                    Divider()
                    
                    Button(action: {
                        
                    }) {
                        Label("Archive", systemImage: "archivebox")
                    }
                    
                    Button(action: {
                        
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

struct EmailContentView: View {
    let email: Email
    @State private var webViewHeight: CGFloat = 0
    @State private var isLoading = true
    @State private var contentToShow: String = ""
    @State private var shouldUseWebView: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                ProgressView("Loading content...")
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        processEmailContent()
                    }
            } else {
                if shouldUseWebView {
                    HTMLEmailView(
                        htmlContent: contentToShow,
                        height: $webViewHeight
                    )
                    .frame(minHeight: max(webViewHeight, 200))
                } else {
                    PlainTextEmailView(content: contentToShow)
                }
                
                if !email.attachments.isEmpty {
                    AttachmentSectionView(attachments: email.attachments)
                }
            }
        }
    }
    
    private func processEmailContent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Determine what content to show and how to show it
            if let htmlBody = email.htmlBody, !htmlBody.isEmpty, htmlBody.contains("<") {
                // We have HTML content, use WebView
                contentToShow = htmlBody
                shouldUseWebView = true
            } else if email.body.contains("<") && email.body.contains(">") {
                // Body appears to be HTML, use WebView
                contentToShow = email.body
                shouldUseWebView = true
            } else if email.body.contains("http") && email.body.contains("[") {
                // Body contains links in bracket format, might need HTML rendering
                contentToShow = convertLinksToHTML(email.body)
                shouldUseWebView = true
            } else {
                // Use plain text
                contentToShow = email.body
                shouldUseWebView = false
            }
            
            isLoading = false
        }
    }
    
    private func convertLinksToHTML(_ text: String) -> String {
        var htmlContent = text
        
        // Handle promotional email format like [SHOP NOW](URL)
        let linkPattern = #"\[([^\]]+)\]\((https?://[^\)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            let range = NSRange(htmlContent.startIndex..<htmlContent.endIndex, in: htmlContent)
            htmlContent = regex.stringByReplacingMatches(in: htmlContent, options: [], range: range, withTemplate: "<div style=\"margin: 12px 0;\"><a href=\"$2\" style=\"display: inline-block; padding: 12px 20px; background-color: #007AFF; color: white; text-decoration: none; border-radius: 8px; font-weight: 600;\">$1</a></div>")
        }
        
        // Convert standalone URLs to clickable links
        let urlPattern = #"(https?://[^\s\)]+)"#
        if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
            let range = NSRange(htmlContent.startIndex..<htmlContent.endIndex, in: htmlContent)
            htmlContent = urlRegex.stringByReplacingMatches(in: htmlContent, options: [], range: range, withTemplate: "<a href=\"$1\" style=\"word-break: break-all; color: #007AFF;\">$1</a>")
        }
        
        // Convert plain text lines to paragraphs
        let lines = htmlContent.components(separatedBy: "\n")
        let paragraphs = lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "<p>\(trimmed)</p>"
        }
        
        return paragraphs.joined(separator: "\n")
    }
}

struct HTMLEmailView: UIViewRepresentable {
    let htmlContent: String
    @Binding var height: CGFloat
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let css = """
        <style>
        * {
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.5;
            margin: 0;
            padding: 16px;
            background-color: transparent !important;
            word-wrap: break-word;
            overflow-wrap: break-word;
            -webkit-text-size-adjust: none;
        }
        img {
            max-width: 100% !important;
            height: auto !important;
            border-radius: 8px;
            margin: 8px 0;
            display: block;
        }
        a {
            color: #007AFF !important;
            text-decoration: none;
            word-break: break-all;
        }
        a:hover {
            text-decoration: underline;
        }
        blockquote {
            border-left: 3px solid #007AFF;
            margin: 16px 0;
            padding-left: 16px;
            color: #666;
            font-style: italic;
        }
        pre, code {
            background-color: #f5f5f5;
            padding: 8px;
            border-radius: 4px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, monospace;
            white-space: pre-wrap;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 16px 0;
            table-layout: fixed;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
            word-wrap: break-word;
        }
        th {
            background-color: #f5f5f5;
            font-weight: 600;
        }
        p {
            margin: 8px 0;
        }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 20px;
            margin-bottom: 10px;
        }
        /* Handle promotional email styles */
        .button, .btn {
            display: inline-block;
            padding: 12px 20px;
            background-color: #007AFF;
            color: white !important;
            text-decoration: none;
            border-radius: 8px;
            margin: 8px 0;
        }
        @media (prefers-color-scheme: dark) {
            body { 
                color: white !important; 
                background-color: transparent !important;
            }
            pre, code { 
                background-color: #2c2c2e; 
                color: white;
            }
            th { 
                background-color: #2c2c2e; 
                color: white;
            }
            th, td { 
                border-color: #444; 
                color: white;
            }
            a {
                color: #0A84FF !important;
            }
        }
        </style>
        """
        
        let wrappedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            \(css)
        </head>
        <body>
            \(htmlContent)
        </body>
        </html>
        """
        
        uiView.loadHTMLString(wrappedHTML, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLEmailView
        
        init(_ parent: HTMLEmailView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { (height, error) in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = height + 32
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

struct PlainTextEmailView: View {
    let content: String
    
    var body: some View {
        Text(content)
            .font(.body)
            .lineSpacing(4)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
    }
}

struct AttachmentSectionView: View {
    let attachments: [EmailAttachment]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments (\(attachments.count))")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVStack(spacing: 8) {
                ForEach(attachments, id: \.id) { attachment in
                    AttachmentRowView(attachment: attachment)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct AttachmentRowView: View {
    let attachment: EmailAttachment
    @State private var isDownloading = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: attachment.systemImageName)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(attachment.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if attachment.isImage {
                AsyncImage(url: attachment.downloadURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            Button(action: {
                isDownloading = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    isDownloading = false
                }
            }) {
                Image(systemName: isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .disabled(isDownloading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
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