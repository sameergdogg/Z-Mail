import SwiftUI
import WebKit

struct EmailContentRenderer: View {
    let email: Email
    @State private var webViewHeight: CGFloat = 0
    @State private var isLoading = true
    @State private var loadingError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView("Loading content...")
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            } else if let error = loadingError {
                ErrorView(message: error)
            } else {
                if email.isHTMLContent {
                    HTMLContentView(
                        htmlContent: email.htmlBody ?? email.body,
                        height: $webViewHeight
                    )
                    .frame(height: max(webViewHeight, 100))
                } else {
                    PlainTextContentView(content: email.body)
                }
            }
            
            if !email.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attachments (\(email.attachments.count))")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top)
                    
                    EmailMediaViewer(attachments: email.attachments)
                }
            }
        }
        .onAppear {
            loadContent()
        }
    }
    
    private func loadContent() {
        isLoading = false
    }
}

struct HTMLContentView: UIViewRepresentable {
    let htmlContent: String
    @Binding var height: CGFloat
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        
        let css = """
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.5;
            margin: 0;
            padding: 16px;
            background-color: transparent;
            color: black;
        }
        img {
            max-width: 100% !important;
            height: auto !important;
            border-radius: 8px;
            margin: 8px 0;
        }
        a {
            color: #007AFF;
            text-decoration: none;
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
        pre {
            background-color: #f5f5f5;
            padding: 12px;
            border-radius: 6px;
            overflow-x: auto;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
        }
        code {
            background-color: #f5f5f5;
            padding: 2px 4px;
            border-radius: 3px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
            font-size: 14px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 16px 0;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
        }
        th {
            background-color: #f5f5f5;
            font-weight: 600;
        }
        .email-quote {
            border-left: 2px solid #ccc;
            padding-left: 10px;
            margin-left: 10px;
            color: #666;
            font-size: 14px;
        }
        @media (prefers-color-scheme: dark) {
            body { color: white; }
            pre, code { background-color: #2c2c2e; color: white; }
            th { background-color: #2c2c2e; }
            th, td { border-color: #444; }
            .email-quote { color: #999; border-left-color: #555; }
        }
        </style>
        """
        
        let fullHTML = css + htmlContent
        webView.loadHTMLString(fullHTML, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLContentView
        
        init(_ parent: HTMLContentView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.readyState") { (complete, error) in
                if complete != nil {
                    webView.evaluateJavaScript("document.body.scrollHeight") { (height, error) in
                        if let height = height as? CGFloat {
                            DispatchQueue.main.async {
                                self.parent.height = height + 32
                            }
                        }
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

struct PlainTextContentView: View {
    let content: String
    
    var body: some View {
        Text(processPlainText(content))
            .font(.body)
            .lineSpacing(4)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(8)
    }
    
    private func processPlainText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

struct AttachmentsView: View {
    let attachments: [EmailAttachment]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
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
    @State private var isLoading = false
    
    var body: some View {
        HStack {
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
                            ProgressView()
                                .scaleEffect(0.5)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            Button(action: {
                downloadAttachment()
            }) {
                Image(systemName: isLoading ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private func downloadAttachment() {
        isLoading = true
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            DispatchQueue.main.async {
                isLoading = false
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text("Content Loading Error")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    ScrollView {
        VStack {
            EmailContentRenderer(
                email: Email(
                    id: "1",
                    subject: "HTML Email Test",
                    sender: EmailAddress(name: "John Doe", email: "john@example.com"),
                    recipients: [EmailAddress(name: nil, email: "user@gmail.com")],
                    body: "<h2>Welcome!</h2><p>This is an <strong>HTML email</strong> with <a href='https://apple.com'>links</a> and images.</p><img src='https://picsum.photos/300/200' alt='Sample'><blockquote>This is a quote</blockquote>",
                    date: Date(),
                    accountEmail: "user@gmail.com"
                )
            )
        }
        .padding()
    }
}