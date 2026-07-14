#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
derived_data="${CAPDECK_DERIVED_DATA:-/tmp/CapDeckReleaseDerived}"
dist_directory="$project_root/dist"
app_source="$derived_data/Build/Products/Release/CapDeck.app"
app_destination="$dist_directory/CapDeck.app"
sparkle_framework="$app_destination/Contents/Frameworks/Sparkle.framework"

mkdir -p "$dist_directory"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcodebuild build \
  -project "$project_root/CapDeck.xcodeproj" \
  -scheme CapDeck \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$app_source/Contents/Info.plist")
if [[ -z "$version" ]]; then
  print -u2 "Unable to read CFBundleShortVersionString from the Release app."
  exit 1
fi

archive_filename="CapDeck-${version}-macOS.zip"
checksum_filename="$archive_filename.sha256"
archive_path="$dist_directory/$archive_filename"
checksum_path="$dist_directory/$checksum_filename"

rm -rf "$app_destination" "$archive_path" "$checksum_path"
ditto "$app_source" "$app_destination"

signing_identity="${CAPDECK_SIGNING_IDENTITY:--}"
timestamp_arguments=()
temporary_entitlements=$(mktemp -t CapDeck-entitlements).plist
trap 'rm -f "$temporary_entitlements"' EXIT
cp "$project_root/CapDeck/CapDeck.entitlements" "$temporary_entitlements"
bundle_identifier=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
  "$app_destination/Contents/Info.plist")
/usr/libexec/PlistBuddy -c \
  "Set :com.apple.security.temporary-exception.mach-lookup.global-name:0 ${bundle_identifier}-spks" \
  "$temporary_entitlements"
/usr/libexec/PlistBuddy -c \
  "Set :com.apple.security.temporary-exception.mach-lookup.global-name:1 ${bundle_identifier}-spki" \
  "$temporary_entitlements"
app_entitlements="$temporary_entitlements"

if [[ "$signing_identity" == "-" ]]; then
  /usr/libexec/PlistBuddy -c \
    "Add :com.apple.security.cs.disable-library-validation bool true" \
    "$temporary_entitlements"
  print "No CAPDECK_SIGNING_IDENTITY supplied; preparing an ad-hoc local build."
else
  timestamp_arguments=(--timestamp)
fi

# Sparkle's nested helpers have distinct signing requirements. Sign them from
# the inside out with the same identity as the host app; do not use --deep.
codesign --force --sign "$signing_identity" --options runtime \
  "${timestamp_arguments[@]}" \
  "$sparkle_framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$signing_identity" --options runtime \
  "${timestamp_arguments[@]}" --preserve-metadata=entitlements \
  "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$signing_identity" --options runtime \
  "${timestamp_arguments[@]}" \
  "$sparkle_framework/Versions/B/Autoupdate"
codesign --force --sign "$signing_identity" --options runtime \
  "${timestamp_arguments[@]}" \
  "$sparkle_framework/Versions/B/Updater.app"
codesign --force --sign "$signing_identity" --options runtime \
  "${timestamp_arguments[@]}" "$sparkle_framework"
codesign --force --sign "$signing_identity" --options runtime \
  "${timestamp_arguments[@]}" --entitlements "$app_entitlements" \
  "$app_destination"

codesign --verify --deep --strict --verbose=2 "$app_destination"

for key in \
  SUFeedURL \
  SUPublicEDKey \
  SUEnableInstallerLauncherService \
  SUEnableDownloaderService \
  SUVerifyUpdateBeforeExtraction \
  SURequireSignedFeed; do
  if ! plutil -extract "$key" raw "$app_destination/Contents/Info.plist" >/dev/null; then
    print -u2 "Release app is missing required update key: $key"
    exit 1
  fi
done

ditto -c -k --sequesterRsrc --keepParent "$app_destination" "$archive_path"
(
  cd "$dist_directory"
  shasum -a 256 "$archive_filename" > "$checksum_filename"
)

print "Release app: $app_destination"
print "Archive: $archive_path"
print "Checksum: $checksum_path"
