// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MobileMapCache",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        // 🪶 Fluent driver for SQLite.
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.6.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // Calculations for tiling
        .package(url: "https://github.com/Mapboard/SwiftTileMatrix.git", branch: "main"),
        // Geometry management
        .package(url: "https://github.com/GEOSwift/GEOSwift.git", from: "10.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MobileMapCache",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "GEOSwift", package: "GEOSwift"),
                .product(name: "SwiftTileMatrix", package: "SwiftTileMatrix"),
            ],
            resources: [
              .copy("Schema/"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MobileMapCacheTests",
            dependencies: [
                .target(name: "MobileMapCache"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            resources: [
                .copy("Fixtures/Rockd-map-cache-v1.db"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
