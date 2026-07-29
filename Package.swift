// swift-tools-version:6.0
// Orbit — personal relationship memory.
// Module boundaries are load-bearing (see docs/BUILD.md §2):
//   - OrbitWrite is the ONLY target that may open a writable database connection
//     (INV-5); everything else reads. scripts/lint-writepath.sh enforces this in CI,
//     and SQL triggers enforce immutability (INV-1) beneath it.
//   - Only app-layer targets (in apps/) may import SwiftUI; this package is
//     platform-neutral and builds on Linux, which is what makes the invariant
//     suite runnable in any CI environment.
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // exported for the app layer's read-side queries (SQLValue/Row);
        // openWriter stays lint-fenced to OrbitWrite regardless (INV-5)
        .library(name: "OrbitSQLite", targets: ["OrbitSQLite"]),
        .library(name: "OrbitCore", targets: ["OrbitCore"]),
        .library(name: "OrbitStore", targets: ["OrbitStore"]),
        .library(name: "OrbitWrite", targets: ["OrbitWrite"]),
        .library(name: "OrbitPipeline", targets: ["OrbitPipeline"]),
        .library(name: "OrbitRecall", targets: ["OrbitRecall"]),
        .library(name: "OrbitSearch", targets: ["OrbitSearch"]),
        .executable(name: "orbit-evals", targets: ["OrbitEvals"]),
    ],
    targets: [
        // SQLite C interop. iOS ships libsqlite3; Ubuntu has libsqlite3-dev.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),

        // Thin, deliberate wrapper: connections (reader/writer split), statements,
        // migrations. No ORM — the schema is the product.
        .target(name: "OrbitSQLite", dependencies: ["CSQLite"]),

        // Pure domain: entity types, ops, lifecycle state machines. No DB import.
        .target(name: "OrbitCore"),

        // Schema DDL + triggers + read models + all read-side queries.
        .target(
            name: "OrbitStore",
            dependencies: ["OrbitSQLite", "OrbitCore"],
            resources: [.copy("Resources")]
        ),

        // The write funnel: ProposalResolutionService + UserEditService.
        // The only target that opens a writer connection.
        .target(name: "OrbitWrite", dependencies: ["OrbitStore"]),

        // Extraction seam (§7.9) + sync engine (extraction payload → proposals).
        .target(
            name: "OrbitPipeline",
            dependencies: ["OrbitCore", "OrbitStore", "OrbitWrite"],
            resources: [.copy("Resources")]
        ),

        // Brief assembly + ranking (DATA-MODEL §8). Read-only.
        .target(name: "OrbitRecall", dependencies: ["OrbitStore"]),

        // FTS + entity graph + fragment search. Read-only.
        .target(name: "OrbitSearch", dependencies: ["OrbitStore"]),

        // Eval harness CLI: goldens, contract matching, measurement reports (EVALS.md).
        .executableTarget(
            name: "OrbitEvals",
            dependencies: ["OrbitCore", "OrbitStore", "OrbitWrite", "OrbitPipeline", "OrbitRecall", "OrbitSearch"]
        ),

        // L0 invariant suite (INV-1..24) — runs against the real storage layer.
        .testTarget(
            name: "OrbitInvariantTests",
            dependencies: ["OrbitStore", "OrbitWrite", "OrbitCore"]
        ),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"]),
        .testTarget(
            name: "OrbitPipelineTests",
            dependencies: ["OrbitPipeline", "OrbitWrite"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "OrbitRecallTests", dependencies: ["OrbitRecall", "OrbitWrite"]),
        .testTarget(name: "OrbitSearchTests", dependencies: ["OrbitSearch", "OrbitWrite"]),
    ]
)
