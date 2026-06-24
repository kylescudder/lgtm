// swift-tools-version: 6.0
import PackageDescription

// Push backend: receives Azure DevOps service-hook webhooks and sends APNs.
// Reuses LGTMKit for the shared webhook model + reviewer-selection logic.
let package = Package(
    name: "LGTMBackend",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/vapor/apns.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "5.0.0"),
        .package(path: "../Packages/LGTMKit")
    ],
    targets: [
        .executableTarget(
            name: "LGTMBackend",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "VaporAPNS", package: "apns"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "LGTMKit", package: "LGTMKit")
            ]
        )
    ]
)
