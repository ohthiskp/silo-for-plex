// swift-tools-version:5.10

import PackageDescription

// AstraKit: the Plex client and models for the native Astra apps.
// It has no UI and no mpv dependency, so it builds and tests with plain `swift test`.
let package = Package(
  name: "AstraKit",
  platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
  products: [
    .library(name: "AstraKit", targets: ["AstraKit"])
  ],
  targets: [
    .target(name: "AstraKit"),
    .testTarget(name: "AstraKitTests", dependencies: ["AstraKit"]),
  ]
)
