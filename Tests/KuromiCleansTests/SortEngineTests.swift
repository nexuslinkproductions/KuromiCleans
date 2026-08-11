import XCTest
@testable import KuromiCleans

final class SortEngineTests: XCTestCase {

    private var tmp: URL!
    private var fm: FileManager { FileManager.default }

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory
            .appendingPathComponent("KuromiCleansTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp {
            try? fm.removeItem(at: tmp)
        }
        tmp = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func makeFile(_ name: String, in dir: URL? = nil) throws -> URL {
        let url = (dir ?? tmp).appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    @discardableResult
    private func makeDir(_ name: String, in dir: URL? = nil) throws -> URL {
        let url = (dir ?? tmp).appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Sorted relative listing of everything under `root`, for before/after comparisons.
    private func listing(_ root: URL) -> [String] {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [String] = []
        for case let url as URL in enumerator {
            out.append(String(url.path.dropFirst(root.path.count)))
        }
        return out.sorted()
    }

    private func destSet(_ result: OrganizeResult) -> Set<String> {
        Set(result.moved.map { $0.to.path })
    }

    private func destNames(_ result: OrganizeResult) -> Set<String> {
        Set(result.moved.map { $0.to.lastPathComponent })
    }

    // MARK: - (a) Every category bucket

    func testCategoryForRepresentativeExtensions() {
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "pic.jpg")), "Images")
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "paper.pdf")), "Documents")
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "clip.mp4")), "Video")
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "song.mp3")), "Audio")
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "bundle.zip")), "Archives")
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "Tool.app")), "Applications")
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "main.swift")), "Code")
    }

    func testCategoryFullExtensionListMatchesBuckets() {
        for (category, extensions) in SortEngine.categoryExtensions {
            for ext in extensions {
                let url = URL(fileURLWithPath: "sample.\(ext)")
                XCTAssertEqual(SortEngine.category(for: url), category, "extension \(ext) should be \(category)")
            }
        }
    }

    func testEveryCategoryBucketOrganizesIntoRightSubfolder() throws {
        try makeFile("pic.jpg")
        try makeFile("paper.pdf")
        try makeFile("clip.mp4")
        try makeFile("song.mp3")
        try makeFile("bundle.zip")
        try makeFile("Tool.app")
        try makeFile("main.swift")
        try makeFile("mystery.xyz")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 8)
        let dests = destSet(result)
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Images/pic.jpg").path))
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Documents/paper.pdf").path))
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Video/clip.mp4").path))
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Audio/song.mp3").path))
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Archives/bundle.zip").path))
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Applications/Tool.app").path))
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Code/main.swift").path))
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Other/mystery.xyz").path))

        for (_, to) in result.moved {
            XCTAssertTrue(fm.fileExists(atPath: to.path), "destination should exist: \(to.path)")
        }
    }

    // MARK: - (b) Uppercase extensions

    func testCategoryForIsCaseInsensitive() {
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "PHOTO.JPG")), "Images")
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "REPORT.PDF")), "Documents")
        XCTAssertEqual(SortEngine.category(for: URL(fileURLWithPath: "CLIP.MP4")), "Video")
    }

    func testUppercaseExtensionsOrganizeIdentically() throws {
        try makeFile("PHOTO.JPG")
        try makeFile("REPORT.PDF")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 2)
        let dests = destSet(result)
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Images/PHOTO.JPG").path))
        XCTAssertTrue(dests.contains(tmp.appendingPathComponent("Documents/REPORT.PDF").path))
    }

    // MARK: - (c) No extension and unknown extension go to Other

    func testNoExtensionAndUnknownExtensionGoToOther() throws {
        try makeFile("README")
        try makeFile("notes")
        try makeFile("blob.zzz")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 3)
        for (_, to) in result.moved {
            XCTAssertEqual(to.deletingLastPathComponent().lastPathComponent, "Other")
        }
        XCTAssertTrue(destSet(result).contains(tmp.appendingPathComponent("Other/README").path))
        XCTAssertTrue(destSet(result).contains(tmp.appendingPathComponent("Other/notes").path))
        XCTAssertTrue(destSet(result).contains(tmp.appendingPathComponent("Other/blob.zzz").path))
    }

    // MARK: - (d) Collision resolution

    func testCollisionTwoIdenticalNames() throws {
        try makeFile("report.pdf")
        try makeFile("report.pdf")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 2)
        XCTAssertEqual(destNames(result), ["report.pdf", "report 2.pdf"])
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("Documents/report.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("Documents/report 2.pdf").path))
    }

    func testCollisionThreeIdenticalNames() throws {
        let dir = fm.temporaryDirectory.appendingPathComponent("KuromiCleansTests3-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try makeFile("report.pdf", in: dir)
        try makeFile("report.pdf", in: dir)
        try makeFile("report.pdf", in: dir)

        let result = SortEngine.organize(directory: dir)

        XCTAssertEqual(result.moved.count, 3)
        XCTAssertEqual(destNames(result), ["report.pdf", "report 2.pdf", "report 3.pdf"])
    }

    func testCollisionWithNoExtension() throws {
        try makeFile("README")
        try makeFile("README")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 2)
        XCTAssertEqual(destNames(result), ["README", "README 2"])
    }

    // MARK: - (e) Dotfiles stay untouched

    func testDotfilesStayUntouched() throws {
        try makeFile(".DS_Store")
        try makeFile(".hidden")
        try makeFile("pic.jpg")
        let before = listing(tmp)

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent(".DS_Store").path))
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent(".hidden").path))
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("Images/pic.jpg").path))
        XCTAssertEqual(Set(result.skipped.map { $0.lastPathComponent }), [".DS_Store", ".hidden"])
        // The only change is the new Images folder plus the moved file.
        XCTAssertEqual(listing(tmp).filter { $0.hasPrefix("/Images") }.count, 1)
        XCTAssertEqual(before.filter { $0.hasPrefix("/.") }, listing(tmp).filter { $0.hasPrefix("/.") })
    }

    // MARK: - (f) Existing category folders and their contents are untouched

    func testExistingCategoryFoldersUntouched() throws {
        let images = try makeDir("Images")
        try makeFile("keep.png", in: images)
        try makeFile("new.jpg")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 1)
        XCTAssertTrue(destSet(result).contains(tmp.appendingPathComponent("Images/new.jpg").path))
        XCTAssertTrue(fm.fileExists(atPath: images.appendingPathComponent("keep.png").path))
        XCTAssertTrue(fm.fileExists(atPath: images.appendingPathComponent("new.jpg").path))
        XCTAssertEqual(result.skipped.map { $0.lastPathComponent }, ["Images"])
    }

    func testOnlyNeededCategoryFoldersAreCreated() throws {
        try makeFile("song.mp3")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("Audio").path))
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("Images").path))
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("Other").path))
    }

    // MARK: - (g) Subdirectories are never recursed into

    func testSubdirectoriesNeverRecursed() throws {
        let sub = try makeDir("MyStuff")
        try makeFile("nested.txt", in: sub)
        try makeFile("top.pdf")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 1)
        XCTAssertTrue(destSet(result).contains(tmp.appendingPathComponent("Documents/top.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: sub.appendingPathComponent("nested.txt").path))
        XCTAssertTrue(result.skipped.contains(sub))
        XCTAssertFalse(result.moved.contains { $0.from.path.contains("MyStuff") })
    }

    // MARK: - (h) Empty directory is a no-op

    func testEmptyDirectoryIsNoOp() {
        let result = SortEngine.organize(directory: tmp)

        XCTAssertTrue(result.moved.isEmpty)
        XCTAssertTrue(result.skipped.isEmpty)
        XCTAssertEqual(listing(tmp), [])
    }

    // MARK: - (i) Dry run leaves the directory completely unchanged

    func testDryRunLeavesDirectoryUnchanged() throws {
        try makeFile("a.jpg")
        try makeFile("b.jpg")
        try makeFile("report.pdf")
        try makeFile("report.pdf")
        try makeFile("data.csv")
        try makeFile(".DS_Store")
        try makeDir("Stuff")
        let before = listing(tmp)

        let plan = SortEngine.organize(directory: tmp, dryRun: true)

        XCTAssertEqual(plan.moved.count, 5)
        XCTAssertEqual(listing(tmp), before, "dry run must not touch the filesystem")

        // The plan must match what a real run does, collisions included.
        let real = SortEngine.organize(directory: tmp)
        XCTAssertEqual(real.moved.count, plan.moved.count)
        XCTAssertEqual(destSet(real), destSet(plan))
        XCTAssertEqual(destNames(real), destNames(plan))
    }

    // MARK: - (j) Destinations stay inside the target directory

    func testDestinationsStayInsideTargetDryRun() throws {
        try makeFile("a.jpg")
        try makeFile("b.pdf")
        try makeFile("c.mp3")
        try makeFile("d.zip")
        try makeFile("e.swift")

        let plan = SortEngine.organize(directory: tmp, dryRun: true)
        XCTAssertEqual(plan.moved.count, 5)

        let root = tmp.path + "/"
        for (_, to) in plan.moved {
            XCTAssertTrue(to.path.hasPrefix(root), "destination escaped target: \(to.path)")
            XCTAssertFalse(to.path.contains("/../"))
            XCTAssertEqual(to.deletingLastPathComponent().deletingLastPathComponent(), tmp)
        }
    }

    func testDestinationsStayInsideTargetRealRun() throws {
        try makeFile("a.jpg")
        try makeFile("b.pdf")

        let result = SortEngine.organize(directory: tmp)
        XCTAssertEqual(result.moved.count, 2)

        let root = tmp.path + "/"
        for (_, to) in result.moved {
            XCTAssertTrue(to.path.hasPrefix(root))
            XCTAssertFalse(to.path.contains("/../"))
        }
    }

    // MARK: - (k) Spaces and unicode filenames

    func testSpacesAndUnicodeFilenames() throws {
        try makeFile("vacation photo 2024.jpg")
        try makeFile("résumé final.pdf")
        try makeFile("日本語 ドキュメント.txt")

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 3)
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("Images/vacation photo 2024.jpg").path))
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("Documents/résumé final.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: tmp.appendingPathComponent("Documents/日本語 ドキュメント.txt").path))
    }

    // MARK: - (l) Skipped items are reported

    func testSkippedItemsAreReported() throws {
        try makeFile(".DS_Store")
        try makeFile("normal.jpg")
        let sub = try makeDir("SubDir")
        let link = tmp.appendingPathComponent("link.txt")
        try fm.createSymbolicLink(at: link, withDestinationURL: tmp.appendingPathComponent("normal.jpg"))

        let result = SortEngine.organize(directory: tmp)

        XCTAssertEqual(result.moved.count, 1)
        XCTAssertEqual(result.skipped.count, 3)
        XCTAssertTrue(result.skipped.contains(tmp.appendingPathComponent(".DS_Store")))
        XCTAssertTrue(result.skipped.contains(sub))
        XCTAssertTrue(result.skipped.contains(link))

        // Symlink is still there and still a symlink.
        let values = try link.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(values.isSymbolicLink, true)
        XCTAssertTrue(fm.fileExists(atPath: link.path))
    }
}
