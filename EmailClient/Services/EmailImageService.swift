import SwiftUI
import UIKit
import GoogleSignIn

class EmailImageService: ObservableObject {
    private let cache = NSCache<NSString, UIImage>()
    private let baseURL = "https://www.googleapis.com/gmail/v1"
    
    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024
    }
    
    func loadImage(attachmentId: String, messageId: String, user: GIDGoogleUser) async -> UIImage? {
        let cacheKey = "\(messageId)_\(attachmentId)" as NSString
        
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        guard let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)/attachments/\(attachmentId)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(user.accessToken.tokenString)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let attachmentData = try JSONDecoder().decode(GmailAttachmentData.self, from: data)
            
            guard let attachmentBytes = decodeBase64URLSafe(attachmentData.data),
                  let image = UIImage(data: attachmentBytes) else {
                return nil
            }
            
            cache.setObject(image, forKey: cacheKey, cost: attachmentBytes.count)
            return image
            
        } catch {
            print("Failed to load image attachment: \(error)")
            return nil
        }
    }
    
    private func decodeBase64URLSafe(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let padding = 4 - base64.count % 4
        if padding != 4 {
            base64 += String(repeating: "=", count: padding)
        }
        
        return Data(base64Encoded: base64)
    }
}

struct GmailAttachmentData: Codable {
    let size: Int
    let data: String
}

struct AsyncEmailImage: View {
    let attachmentId: String
    let messageId: String
    let user: GIDGoogleUser?
    
    @StateObject private var imageService = EmailImageService()
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var showingFullScreen = false
    
    var body: some View {
        Group {
            if isLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
                    .frame(maxHeight: 200)
            } else if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
                    .onTapGesture {
                        showingFullScreen = true
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .overlay(
                        VStack {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text("Image unavailable")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
                    .frame(height: 120)
            }
        }
        .onAppear {
            loadImage()
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            if let image = image {
                FullScreenImageView(image: image)
            }
        }
    }
    
    private func loadImage() {
        guard let user = user else {
            isLoading = false
            return
        }
        
        Task {
            let loadedImage = await imageService.loadImage(
                attachmentId: attachmentId,
                messageId: messageId,
                user: user
            )
            
            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 0.5), 5.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if scale > 1.0 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.0
                            }
                        }
                    }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}