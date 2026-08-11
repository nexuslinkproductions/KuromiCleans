import Foundation

/// The outcome of a sort pass.
public struct OrganizeResult {
    public var moved: [(from: URL, to: URL)]
    public var skipped: [URL]

    public init(moved: [(from: URL, to: URL)] = [], skipped: [URL] = []) {
        self.moved = moved
        self.skipped = skipped
    }
}

/// Pure Foundation sorting logic. No AppKit here, so tests can link it directly.
public enum SortEngine {

    /// Extension (lowercase, no dot) to category mapping.
    public static let categoryExtensions: [String: [String]] = [
        "Images": ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "svg", "tiff", "tif", "bmp", "raw", "cr2", "nef", "psd", "ai", "eps"],
        "Documents": ["pdf", "doc", "docx", "txt", "md", "rtf", "odt", "xls", "xlsx", "ppt", "pptx", "csv", "pages", "numbers", "key", "epub", "mobi"],
        "Video": ["mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv", "flv", "ts"],
        "Audio": ["mp3", "wav", "aac", "flac", "m4a", "ogg", "aiff", "wma", "opus"],
        "Archives": ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "pkg", "iso", "cab"],
        "Applications": ["app"],
        "Code": ["swift", "py", "js", "ts", "jsx", "tsx", "html", "css", "json", "yaml", "yml", "xml", "sh", "bash", "rb", "go", "rs", "java", "c", "cpp", "h", "hpp", "ipynb", "sql", "toml"]
    ]

    /// The category a file belongs to, based on its extension. Case-insensitive.
    /// Files with no extension, or with an unknown extension, land in "Other".
    public static func category(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return "Other" }
        for (category, extensions) in categoryExtensions {
            if extensions.contains(ext) {
                return category
            }
        }
        return "Other"
    }

    /// Sorts the DIRECT children of `directory` into category subfolders.
    ///
    /// Rules:
    /// - Only direct children are considered (no recursion).
    /// - Only regular files move. Directories and symlinks are skipped.
    /// - Dotfiles (names starting with ".") are skipped.
    /// - Files already inside category subfolders are never touched.
    /// - A category subfolder is created only when a matching file actually moves.
    /// - Name collisions get " 2", " 3" appended before the extension.
    /// - `dryRun` computes the full plan (including collision resolution) without
    ///   touching the filesystem.
    public static func organize(directory: URL, dryRun: Bool = false) -> OrganizeResult {
        let fm = FileManager.default
        var moved: [(from: URL, to: URL)] = []
        var skipped: [URL] = []

        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return OrganizeResult()
        }

        // Per-category set of names already taken, seeded from any existing
        // category folder, so dry runs and real runs agree exactly.
        var occupied: [String: Set<String>] = [:]

        for item in items {
            let name = item.lastPathComponent

            guard !name.hasPrefix(".") else {
                skipped.append(item)
                continue
            }

            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true || values?.isRegularFile != true {
                skipped.append(item)
                continue
            }

            let categoryName = category(for: item)
            let categoryDir = directory.appendingPathComponent(categoryName)

            var taken = occupied[categoryName] ?? []
            if occupied[categoryName] == nil,
               let existing = try? fm.contentsOfDirectory(atPath: categoryDir.path) {
                taken.formUnion(existing)
            }

            let destination = uniqueDestination(in: categoryDir, baseName: name, taken: &taken)
            occupied[categoryName] = taken
            moved.append((from: item, to: destination))
        }

        if !dryRun {
            for (from, to) in moved {
                do {
                    try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: from, to: to)
                } catch {
                    // Leave the file in place. Nothing else to do for a tiny utility.
                }
            }
        }

        return OrganizeResult(moved: moved, skipped: skipped)
    }

    /// Picks a destination name inside `dir` that is not in `taken`, appending
    /// " 2", " 3", ... before the extension on collision ("report.pdf" becomes
    /// "report 2.pdf"). Mutates `taken` with the chosen name.
    private static func uniqueDestination(in dir: URL, baseName: String, taken: inout Set<String>) -> URL {
        let ns = baseName as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var candidate = baseName
        var counter = 2
        while taken.contains(candidate) {
            candidate = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            counter += 1
        }
        taken.insert(candidate)
        return dir.appendingPathComponent(candidate)
    }
}
