import Foundation

// KuromiCleans verification harness. Plain Swift, no XCTest, no SwiftPM.
// Compile: swiftc -O Sources/SortEngine.swift Tests/main.swift -o .build/run_tests
// Exit code 0 = all checks pass.

let fm = FileManager.default
var passed = 0
var failed = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        passed += 1
        print("PASS  \(name)")
    } else {
        failed += 1
        print("FAIL  \(name)  \(detail)")
    }
}

func makeDir(_ url: URL) {
    try! fm.createDirectory(at: url, withIntermediateDirectories: true)
}

func makeFile(_ url: URL, _ content: String = "x") {
    fm.createFile(atPath: url.path, contents: Data(content.utf8))
}

func makeSymlink(_ link: URL, to target: URL) {
    try! fm.createSymbolicLink(at: link, withDestinationURL: target)
}

func exists(_ root: URL, _ relative: String) -> Bool {
    fm.fileExists(atPath: root.appendingPathComponent(relative).path)
}

func relativePaths(_ root: URL) -> Set<String> {
    // Pure string-path walk. Immune to /var vs /private/var canonicalization
    // differences that the URL-based enumerator trips over on this machine.
    var out = Set<String>()
    func walk(_ dir: String, _ prefix: String) {
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for name in names {
            let rel = prefix.isEmpty ? name : "\(prefix)/\(name)"
            out.insert(rel)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dir + "/" + name, isDirectory: &isDir), isDir.boolValue {
                walk(dir + "/" + name, rel)
            }
        }
    }
    walk(root.path, "")
    return out
}

func canon(_ url: URL) -> String {
    // FileManager returns /private/var form for some APIs and /var for others.
    // Normalize before any prefix comparison.
    var p = url.path
    if p.hasPrefix("/private/") { p = String(p.dropFirst("/private".count)) }
    return p
}

func withFixture(_ name: String, _ body: (URL) -> Void) {
    let root = fm.temporaryDirectory.appendingPathComponent("kc-\(name)-\(UUID().uuidString)").resolvingSymlinksInPath()
    makeDir(root)
    defer { try? fm.removeItem(at: root) }
    body(root)
}

// (a) Every category bucket lands in its folder; unknown and no-extension go to Other.
func testAllBuckets() {
    withFixture("buckets") { root in
        makeFile(root.appendingPathComponent("photo.jpg"))
        makeFile(root.appendingPathComponent("note.pdf"))
        makeFile(root.appendingPathComponent("clip.mp4"))
        makeFile(root.appendingPathComponent("song.mp3"))
        makeFile(root.appendingPathComponent("bundle.zip"))
        makeFile(root.appendingPathComponent("app.app"))
        makeFile(root.appendingPathComponent("script.py"))
        makeFile(root.appendingPathComponent("blob.xyz"))
        makeFile(root.appendingPathComponent("README"))
        let r = SortEngine.organize(directory: root)
        check("a1 moved count == 9", r.moved.count == 9, "got \(r.moved.count)")
        check("a2 Images/photo.jpg", exists(root, "Images/photo.jpg"))
        check("a3 Documents/note.pdf", exists(root, "Documents/note.pdf"))
        check("a4 Video/clip.mp4", exists(root, "Video/clip.mp4"))
        check("a5 Audio/song.mp3", exists(root, "Audio/song.mp3"))
        check("a6 Archives/bundle.zip", exists(root, "Archives/bundle.zip"))
        check("a7 Applications/app.app", exists(root, "Applications/app.app"))
        check("a8 Code/script.py", exists(root, "Code/script.py"))
        check("a9 Other/blob.xyz", exists(root, "Other/blob.xyz"))
        check("a10 Other/README (no extension)", exists(root, "Other/README"))
        check("a11 all 8 category folders exist",
              exists(root, "Images") && exists(root, "Documents") && exists(root, "Video")
              && exists(root, "Audio") && exists(root, "Archives") && exists(root, "Applications")
              && exists(root, "Code") && exists(root, "Other"))
    }
}

