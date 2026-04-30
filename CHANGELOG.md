# Changelog

## 0.1.0

- Initial Swift Package release.
- Adds deterministic Swift file basename obfuscation.
- Adds conservative private/fileprivate function renaming.
- Adds JSON manifest output and generic path excludes.
- Adds a reusable Xcode build wrapper example.
- Preserves SwiftPM `Package.swift` manifests by default.
- Preserves SwiftPM executable/test entrypoint files by default.
- Skips function renames when the identifier appears in a string literal.
- Preserves Swift files targeted by symlinks to avoid broken package aliases.
- Prunes common build/cache folders when creating an output copy.
