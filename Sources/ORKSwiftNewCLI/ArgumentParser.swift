import Foundation
import ORKSwiftNewCore

struct ArgumentParser {
    func parse(_ args: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 1

        func requireValue(for flag: String) throws -> String {
            let valueIndex = index + 1
            guard valueIndex < args.count else {
                throw CLIError.missingValue("Missing value for \(flag)")
            }
            index = valueIndex
            return args[valueIndex]
        }

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--":
                break
            case "--input":
                options.inputPath = try requireValue(for: arg)
            case "--output":
                options.outputPath = try requireValue(for: arg)
            case "--manifest":
                options.manifestPath = try requireValue(for: arg)
            case "--seed":
                options.seed = try requireValue(for: arg)
            case "--exclude":
                options.excludePatterns.append(try requireValue(for: arg))
            case "--no-default-excludes":
                options.useDefaultExcludes = false
            case "--in-place":
                options.inPlace = true
            case "--dry-run":
                options.dryRun = true
            case "--rename-files":
                options.renameFiles = true
            case "--rename-directories":
                options.renameDirectories = true
            case "--rename-private-functions":
                options.renamePrivateFunctions = true
            case "--rename-types":
                options.renameTypes = true
            case "--quiet":
                options.quiet = true
            case "--verbose":
                options.verbose = true
            case "--version":
                print("ork-swift-new \(version)")
                exit(0)
            case "--help", "-h":
                print(usage())
                exit(0)
            default:
                throw CLIError.usage("Unknown option: \(arg)\n\n\(usage())")
            }
            index += 1
        }

        guard options.inputPath != nil else {
            throw CLIError.usage("Missing --input\n\n\(usage())")
        }

        return options
    }

    func usage() -> String {
        """
        Usage:
          ork-swift-new --input <Swift source dir> (--output <dir> | --in-place | --dry-run) [options]

        Options:
          --rename-files               Rename .swift file basenames in the working source tree.
          --rename-directories         Rename Swift-only source directories in the working source tree.
          --rename-private-functions   Rename safe private/fileprivate Swift function declarations and local call sites.
          --rename-types               Rename safe internal/private Swift struct/class/enum/actor names and references.
          --exclude <pattern>          Skip matching files/directories. Repeat for multiple paths.
                                       Plain names match any path component; glob patterns match relative paths.
          --no-default-excludes        Disable built-in excludes: \(defaultExcludePatterns.joined(separator: ", ")).
          --manifest <path|- >         Write JSON rename manifest. Use '-' for stdout.
          --seed <value>               Deterministic seed used for generated names.
          --dry-run                    Scan and report without writing files.
          --in-place                   Rewrite the input source tree directly.
          --quiet                      Suppress summary output.
          --verbose                    Print skipped function details.
          --version                    Print version.
          --help                       Print this help.

        Safety:
          Function and type renaming are intentionally conservative. Runtime-sensitive
          declarations such as @objc, dynamic, override, public/open APIs, unsafe
          overloads, function references, and suspicious string interpolation usages
          are skipped.
        """
    }
}