// (b) Uppercase extensions behave identically.
func testUppercaseExtensions() {
    withFixture("upper") { root in
        makeFile(root.appendingPathComponent("A.JPG"))
        makeFile(root.appendingPathComponent("B.PDF"))
        let r = SortEngine.organize(directory: root)
        check("b1 UPPER.JPG -> Images", exists(root, "Images/A.JPG"))
        check("b2 UPPER.PDF -> Documents", exists(root, "Documents/B.PDF"))
        check("b3 moved count == 2", r.moved.count == 2, "got \(r.moved.count)")
    }
}

// (d) Collision with existing folder content appends " 2", " 3" before the extension.
func testCollisions() {
    withFixture("collision") { root in
        makeDir(root.appendingPathComponent("Images"))
        makeFile(root.appendingPathComponent("Images/photo.jpg"))
        makeFile(root.appendingPathComponent("photo.jpg"))
        let r = SortEngine.organize(directory: root)
        check("d1 existing name stays", exists(root, "Images/photo.jpg"))
        check("d2 new file becomes photo 2.jpg", exists(root, "Images/photo 2.jpg"))
        check("d3 moved count == 1", r.moved.count == 1, "got \(r.moved.count)")
    }
    withFixture("collision3") { root in
        makeDir(root.appendingPathComponent("Images"))
        makeFile(root.appendingPathComponent("Images/photo.jpg"))
        makeFile(root.appendingPathComponent("Images/photo 2.jpg"))
        makeFile(root.appendingPathComponent("photo.jpg"))
        _ = SortEngine.organize(directory: root)
        check("d4 third file becomes photo 3.jpg", exists(root, "Images/photo 3.jpg"))
    }
}

// (e) Dotfiles stay untouched and are reported as skipped.
func testDotfiles() {
    withFixture("dotfiles") { root in
        makeFile(root.appendingPathComponent(".DS_Store"))
        makeFile(root.appendingPathComponent(".hidden"))
        let r = SortEngine.organize(directory: root)
        check("e1 .DS_Store stays at root", exists(root, ".DS_Store"))
        check("e2 .hidden stays at root", exists(root, ".hidden"))
        check("e3 moved count == 0", r.moved.count == 0, "got \(r.moved.count)")
        check("e4 skipped count == 2", r.skipped.count == 2, "got \(r.skipped.count)")
        check("e5 no folders created", relativePaths(root).filter { !$0.hasPrefix(".") }.isEmpty, "\(relativePaths(root))")
    }
}

// (f) Existing category folders and their contents are never touched.
func testExistingCategoryFolderUntouched() {
    withFixture("existing") { root in
        makeDir(root.appendingPathComponent("Documents"))
        makeFile(root.appendingPathComponent("Documents/old.pdf"))
        makeFile(root.appendingPathComponent("new.txt"))
        let r = SortEngine.organize(directory: root)
        check("f1 old.pdf untouched", exists(root, "Documents/old.pdf"))
        check("f2 new.txt moved in", exists(root, "Documents/new.txt"))
        check("f3 moved count == 1", r.moved.count == 1, "got \(r.moved.count)")
    }
}

// (g) Subdirectories are never recursed into, moved, or altered.
func testSubdirectoriesUntouched() {
    withFixture("subdirs") { root in
        makeDir(root.appendingPathComponent("Projects"))
        makeFile(root.appendingPathComponent("Projects/inner.txt"))
        let r = SortEngine.organize(directory: root)
        check("g1 Projects folder still there", exists(root, "Projects"))
        check("g2 inner file untouched", exists(root, "Projects/inner.txt"))
        check("g3 moved count == 0", r.moved.count == 0, "got \(r.moved.count)")
    }
}

// (h) Empty directory is a clean no-op.
func testEmptyDirectory() {
    withFixture("empty") { root in
        let r = SortEngine.organize(directory: root)
        check("h1 moved count == 0", r.moved.count == 0, "got \(r.moved.count)")
        check("h2 no folders created", relativePaths(root).isEmpty, "\(relativePaths(root))")
    }
}

