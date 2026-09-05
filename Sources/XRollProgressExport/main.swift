import Foundation
import XRollCore

func printUsage() {
    print("Uso: swift run xroll-export-progress <archivo.csv|archivo.json> [--exercise ID] [--minimum-score 0...100]")
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let path = arguments.first, !path.hasPrefix("-") else { printUsage(); exit(2) }
var filter = ProgressFilter()
var index = 1
while index < arguments.count {
    switch arguments[index] {
    case "--exercise" where index + 1 < arguments.count:
        filter.exerciseID = arguments[index + 1]; index += 2
    case "--minimum-score" where index + 1 < arguments.count:
        filter.minimumScore = Double(arguments[index + 1]); index += 2
    default:
        printUsage(); exit(2)
    }
}

let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let database = appSupport.appendingPathComponent("xRoll/progress.sqlite")
let output = URL(fileURLWithPath: path).standardizedFileURL
do {
    let store = try ProgressStore(url: database)
    switch output.pathExtension.lowercased() {
    case "csv": try store.exportCSV(to: output, filter: filter)
    case "json": try store.exportJSON(to: output, filter: filter)
    default: print("El archivo debe terminar en .csv o .json."); exit(2)
    }
    print("Progreso exportado en \(output.path)")
} catch {
    fputs("No se pudo exportar: \(error.localizedDescription)\n", stderr)
    exit(1)
}
