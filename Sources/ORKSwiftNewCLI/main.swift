import Foundation
import ORKSwiftNewCore

do {
    let options = try ArgumentParser().parse(CommandLine.arguments)
    let result = try ORKSwiftNew().run(options.makeCoreOptions())
    ConsoleReporter().printResult(result, options: options)
} catch let error as CLIError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch let error as ORKSwiftNewError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("ORK-SWIFT-NEW error: \(error)\n", stderr)
    exit(1)
}