// (i) Dry run computes the plan and leaves the directory byte-identical.
func testDryRunNoChanges() {
    withFixture("dryrun") { root in
        makeFile(root.appendingPathComponent("photo.jpg"))
        makeFile(root.appendingPathComponent("note.pdf"))
        makeFile(root.appendingPathComponent(".DS_Store"))
        let before = relativePaths(root)
        let r = SortEngine.organize(directory: root, dryRun: true)
        let after = relativePaths(root)
        check("i1 dry plan moves 2", r.moved.count == 2, "got \(r.moved.count)")
        check("i2 dry plan skips dotfile", r.skipped.count == 1, "got \(r.skipped.count)")
        check("i3 directory unchanged", before == after, "before \(before) after \(after)")
        check("i4 files still at root", exists(root, "photo.jpg") && exists(root, "note.pdf"))
        check("i5 no folders created by dry run", relativePaths(root).filter { !$0.hasPrefix(".") }.count == 2)
    }
}

// (j) Every destination path stays inside the target directory (bound check).
func testBoundCheck() {
    withFixture("bound") { root in
        makeFile(root.appendingPathComponent("a.jpg"))
        makeFile(root.appendingPathComponent("b.pdf"))
        makeFile(root.appendingPathComponent("c.zip"))
        let r = SortEngine.organize(directory: root)
        let rootNorm = canon(root) + "/"
        let allInside = r.moved.allSatisfy { canon($0.to).hasPrefix(rootNorm) }
        check("j1 all destinations inside target", allInside)
        let allFromInside = r.moved.allSatisfy { canon($0.from).hasPrefix(rootNorm) }
        check("j2 all sources inside target", allFromInside)
        let allFilesInside = relativePaths(root).allSatisfy { !$0.contains("..") }
        check("j3 no path escapes target", allFilesInside)
    }
}

// (k) Filenames with spaces and unicode sort correctly.
func testSpacesAndUnicode() {
    withFixture("unicode") { root in
        makeFile(root.appendingPathComponent("vacation photo 2026.jpg"))
        makeFile(root.appendingPathComponent("café menu.pdf"))
        let r = SortEngine.organize(directory: root)
        check("k1 spaces file -> Images", exists(root, "Images/vacation photo 2026.jpg"))
        check("k2 unicode file -> Documents", exists(root, "Documents/café menu.pdf"))
        check("k3 moved count == 2", r.moved.count == 2, "got \(r.moved.count)")
    }
}

// (l) Skipped items (dotfiles, directories, symlinks) are reported.
func testSkippedReported() {
    withFixture("skipped") { root in
        makeFile(root.appendingPathComponent(".DS_Store"))
        makeDir(root.appendingPathComponent("Stuff"))
        makeFile(root.appendingPathComponent("Stuff/inner.txt"))
        makeFile(root.appendingPathComponent("real.txt"))
        makeSymlink(root.appendingPathComponent("link.txt"), to: root.appendingPathComponent("real.txt"))
        let r = SortEngine.organize(directory: root)
        check("l1 skipped count == 3 (dotfile, dir, symlink)", r.skipped.count == 3, "got \(r.skipped.count)")
        check("l2 symlink still a symlink", (try? fm.destinationOfSymbolicLink(atPath: root.appendingPathComponent("link.txt").path)) != nil)
        check("l3 real.txt moved", exists(root, "Documents/real.txt"))
    }
}

// Extra: a second run is idempotent, nothing moves twice.
func testIdempotentSecondRun() {
    withFixture("idempotent") { root in
        makeFile(root.appendingPathComponent("photo.jpg"))
        makeFile(root.appendingPathComponent("note.pdf"))
        _ = SortEngine.organize(directory: root)
        let second = SortEngine.organize(directory: root)
        check("m1 second run moves 0", second.moved.count == 0, "got \(second.moved.count)")
        check("m2 files stay put", exists(root, "Images/photo.jpg") && exists(root, "Documents/note.pdf"))
    }
}

testAllBuckets()
testUppercaseExtensions()
testCollisions()
testDotfiles()
testExistingCategoryFolderUntouched()
testSubdirectoriesUntouched()
testEmptyDirectory()
testDryRunNoChanges()
testBoundCheck()
testSpacesAndUnicode()
testSkippedReported()
testIdempotentSecondRun()

print("")
print("Result: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
