import AppKit
import Foundation

// KuromiCleans: sort ~/Downloads into category subfolders, show one alert, quit.

let arguments = CommandLine.arguments
var dryRun = false
var targetPath: String?

var index = 1
while index < arguments.count {
    switch arguments[index] {
    case "--dry-run":
        dryRun = true
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

if dryRun {
    let result = SortEngine.organize(directory: target, dryRun: true)
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

let result = SortEngine.organize(directory: target, dryRun: false)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let alert = NSAlert()
alert.messageText = "Downloads sorted. Moved \(result.moved.count) files."
alert.informativeText = "Everything is tucked into tidy subfolders."
alert.alertStyle = .informational
alert.addButton(withTitle: "OK")
NSApp.activate(ignoringOtherApps: true)
alert.runModal()

exit(0)
