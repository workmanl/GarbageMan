#!/usr/bin/env bash
#
# scripts/make-dmg.sh
#
# Build GarbageMan in Release, stage the .app + an /Applications symlink,
# and produce a compressed UDZO disk image ready for Gumroad upload.
#
# Optional environment variables:
#   SIGN_IDENTITY    — overrides the codesign identity. Defaults to "-" (ad-hoc).
#                      For real distribution, set this to "Developer ID Application: ..." and
#                      run `xcrun notarytool` afterwards.
#   SKIP_REGEN       — set to 1 to skip `xcodegen generate`.
#
# Output:
#   dist/GarbageMan-<version>.dmg
#
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

SIGN_IDENTITY="${SIGN_IDENTITY:-"-"}"
BUILD_DIR="${REPO_ROOT}/build"
DIST_DIR="${REPO_ROOT}/dist"
STAGE_DIR="${REPO_ROOT}/.dmg-stage"

# 1. Regenerate Xcode project unless caller opts out.
if [ "${SKIP_REGEN:-0}" != "1" ]; then
  echo "==> Regenerating Xcode project"
  xcodegen generate >/dev/null
fi

# 2. Build Release configuration.
echo "==> Building Release"
xcodebuild \
  -project GarbageMan.xcodeproj \
  -scheme GarbageMan \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build >/dev/null

APP_PATH="${BUILD_DIR}/Build/Products/Release/GarbageMan.app"
if [ ! -d "${APP_PATH}" ]; then
  echo "ERROR: Release build did not produce ${APP_PATH}" >&2
  exit 1
fi

# 3. Read version from the built Info.plist (single source of truth).
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist")
echo "==> GarbageMan version ${VERSION} (${BUILD})"

# 4. Stage the DMG contents.
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_PATH}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

# 5. Build the compressed DMG.
mkdir -p "${DIST_DIR}"
DMG_PATH="${DIST_DIR}/GarbageMan-${VERSION}.dmg"
rm -f "${DMG_PATH}"

echo "==> Creating DMG"
hdiutil create \
  -volname "GarbageMan ${VERSION}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "${DMG_PATH}" >/dev/null

# 6. Print summary.
SIZE=$(du -h "${DMG_PATH}" | awk '{print $1}')
echo ""
echo "✓ Wrote ${DMG_PATH} (${SIZE})"
echo ""
echo "Next steps to ship via Gumroad:"
echo "  1. (Required for users without bypassing Gatekeeper) Sign with a real identity:"
echo "       SIGN_IDENTITY='Developer ID Application: ...' bash scripts/make-dmg.sh"
echo "  2. Notarize:"
echo "       xcrun notarytool submit ${DMG_PATH} --apple-id <id> --team-id <team> --password <app-spec-pw> --wait"
echo "       xcrun stapler staple ${DMG_PATH}"
echo "  3. Upload to Gumroad as the new GarbageMan version file."

# 7. Clean up stage dir (keep dist/).
rm -rf "${STAGE_DIR}"
