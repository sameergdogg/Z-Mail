// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EmailClient",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "EmailClient",
            targets: ["EmailClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "7.0.0"),
        .package(url: "https://github.com/googleapis/google-api-swift-client", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "EmailClient",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GoogleAPIClientForREST", package: "google-api-swift-client")
            ]
        )
    ]
)