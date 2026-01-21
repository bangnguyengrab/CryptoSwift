// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "CryptoSwift",
  platforms: [
    .macOS(.v10_13), .iOS(.v11), .tvOS(.v11), .watchOS(.v4)
  ],
  products: [
    .library(
      name: "CryptoSwift",
      targets: ["CryptoSwift"]
    )
  ],
  targets: [
    // Switch to Binary Target to enforce Library Evolution (LE) support
    .binaryTarget(
      name: "CryptoSwift",
      url: "https://github.com/bangnguyengrab/CryptoSwift/releases/download/1.7.4/CryptoSwift.xcframework.zip",
      checksum: "a5da3d870288ff97200020a61d4eafd798bf03c72ee823bbc186c2e5390a4b24"
    )
  ]
)
