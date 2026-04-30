# ORK-SWIFT-NEW

Production-oriented Swift source obfuscation for Xcode build pipelines.

The tool works on a copied source tree before `xcodebuild` runs, so the original
project stays unchanged. It is designed to be reusable across projects by
combining deterministic generated names with explicit exclude patterns.
When `--output` is used, common build/cache directories such as `.build`,
`.git`, `build`, `DerivedData`, and `tmp` are pruned from the copied tree.

See `Docs/Architecture.md` for component responsibilities and safety model.

## Features

- Deterministic output from a user-provided seed.
- Generic exclude rules for folders, paths, and glob-style generated files.
- Swift symlink targets are preserved so package target aliases keep working.
- Directories that use Swift access-controlled imports keep their file names to
  avoid compiler file-order sensitivity.
- Output copies prune common build caches to avoid stale SwiftPM module state.
- JSON manifest with every file and function rename.
- Library API for custom build systems.
- CLI for shell scripts and CI release pipelines.
- Xcode build wrapper example that runs against a temporary project copy.

## What It Obfuscates

- `.swift` file basenames.
- Conservative `private` and `fileprivate func` declarations.
- Local call sites that are safe to rewrite.

The function pass intentionally skips runtime-sensitive or ambiguous Swift:

- `@objc`, `@IBAction`, `@NSManaged`, `_cdecl`, `_silgen_name`,
  `_dynamicReplacement`.
- `public`, `open`, `dynamic`, `override`.
- Backticked names, special entry points, unsafe overloads.
- Function references that are not normal direct calls.
- Function names that appear in string literals or interpolation.
- Calls whose argument labels do not match the private overload being renamed.
- Same-name calls inside the function body, which may resolve to a different
  overload after type checking.

## Requirements

- macOS 13 or newer.
- Xcode command line tools.
- Swift 5.9 or newer.

## Build And Test

```bash
swift build -c release
swift test
```

## CLI Usage

Print help:

```bash
swift run -c release ork-swift-new -- --help
```

Run against a source directory:

```bash
swift run -c release ork-swift-new -- \
  --input /path/to/AppSources \
  --output /tmp/AppSources.obfuscated \
  --rename-files \
  --rename-private-functions \
  --exclude Security \
  --exclude "*.generated.swift" \
  --manifest /tmp/obfuscation-manifest.json \
  --seed "my-app-release"
```

Write changes directly into a temporary copied tree:

```bash
swift run -c release ork-swift-new -- \
  --input /tmp/MyAppCopy/MyApp \
  --in-place \
  --rename-files \
  --rename-private-functions \
  --manifest /tmp/ork-swift-new-manifest.json
```

## Xcode Build Wrapper

`Examples/build-obfuscated-xcode.sh` copies any Xcode project into a temporary
work directory, obfuscates the configured source folder in place inside that
copy, and then runs `xcodebuild`.

Example:

```bash
SCHEME_NAME=MyApp \
SOURCE_DIR=MyApp \
OBFUSCATION_EXCLUDES=$'Generated\nSecurity' \
./Examples/build-obfuscated-xcode.sh
```

Important environment variables:

- `SCHEME_NAME`: required Xcode scheme.
- `SOURCE_DIR`: source folder inside the copied project. Defaults to
  `SCHEME_NAME`.
- `WORKSPACE_PATH`: workspace path inside the project copy. Defaults to
  `${SCHEME_NAME}.xcworkspace`.
- `PROJECT_PATH`: fallback project path if no workspace is used.
- `OBFUSCATION_EXCLUDES`: newline-separated exclude patterns.
- `KEEP_OBFUSCATION_WORKDIR=1`: keep the temporary copy after the build.

## Exclude Patterns

Excludes are intentionally generic:

- `Security` skips any path component named `Security`.
- `Features/Generated` skips that directory prefix.
- `*.generated.swift` skips matching generated files by basename or relative
  path.

Default excludes:

```text
.build, .git, build, DerivedData, Pods, Package.swift, Package@swift-*.swift, main.swift, LinuxMain.swift, tmp, *.generated.swift
```

Use `--no-default-excludes` only when you want full control.

## Validation

The current safety model has been dry-run against large public Swift codebases,
including Signal-iOS, Firefox iOS, DuckDuckGo iOS, WordPress iOS, Nextcloud iOS,
Mastodon iOS, sourcekit-lsp, swift-docc, swift-format, swift-package-manager,
swift-protobuf, and swift-syntax. On that set, ORK-SWIFT-NEW scanned 15,251
Swift files, planned 11,203 file renames, planned 13,838 private function
renames, and emitted valid JSON manifests for every project.

Actual obfuscated SwiftPM builds have been verified for swift-protobuf,
swift-format, swift-syntax, swift-docc, sourcekit-lsp, and
swift-package-manager.

## Manifest

The manifest is a stable JSON audit trail for the release build:

```json
{
  "fileRenames": [
    {
      "from": "Feature/ProfileView.swift",
      "to": "Feature/S_123456789abc.swift"
    }
  ],
  "functionRenames": [
    {
      "file": "Feature/ProfileView.swift",
      "from": "renderAvatar",
      "to": "f_123456789abc"
    }
  ],
  "skippedFunctions": []
}
```

Keep the manifest as a private build artifact. It is useful for debugging
release-only issues, but it reverses part of the obfuscation mapping.

## Library API

```swift
import ORKSwiftNewCore

let result = try ORKSwiftNew().run(.init(
    inputPath: "/tmp/MyAppCopy/MyApp",
    outputPath: "/tmp/MyAppObfuscated",
    manifestPath: "/tmp/ork-swift-new-manifest.json",
    seed: "my-app-release",
    renameFiles: true,
    renamePrivateFunctions: true,
    excludePatterns: ["Generated", "Security"]
))

print(result.summary)
```

## Current Limits

ORK-SWIFT-NEW is intentionally source-conservative. It does not attempt full
semantic Swift refactoring and does not rename public APIs, types, properties,
assets, Objective-C selectors, storyboard references, or symbols exposed through
reflection/runtime hooks. A production pipeline should always run `xcodebuild`
after obfuscation and treat that build as the final validation gate.
