# Releasing Levelex and deploying the website

Levelex is not in Google Play or the App Store. People install it from the
project's GitHub releases, guided by the website in `website/`. This page
covers both.

## One-time: create the Android release key

Android installs an update only over an app signed with the same key. Sign
public builds with a release key from the very first one; a build signed
with a debug key can never be updated in place by a properly signed one.

```bash
keytool -genkey -v -keystore ~/levelex-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (it is git-ignored):

```properties
storeFile=/Users/<you>/levelex-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Back up the keystore and its passwords somewhere safe. If the key is lost,
no existing install can be updated again.

## Publishing a release

1. Bump `version:` in `pubspec.yaml` (for example `1.0.1+2`; the number
   after `+` must go up with every release).
2. Run the checks: `dart format . && flutter analyze && flutter test`.
3. Build the release files:

   ```bash
   tool/release/build_release.sh --ios
   ```

   Leave out `--ios` when not on a Mac. The script writes these to
   `build/release/`, with the names the website links to:

   | File | For |
   |---|---|
   | `levelex-android-arm64.apk` | Nearly every Android phone (64-bit) |
   | `levelex-android-armv7.apk` | Older 32-bit Android phones |
   | `levelex-android-universal.apk` | Any Android phone (larger) |
   | `levelex-ios-unsigned.ipa` | iPhone, signed on install by Sideloadly or AltStore |
   | `SHA256SUMS.txt` | Checksums of the files above |

4. Install `levelex-android-arm64.apk` on a real phone and do one camera set.
   A release build can pass every test and still fail at launch.
5. Create the GitHub release with the tag `v<version>` and upload every file
   from `build/release/`, either on
   <https://github.com/khjabir/levelex/releases/new> or with the GitHub CLI:

   ```bash
   gh release create v1.0.1 build/release/* --title "Levelex 1.0.1" --notes "What changed"
   ```

The website picks the release up by itself: its download buttons use
GitHub's `releases/latest/download/<file>` links, and the page reads the
version and file sizes from GitHub's public API. Keep the file names
unchanged. A file missing from a release sends visitors to the release page
instead.

## The website

The site is plain HTML, CSS and JavaScript in `website/`, with no build
step:

| File | What it is |
|---|---|
| `website/index.html` | The page: features, 3D guide, exercises, privacy, install guide, FAQ |
| `website/styles.css` | Styles, using the app's colours |
| `website/main.js` | Menu, install tabs, release info, copy buttons and the 3D guide |
| `website/404.html` | Not-found page |
| `website/assets/` | Icons, screenshots, the Inter font and the 3D athlete |
| `vercel.json` | Tells Vercel to serve `website/` as a static site |

### Deploying on Vercel

1. In Vercel, choose **Add New → Project** and import the GitHub repository.
2. Keep the defaults and deploy. `vercel.json` at the repository root sets
   the framework to "Other", skips the install step, and serves the
   `website/` folder, so no Root Directory or build settings are needed.
3. Optional: add your own domain under **Settings → Domains**.

Every push to the production branch redeploys the site. The Flutter app
itself is never built on Vercel.

### Previewing locally

```bash
python3 -m http.server 4173 --directory website
```

Then open <http://localhost:4173>.

### Updating the site's content

- **Screenshots** live in `website/assets/shots/` (540 px wide JPEGs).
- **The 3D athlete** is a web copy of the app's model. After rebuilding
  `assets/figure/athlete.glb`, regenerate it:

  ```bash
  python3 tool/website/make_web_glb.py assets/figure/athlete.glb website/assets/athlete.glb
  ```

  The app keeps baked shading in the model's vertex colours, which a
  standard viewer would show as a red tint; the script turns them into
  plain grey shading.
- **The 3D viewer** is Google's
  [`<model-viewer>`](https://modelviewer.dev), loaded from jsDelivr at a
  fixed version in `index.html`.
