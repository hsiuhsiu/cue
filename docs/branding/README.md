# Cue artwork

The supplied app icon and menu bar mark are retained in `source/` without changes.
The app icon's transparent padding is preserved; the menu bar mark is cropped to
its visible shape and fitted into an 18-point template with a one-point margin.
macOS applies the template color for light, dark, and selected appearances.

- `Resources/AppIcon.icns`: 16 through 1024 pixels for Finder, system dialogs,
  the standard About panel, and Sparkle update windows.
- `Resources/MenuBarIconTemplate.png` and `@2x`: 18/36-pixel menu bar artwork.
- `Resources/MenuBarIconUpdateTemplate.png` and `@2x`: the same mark with an
  update dot, retaining Cue's identity while an update is available.
- `cue-icon.png`: a 256-pixel preview displayed in the GitHub README.
- `menu-bar-light.png` and `menu-bar-dark.png`: small GitHub previews selected
  according to the viewer's color scheme.

Regenerate these files from the repository root with full Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift scripts/prepare-branding.swift
```

This is an offline asset preparation step using macOS image tools. App builds
use the checked-in resources; Cue never resizes or generates artwork during
typing, searching, or update checks. Original images and documentation previews
are not copied into the app bundle.
