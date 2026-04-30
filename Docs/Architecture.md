# Architecture

ORK-SWIFT-NEW is split into a reusable core library and a thin command
line target.

## Targets

- `ORKSwiftNewCore`: file discovery, path filtering, source
  transformation, file renaming, manifest creation, and public API models.
- `ORKSwiftNewCLI`: argument parsing, process exit behavior, and
  console reporting.

## Core Components

- `ORKSwiftNew`: validates options and orchestrates the pipeline.
- `PathFilter`: applies generic include/exclude policy.
- `SourceFunctionTransformer`: applies source-level private function renames.
- `FunctionRenamer`: token-level function candidate analysis and replacement.
- `SwiftFileRenamer`: deterministic `.swift` file basename renames.
- `ManifestWriter`: serializes JSON output.
- `FileSystem`: filesystem helpers and Swift file discovery.
- `StableName`: deterministic generated name hashing.

## Safety Model

The tool avoids build-breaking rewrites by skipping cases that need full Swift
semantic knowledge. This is intentional:

- Runtime-facing declarations stay unchanged.
- Public/open/dynamic/override declarations stay unchanged.
- Unsafe overload groups stay unchanged.
- Function references and ambiguous occurrences stay unchanged.
- Generated and excluded paths are copied but not transformed.

The build wrapper should run this tool on a temporary project copy. Production
release pipelines should treat a successful `xcodebuild` after obfuscation as
the final safety gate.
