# KuromiCleans

Tidy up in one click. KuromiCleans sorts everything in your Downloads folder into neat category subfolders, shows a friendly alert, and gets out of your way.

## What it does

Double-click the app. It looks at the files directly inside ~/Downloads, moves each one into its matching category subfolder, shows "Downloads sorted. Moved N files.", and quits. No windows, no menu bar, nothing left running.

Things it leaves alone:

- Dotfiles like .DS_Store
- Folders and everything inside them
- Files that already live inside category subfolders
- Symlinks

Matching is case-insensitive, so PHOTO.JPG lands in Images too. When two files share a name, the second one becomes "report 2.pdf", then "report 3.pdf".

## Install

1. Open the KuromiCleans.dmg file.
2. Drag KuromiCleans.app into Applications.
3. First launch: right-click KuromiCleans in Applications, choose Open, then click Open. The app is not notarized, so this is expected the first time.

## Usage

Double-click KuromiCleans. That is all.

## Categories

| Category | Extensions |
|---|---|
| Images | jpg, jpeg, png, gif, heic, heif, webp, svg, tiff, tif, bmp, raw, cr2, nef, psd, ai, eps |
| Documents | pdf, doc, docx, txt, md, rtf, odt, xls, xlsx, ppt, pptx, csv, pages, numbers, key, epub, mobi |
| Video | mp4, mov, mkv, avi, webm, m4v, wmv, flv, ts |
| Audio | mp3, wav, aac, flac, m4a, ogg, aiff, wma, opus |
| Archives | zip, rar, 7z, tar, gz, bz2, xz, dmg, pkg, iso, cab |
| Applications | app |
| Code | swift, py, js, ts, jsx, tsx, html, css, json, yaml, yml, xml, sh, bash, rb, go, rs, java, c, cpp, h, hpp, ipynb, sql, toml |
| Other | everything else, and files with no extension |

## Custom icon

Drop a 1024x1024 PNG at Assets/AppIcon-source.png (any background), strip the
background and scale the character up, then rebuild:

```sh
swift Scripts/icon_clean.swift Assets/AppIcon-source.png Assets/AppIcon.png 1.075
bash Scripts/build_app.sh
bash Scripts/make_dmg.sh
```

The tool flood-fills the background away from the image borders, so the
character's own dark pixels stay intact, then scales her up by the given
factor (1.075 = 7.5% bigger) centered in the frame. If Assets/AppIcon.png is
missing entirely, a pink placeholder icon is generated automatically.

## Build from source

Requirements: a Mac with the Swift command line tools (swift, sips, iconutil, codesign, hdiutil). No third party dependencies, no network access needed.

```sh
bash Scripts/mechanism_test.sh  # deterministic mechanism test on a staged folder
bash Scripts/build_app.sh  # build dist/KuromiCleans.app (universal when possible)
bash Scripts/make_dmg.sh   # package dist/KuromiCleans.dmg
bash Scripts/smoke.sh      # dry-run preview against your real Downloads, moves nothing
```

Developer flags for the app binary:

```sh
dist/KuromiCleans.app/Contents/MacOS/KuromiCleans --dry-run --path /some/folder
dist/KuromiCleans.app/Contents/MacOS/KuromiCleans --dump --no-alert --path /some/folder
dist/KuromiCleans.app/Contents/MacOS/KuromiCleans --check --path /some/folder
dist/KuromiCleans.app/Contents/MacOS/KuromiCleans --version
```

Verification works through the binary's own diagnostics. `--dump` emits a JSON
report of any run: per-category counts, every moved file with its destination,
skip reasons (dotfile, directory, symlink), collision renames, errors, bytes
moved, elapsed time. `--check` validates a folder's state with health codes
(`HEALTH OK` / `HEALTH FAIL`) for loose files at the root and category mismatches,
and exits nonzero when anything is off. `Scripts/mechanism_test.sh` drives both
against a deterministic staged folder and asserts the diagnostic output. For
live evidence on the real Downloads folder, run the binary with
`--dump --no-alert`, then `--check`.
