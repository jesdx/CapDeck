#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
derived_data="${CAPDECK_DERIVED_DATA:-/tmp/CapDeckReleaseDerived}"
feed_directory="${1:-$project_root/dist/update-feed}"
release_app="$project_root/dist/CapDeck.app"

if [[ ! -d "$release_app" ]]; then
  print -u2 "Build the Release app first with Scripts/build-release.sh."
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$release_app/Contents/Info.plist")
archive_filename="CapDeck-${version}-macOS.zip"
archive_path="$project_root/dist/$archive_filename"
release_notes="$project_root/ReleaseNotes/${version}.md"
sparkle_bin="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
generate_appcast="$sparkle_bin/generate_appcast"
key_arguments=()

if [[ -n "${CAPDECK_SPARKLE_KEY_FILE:-}" ]]; then
  key_arguments=(--ed-key-file "$CAPDECK_SPARKLE_KEY_FILE")
fi

if [[ ! -f "$archive_path" ]]; then
  print -u2 "Missing Release archive: $archive_path"
  exit 1
fi
if [[ ! -f "$release_notes" ]]; then
  print -u2 "Missing release notes: $release_notes"
  exit 1
fi
if [[ ! -x "$generate_appcast" ]]; then
  print -u2 "Sparkle generate_appcast tool not found under $sparkle_bin"
  exit 1
fi

mkdir -p "$feed_directory"
cp "$archive_path" "$feed_directory/$archive_filename"
cp "$release_notes" "$feed_directory/CapDeck-${version}-macOS.md"

"$generate_appcast" \
  "${key_arguments[@]}" \
  --download-url-prefix \
  "https://github.com/jesdx/CapDeck-Releases/releases/download/v${version}/" \
  --embed-release-notes \
  --maximum-versions 10 \
  "$feed_directory"

print "Prepared signed appcast: $feed_directory/appcast.xml"
print "Release asset: $archive_path"
