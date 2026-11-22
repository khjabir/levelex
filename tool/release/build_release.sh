#!/usr/bin/env bash
# Builds the files a GitHub release needs, with the exact names the website
# links to, into build/release/. See docs/RELEASING.md.
#
#   tool/release/build_release.sh            Android APKs + checksums
#   tool/release/build_release.sh --ios      also the unsigned iPhone IPA (macOS)
#   tool/release/build_release.sh --allow-debug-key
#                                            test build without a release key
set -euo pipefail
shopt -s nullglob

cd "$(dirname "$0")/../.."

ios=0
allow_debug=0
for arg in "$@"; do
  case "$arg" in
    --ios) ios=1 ;;
    --allow-debug-key) allow_debug=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ ! -f android/key.properties && $allow_debug -eq 0 ]]; then
  cat >&2 <<'MSG'
android/key.properties is missing, so the APKs would be signed with this
machine's debug key. Android only installs an update over an app signed with
the same key, so everyone would have to uninstall (and lose their history) to
move to a properly signed build later. Create the release key first
(docs/RELEASING.md), or pass --allow-debug-key for a build you will not
publish.
MSG
  exit 1
fi

version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
out=build/release
rm -rf "$out"
mkdir -p "$out"

echo "Building Levelex $version"

flutter build apk --release --split-per-abi
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$out/levelex-android-arm64.apk"
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "$out/levelex-android-armv7.apk"

# Every real phone CPU (x86_64 is only used by emulators).
flutter build apk --release --target-platform android-arm,android-arm64
cp build/app/outputs/flutter-apk/app-release.apk "$out/levelex-android-universal.apk"

if [[ $ios -eq 1 ]]; then
  flutter build ios --release --no-codesign
  staging=$(mktemp -d)
  mkdir -p "$staging/Payload"
  cp -R build/ios/iphoneos/Runner.app "$staging/Payload/"
  (cd "$staging" && zip -qr levelex-ios-unsigned.ipa Payload)
  mv "$staging/levelex-ios-unsigned.ipa" "$out/"
  rm -rf "$staging"
fi

(cd "$out" && shasum -a 256 *.apk *.ipa > SHA256SUMS.txt)

echo
echo "Release files in $out:"
ls -lh "$out"
echo
echo "Publish them (GitHub CLI):"
echo "  gh release create v$version $out/* --title \"Levelex $version\" --notes \"…\""
echo "or upload them on https://github.com/khjabir/levelex/releases/new"
