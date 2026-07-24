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
        .library(name: "TaxonSettings", targets: ["TaxonSettings"]),
        .library(name: "CatalogueOfLifeProvider", targets: ["CatalogueOfLifeProvider"]),
        .library(name: "WikidataProvider", targets: ["WikidataProvider"])
    ],
    targets: [
        .target(name: "TaxonDomain"),
        .target(name: "TaxonSettings", dependencies: ["TaxonDomain"]),
        .target(name: "CatalogueOfLifeProvider", dependencies: ["TaxonDomain"]),
        .target(name: "WikidataProvider", dependencies: ["TaxonDomain"]),
        .testTarget(name: "TaxonDomainTests", dependencies: ["TaxonDomain"]),
        .testTarget(name: "TaxonSettingsTests", dependencies: ["TaxonSettings"]),
        .testTarget(
            name: "CatalogueOfLifeProviderTests",
            dependencies: ["CatalogueOfLifeProvider"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "WikidataProviderTests",
            dependencies: ["WikidataProvider"],
            resources: [.process("Fixtures")]
        )
    ]
)
