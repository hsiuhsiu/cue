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


## Built-in command icons

`Sources/Cue/CommandIcon.swift` draws Cue's eight command icons: Clipboard
History, Sleep, Lock Screen, Screen Off, the two Chinese conversion directions,
Update Application Index, and Chinese Conversion Settings. They share a white
rounded background with blue line drawings and generous space around each
symbol. Update Index centers a four-tile app grid inside a surrounding refresh
arc; Sleep uses a complete outlined crescent, and Screen Off places a moon inside
a monitor.
The conversion icons have a right-pointing arrow to the left of the smaller
target character **繁** or **简**. Conversion Settings keeps **繁** at the upper left
and **简** at the lower right, with a larger independent gear at the upper right.
Separate arrows along the sides point up on the left and down on the right,
keeping both conversion directions clear of the gear and characters.

These compact vectors use Core Graphics and Core Text, with no new image library
or bundled raster set. `AppIconCache` prepares 28/56-pixel representations once
on a background worker and keeps the 28-point images across application-index
refreshes. Drawing result rows only reads that cache. The supplied app icon,
menu bar mark, and installed applications' icons retain their own artwork.

內建指令統一採白色圓角底與藍色線條，圖案四周保留較多留白。更新索引以置中的
四格 App 圖案搭配外圍更新弧線表示；睡眠使用完整的新月輪廓，關閉螢幕則在
螢幕中放入月亮。簡繁互轉以左側向右箭頭指向較小的「繁／简」目標字；轉換設定
保留左上的「繁」與右下的「简」，右上以較大、獨立的齒輪表示設定。箭頭移至兩側，
左側向上、右側向下，不與齒輪或文字相接，讓雙向轉換更清楚。
圖示於背景一次產生一般與 Retina 螢幕所需的尺寸並快取，
重新索引 App 時也不重畫，搜尋與打字時只讀取現成圖示。

Run `./scripts/check-command-icons.sh` for cache and raster checks, or append
`--preview .build/command-icons-preview.png` to render the visual review sheet.
