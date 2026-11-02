// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OBD2Kit",
    platforms: [.iOS("18.4")],
    products: [
        .library(
            name: "OBD2Kit",
            targets: ["OBD2Kit"]
        ),
    ],
    targets: [
        .target(
            name: "OBD2Kit",
            path: "Sources/OBD2Kit"
        ),
    ]
)
