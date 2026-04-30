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
- `SourceTypeTransformer`: applies project-wide conservative type renames.
- `TypeRenamer`: token-level nominal type candidate analysis and replacement.
- `SourceFunctionTransformer`: applies source-level private function renames.
- `FunctionRenamer`: token-level function candidate analysis and replacement.
- `FunctionSignatureAnalyzer`: lightweight signature and call-label analysis used
  to reject ambiguous private function rewrites.
- `SwiftFileRenamer`: deterministic `.swift` file basename renames.
- `ManifestWriter`: serializes JSON output.
- `FileSystem`: filesystem helpers and Swift file discovery.
- `StableName`: deterministic generated name hashing.

## Safety Model

The tool avoids build-breaking rewrites by skipping cases that need full Swift
semantic knowledge. This is intentional:

- Runtime-facing declarations stay unchanged.
- Public/open/dynamic/override declarations stay unchanged.
- Exported and runtime-sensitive type declarations stay unchanged.
- Unsafe overload groups stay unchanged.
- Function references and ambiguous occurrences stay unchanged.
- Type declarations are skipped when the name appears in strings, has duplicate
  declarations, is exported, is nested, is used as a qualified external type,
  or appears in value-declaration positions.
- Private functions are skipped when call labels or same-name body calls suggest
  a type-checked overload could be selected.
- Directories using access-controlled imports keep source filenames to avoid
  Swift compiler file-order sensitivity.
- Generated and excluded paths are copied but not transformed.

The build wrapper should run this tool on a temporary project copy. Production
release pipelines should treat a successful `xcodebuild` after obfuscation as
the final safety gate.
