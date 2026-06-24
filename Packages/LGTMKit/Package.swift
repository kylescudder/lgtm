// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Command Line Tools ship Swift Testing as a framework outside the default
// import/link paths, and its interop dylib lives in yet another directory.
// Resolve both from the active developer dir (DEVELOPER_DIR if set, else CLT default).
let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Library/Developer/CommandLineTools"
// Holds Testing.framework.
let commandLineToolsFrameworksPath = developerDir + "/Library/Developer/Frameworks"
// Holds lib_TestingInterop.dylib (a dependency of Testing.framework).
let commandLineToolsTestingLibPath = developerDir + "/Library/Developer/usr/lib"

let package = Package(
    name: "LGTMKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "LGTMKit", targets: ["LGTMKit"])
    ],
    targets: [
        .target(
            name: "LGTMKit"
        ),
        // A dependency-free runtime check usable on Command Line Tools (no XCTest
        // / Swift Testing needed): `swift run DevVerify`. Mirrors the unit tests.
        .executableTarget(
            name: "DevVerify",
            dependencies: ["LGTMKit"]
        ),
        .testTarget(
            name: "LGTMKitTests",
            dependencies: ["LGTMKit"],
            // Command Line Tools ship Swift Testing as a framework outside the
            // default import path. These flags locate it; they are harmless (and
            // redundant) when the package is opened in full Xcode.
            swiftSettings: [
                .unsafeFlags(["-F", commandLineToolsFrameworksPath])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", commandLineToolsFrameworksPath,
                    "-Xlinker", "-rpath", "-Xlinker", commandLineToolsFrameworksPath,
                    "-Xlinker", "-rpath", "-Xlinker", commandLineToolsTestingLibPath
                ])
            ]
        )
    ]
)
