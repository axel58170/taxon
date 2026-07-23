// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TaxonKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TaxonDomain", targets: ["TaxonDomain"]),
        .library(name: "WikidataProvider", targets: ["WikidataProvider"])
    ],
    targets: [
        .target(name: "TaxonDomain"),
        .target(name: "WikidataProvider", dependencies: ["TaxonDomain"]),
        .testTarget(name: "TaxonDomainTests", dependencies: ["TaxonDomain"]),
        .testTarget(
            name: "WikidataProviderTests",
            dependencies: ["WikidataProvider"],
            resources: [.process("Fixtures")]
        )
    ]
)
