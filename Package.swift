// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "RDLKit",
  platforms: [.macOS(.v12)],
  products: [
    .library(name: "RDLKit", targets: ["RDLKit"]),
  ],
  targets: [
    .target(
      name: "RDLKit",
      path: "RDLKit",
      exclude: ["GNUmakefile", "README.md"],
      publicHeadersPath: ".",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Foundation"),
      ]
    ),
    .testTarget(
      name: "RDLKitTests",
      dependencies: ["RDLKit"],
      path: "RDLKitTests",
      exclude: ["README.md", "Info.plist"],
      cSettings: [
        .headerSearchPath("."),
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
      ]
    ),
  ]
)
