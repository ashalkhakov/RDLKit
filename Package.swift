// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "PicaKit",
  platforms: [.macOS(.v12)],
  products: [
    .library(name: "PicaKit", targets: ["PicaKit"]),
  ],
  targets: [
    .target(
      name: "PicaKit",
      path: "PicaKit",
      exclude: ["GNUmakefile", "README.md"],
      publicHeadersPath: ".",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Foundation"),
      ]
    ),
    .testTarget(
      name: "PicaKitTests",
      dependencies: ["PicaKit"],
      path: "PicaKitTests",
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
