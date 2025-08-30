import SwiftUI
import AVKit
import QuickLook
import UniformTypeIdentifiers

struct EmailMediaViewer: View {
    let attachments: [EmailAttachment]
    @State private var selectedAttachment: EmailAttachment?
    @State private var showingQuickLook = false
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(attachments, id: \.id) { attachment in
                EmailMediaItemView(
                    attachment: attachment,
                    onTap: {
                        selectedAttachment = attachment
                        if attachment.supportsQuickLook {
                            showingQuickLook = true
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingQuickLook) {
            if let attachment = selectedAttachment {
                QuickLookPreview(attachment: attachment)
            }
        }
    }
}

struct EmailMediaItemView: View {
    let attachment: EmailAttachment
    let onTap: () -> Void
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(attachment.filename)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Text(attachment.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if attachment.isImage {
                ImagePreviewView(attachment: attachment, onTap: onTap)
            } else if attachment.isVideo {
                VideoPreviewView(attachment: attachment, onTap: onTap)
            } else {
                DocumentPreviewView(attachment: attachment, onTap: onTap)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ImagePreviewView: View {
    let attachment: EmailAttachment
    let onTap: () -> Void
    
    var body: some View {
        AsyncImage(url: attachment.downloadURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    VStack {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.top, 4)
                    }
                )
        }
        .frame(maxHeight: 300)
        .onTapGesture {
            onTap()
        }
    }
}

struct VideoPreviewView: View {
    let attachment: EmailAttachment
    let onTap: () -> Void
    @State private var showingPlayer = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black)
            .aspectRatio(16/9, contentMode: .fit)
            .overlay(
                VStack {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                    
                    Text("Video")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                }
            )
            .onTapGesture {
                showingPlayer = true
            }
            .sheet(isPresented: $showingPlayer) {
                if let url = attachment.downloadURL {
                    VideoPlayerView(url: url)
                }
            }
    }
}

struct DocumentPreviewView: View {
    let attachment: EmailAttachment
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: attachment.systemImageName)
                .font(.largeTitle)
                .foregroundColor(.blue)
                .frame(width: 60, height: 60)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.filename)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(attachment.mimeType)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(attachment.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onTap) {
                Image(systemName: "eye")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

struct VideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VideoPlayer(player: AVPlayer(url: url))
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("Done") {
                    dismiss()
                })
        }
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let attachment: EmailAttachment
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: QuickLookPreview
        
        init(_ parent: QuickLookPreview) {
            self.parent = parent
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return QuickLookItem(attachment: parent.attachment)
        }
        
        func previewControllerWillDismiss(_ controller: QLPreviewController) {
            parent.dismiss()
        }
    }
}

class QuickLookItem: NSObject, QLPreviewItem {
    let attachment: EmailAttachment
    
    init(attachment: EmailAttachment) {
        self.attachment = attachment
    }
    
    var previewItemURL: URL? {
        return attachment.downloadURL
    }
    
    var previewItemTitle: String? {
        return attachment.filename
    }
}

extension EmailAttachment {
    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }
    
    var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }
    
    var isPDF: Bool {
        mimeType == "application/pdf"
    }
    
    var isDocument: Bool {
        let documentTypes = [
            "application/pdf",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        ]
        return documentTypes.contains(mimeType)
    }
    
    var supportsQuickLook: Bool {
        return isImage || isVideo || isAudio || isPDF || isDocument
    }
}

#Preview {
    ScrollView {
        EmailMediaViewer(attachments: [
            EmailAttachment(
                id: "1",
                filename: "IMG_001.jpg",
                mimeType: "image/jpeg",
                size: 2048000,
                attachmentId: nil,
                downloadURL: URL(string: "https://picsum.photos/400/300")
            ),
            EmailAttachment(
                id: "2",
                filename: "presentation.pdf",
                mimeType: "application/pdf",
                size: 1024000,
                attachmentId: nil,
                downloadURL: nil
            ),
            EmailAttachment(
                id: "3",
                filename: "video_sample.mp4",
                mimeType: "video/mp4",
                size: 10240000,
                attachmentId: nil,
                downloadURL: URL(string: "https://www.w3schools.com/html/mov_bbb.mp4")
            )
        ])
        .padding()
    }
}