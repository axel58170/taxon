// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TaxonKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TaxonDomain", targets: ["TaxonDomain"])
    ],
    targets: [
        .target(name: "TaxonDomain"),
        .testTarget(name: "TaxonDomainTests", dependencies: ["TaxonDomain"])
    ]
)
