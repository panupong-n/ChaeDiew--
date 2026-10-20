// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tenix-ChaeDiew",
    platforms: [.macOS(.v14)],
    targets: [
        // Licence key format and Ed25519 verification (Foundation + CryptoKit only). The app can check keys; only ChaeDiewKeygen can make them.
        .target(name: "ChaeDiewLicense", path: "Sources/ChaeDiewLicense"),
        .target(name: "ChaeDiewKit", dependencies: ["ChaeDiewLicense"], path: "Sources/ChaeDiewKit"),
        .executableTarget(name: "ChaeDiewKeygen", dependencies: ["ChaeDiewLicense"], path: "Sources/ChaeDiewKeygen"),
        .executableTarget(name: "ChaeDiew", dependencies: ["ChaeDiewKit"], path: "Sources/ChaeDiew"),
        // Self-checks runnable with only the Command Line Tools (no XCTest/Xcode): `swift run ChaeDiewChecks`
        .executableTarget(name: "ChaeDiewChecks", dependencies: ["ChaeDiewKit", "ChaeDiewLicense"], path: "Sources/ChaeDiewChecks"),
    ]
)
