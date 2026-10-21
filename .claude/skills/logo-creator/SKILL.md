---
name: logo-creator
description: Generate or refresh the Levelex app logo, launcher icons and splash screen from vector art drawn with a CoreGraphics script. Use when asked to change the logo, icon, brand mark, splash or adaptive icon, or to try new logo variants.
---

# Logo creator

Levelex's logo is **generated, not drawn by hand**: a Swift/CoreGraphics
script renders the mark into PNGs, and the Flutter icon and splash tools fan
those out to every platform size. The in-app mark (`BrandMark`) is a
`CustomPainter` that mirrors the same geometry, so the icon and the UI always
match.

## Files

| Path | Role |
| --- | --- |
| `tool/logo/make_logo.swift` | The generator. Variants: `figure` (current), `arrowL`, `bolt`. Modes: `full` (rounded square), `foreground` (transparent, padded for adaptive icons), `background` (square, no mark). |
| `assets/icon/icon.png` | 1024² full icon (iOS, legacy Android). |
| `assets/icon/icon_foreground.png` / `icon_background.png` | Android adaptive layers. |
| `assets/icon/splash.png` | Splash mark (same as the foreground). |
| `lib/widgets/brand_mark.dart` | `BrandMark` / `BrandWordmark` painters used in the UI. |
| `pubspec.yaml` → `flutter_launcher_icons:` and `flutter_native_splash:` | Generator config (colours, paths). |

Brand gradient: lime `#C6FF3D` → mint `#39FF88` → cyan `#38E5FF`, on deep
navy `#07090E` / `#131A26`. Keep the mark a single silhouette with round caps
so it survives 48 px.

## Regenerate the current logo

```bash
cd tool/logo && swiftc -O make_logo.swift -o make_logo
./make_logo ../../assets/icon/icon.png figure full
./make_logo ../../assets/icon/icon_foreground.png figure foreground
./make_logo ../../assets/icon/icon_background.png figure background
cp ../../assets/icon/icon_foreground.png ../../assets/icon/splash.png
cd ../.. && dart run flutter_launcher_icons && dart run flutter_native_splash:create
```

Then rebuild the app; icons are baked at build time.

## Try a new design

1. Add a `case "<name>":` to the `switch variant` block in
   `make_logo.swift`. Build the mark from `stroke([...], width)` polylines
   and `addEllipse` in a unit square (y up); the script adds the gradient,
   highlight and shadow.
2. Render candidates side by side and look at them before choosing:
   `./make_logo /tmp/a.png <name> full && sips -Z 340 /tmp/a.png --out /tmp/a_small.png`
   (view the small one; a logo that only works at 1024 px is wrong).
3. When one wins, regenerate as above and update `_MarkPainter.paint` in
   `brand_mark.dart` to the same coordinates so the in-app mark matches.
4. Check the README "Branding" section still describes the mark.

## Checklist before shipping

- `flutter analyze` clean, `flutter test` green (the mark painter is pure UI,
  but the icon config is read at build time).
- Android: `android/app/src/main/res/mipmap-*` and `mipmap-anydpi-v26`
  regenerated; iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset` replaced.
- Install on a device and look at the home screen and the splash in both
  light and dark system themes.
