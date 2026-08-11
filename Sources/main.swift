import AppKit
import Foundation

// KuromiCleans: sort ~/Downloads into category subfolders, show one alert, quit.
//
// Flags:
//   --dry-run    print the plan as text, move nothing
//   --path <dir> override the target directory (default: real Downloads)
//   --version    print version and exit
//   --dump       emit a machine-readable JSON report of the run (works with or without --dry-run)
//   --check      verify folder state with HEALTH codes, never move anything
//   --no-alert   skip the completion alert (automation)

let arguments = CommandLine.arguments
var dryRun = false
var dump = false
var check = false
var noAlert = false
var targetPath: String?

var index = 1
while index < arguments.count {
    switch arguments[index] {
    case "--dry-run":
        dryRun = true
    case "--dump":
        dump = true
    case "--check":
        check = true
    case "--no-alert":
        noAlert = true
    case "--path":
        index += 1
        if index < arguments.count {
            targetPath = arguments[index]
        }
    case "--version":
        print("1.0.0")
        exit(0)
    default:
        break
    }
    index += 1
}

let target: URL
if let targetPath {
    target = URL(fileURLWithPath: targetPath)
} else {
    target = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
}

guard FileManager.default.fileExists(atPath: target.path) else {
    FileHandle.standardError.write(Data("Target directory does not exist: \(target.path)\n".utf8))
    exit(1)
}

// ---- diagnostics mode: health check, never sorts ----
if check {
    exit(runHealthCheck(target))
}

// ---- the sort ----
let fm = FileManager.default
let start = Date()
let result = SortEngine.organize(directory: target, dryRun: dryRun)
let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

// Real-run failure detection: source still present while destination is missing.
var errors: [ErrorEntry] = []
if !dryRun {
    for (from, to) in result.moved {
        if !fm.fileExists(atPath: to.path) && fm.fileExists(atPath: from.path) {
            errors.append(ErrorEntry(from: from.path, reason: "move failed"))
        }
    }
}

// Bytes moved: size of the destination (real run) or the source (dry run).
var bytesMoved = 0
for (from, to) in result.moved {
    let probe = dryRun ? from : to
    let size = (try? probe.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    bytesMoved += size
}

var byCategory: [String: Int] = [:]
for (from, _) in result.moved {
    let category = SortEngine.category(for: from)
    byCategory[category, default: 0] += 1
}

// ---- diagnostics mode: JSON report ----
if dump {
    let report = DumpReport(
        target: target.path,
        dryRun: dryRun,
        elapsedMs: elapsedMs,
        summary: Summary(
            moved: result.moved.count,
            skipped: result.skipped.count,
            errors: errors.count,
            bytesMoved: bytesMoved
        ),
        byCategory: byCategory,
        moved: result.moved.map {
            MoveEntry(
                from: $0.from.path,
                to: $0.to.path,
                category: SortEngine.category(for: $0.from),
                renamed: $0.from.lastPathComponent != $0.to.lastPathComponent
            )
        },
        skipped: result.skipped.map { SkipEntry(path: $0.path, reason: skipReason($0)) },
        errors: errors
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(report) {
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
    exit(dryRun || errors.isEmpty ? 0 : 1)
}

// ---- interactive dry-run plan (text) ----
if dryRun {
    print("Target: \(target.path)")
    for (from, to) in result.moved {
        let relative = String(to.path.dropFirst(target.path.count + 1))
        print("\(from.lastPathComponent) -> \(relative)")
    }
    for item in result.skipped {
        print("skip: \(item.lastPathComponent)")
    }
    print("Summary: \(result.moved.count) file(s) to move, \(result.skipped.count) skipped.")
    exit(0)
}

// ---- real run, double-click path ----
if !noAlert {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let alert = NSAlert()
    alert.messageText = "Downloads sorted. Moved \(result.moved.count) files."
    alert.informativeText = "Everything is tucked into tidy subfolders."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}
exit(errors.isEmpty ? 0 : 1)

// MARK: - Diagnostics helpers

func skipReason(_ url: URL) -> String {
    if url.lastPathComponent.hasPrefix(".") { return "dotfile" }
    let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
    if values?.isSymbolicLink == true { return "symlink" }
    return "directory"
}

/// Validates the state of a folder without touching it. Prints HEALTH lines.
/// Exit code 0 = all checks OK, 1 = issues found.
func runHealthCheck(_ target: URL) -> Int32 {
    let fm = FileManager.default
    var issues: [String] = []

    // root_clean: no loose regular non-dotfile files directly in the target.
    if let items = try? fm.contentsOfDirectory(at: target, includingPropertiesForKeys: [.isRegularFileKey]) {
        for item in items {
            let name = item.lastPathComponent
            if name.hasPrefix(".") { continue }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                issues.append("loose file: \(name)")
            }
        }
    }
    print(issues.isEmpty
        ? "HEALTH OK root_clean"
        : "HEALTH FAIL root_clean \(issues.joined(separator: ", "))")

    // category_match: every file inside a category folder matches that category.
    var mismatch: [String] = []
    let categories = Set(SortEngine.categoryExtensions.keys).union(["Other"])
    let entries = (try? fm.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)) ?? []
    for entry in entries where categories.contains(entry.lastPathComponent) {
        guard let enumerator = fm.enumerator(at: entry, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile != true { continue }
            if SortEngine.category(for: url) != entry.lastPathComponent {
                mismatch.append("\(entry.lastPathComponent)/\(name)")
            }
        }
    }
    print(mismatch.isEmpty
        ? "HEALTH OK category_match"
        : "HEALTH FAIL category_match \(mismatch.joined(separator: ", "))")

    // Summary line with the actual file count found in category folders.
    var files = 0
    for entry in entries where categories.contains(entry.lastPathComponent) {
        guard let enumerator = fm.enumerator(at: entry, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true { files += 1 }
        }
    }
    print("HEALTH summary target=\(target.path) files=\(files) categories=\(categories.count)")

    return issues.isEmpty && mismatch.isEmpty ? 0 : 1
}

// MARK: - Report types

struct DumpReport: Codable {
    var app: String
    var version: String
    var target: String
    var dryRun: Bool
    var elapsedMs: Int
    var summary: Summary
    var byCategory: [String: Int]
    var moved: [MoveEntry]
    var skipped: [SkipEntry]
    var errors: [ErrorEntry]

    init(target: String, dryRun: Bool, elapsedMs: Int, summary: Summary, byCategory: [String: Int], moved: [MoveEntry], skipped: [SkipEntry], errors: [ErrorEntry]) {
        self.app = "KuromiCleans"
        self.version = "1.0.0"
        self.target = target
        self.dryRun = dryRun
        self.elapsedMs = elapsedMs
        self.summary = summary
        self.byCategory = byCategory
        self.moved = moved
        self.skipped = skipped
        self.errors = errors
    }
}

struct Summary: Codable {
    var moved: Int
    var skipped: Int
    var errors: Int
    var bytesMoved: Int
}

struct MoveEntry: Codable {
    var from: String
    var to: String
    var category: String
    var renamed: Bool
}

struct SkipEntry: Codable {
    var path: String
    var reason: String
}

struct ErrorEntry: Codable {
    var from: String
    var reason: String
}
