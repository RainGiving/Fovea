# Fovea

[简体中文](README-CN.md)

<p align="center">
  <img src="docs/assets/fovea-icon.png" width="128" alt="Fovea icon">
</p>

Fovea is a native macOS image viewer designed for fast opening, continuous browsing within a folder, and trackpad navigation. It supports common and professional image formats and can be set as the default image app.

<p align="center">
  <img src="docs/assets/screenshots/fovea-welcome.png" width="860" alt="Fovea welcome screen with actions for opening an image or browsing a folder">
</p>

<p align="center">
  <img src="docs/assets/screenshots/fovea-viewer.png" width="860" alt="Fovea displaying an image with page controls and a filmstrip">
</p>

## Features

- Opens JPEG, PNG, GIF, TIFF, BMP, HEIC, HEIF, WebP, AVIF, SVG, and a range of RAW and professional formats.
- Loads images from Finder, drag and drop, recent items, or the Open menu, then browses the current folder in natural order.
- Navigates with the keyboard, page controls, or horizontal trackpad gestures, with zoom, pan, full screen, and continuous vertical reading.
- Provides an auto-hiding filmstrip, metadata inspector, searchable help, usage hints, and light, dark, or system appearance.
- Supports rotate, mirror, freeform crop, undo and redo, save, save as, rename, move to Trash, and reveal in Finder.
- Includes folder search, format filters, sorting, multi-selection, batch move, batch rename, cancellable progress, and one-step undo.

## Install with Homebrew

The current release targets Apple Silicon and requires macOS 26 or later.

```bash
brew tap RainGiving/tap
brew install --cask fovea
```

Update an existing installation:

```bash
brew update
brew upgrade --cask fovea
```

Disk images are also available from [GitHub Releases](https://github.com/RainGiving/Fovea/releases).

## Build from source

Building requires the macOS 26 SDK and Swift 6.2 or later.

```bash
make check
make build
open .build/Fovea.app
```

Additional commands:

```bash
make test      # Run tests
make audit     # Run the project audit
make check     # Run tests and the audit
make dmg       # Create .build/artifacts/Fovea-X.Y.Z.dmg
make install   # Install /Applications/Fovea.app
make clean     # Remove .build
```

## Release

`CFBundleShortVersionString` is the release version source. `make version` prints the current version.

```bash
make release VERSION=X.Y.Z
git tag vX.Y.Z
git push origin main --follow-tags
```

GitHub Actions checks the tag and version, reruns the test suite and audit, creates the versioned DMG, and publishes it to GitHub Releases.

## Name migration

Fovea is the successor name to ImageView. The app bundle is `/Applications/Fovea.app`, and its bundle identifier is `io.github.raingiving.fovea`. Historical design, planning, QA, and performance documents retain the ImageView name to preserve their original context.

## License

[MIT License](LICENSE)
