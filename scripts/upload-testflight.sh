#!/usr/bin/env bash
#
# MioCam iOS 完全自動ビルド & App Store Connect (TestFlight) アップロード
#
# これ1コマンドで: XcodeGen 生成 -> アーカイブ -> IPA 書き出し -> TestFlight アップロード
# 署名は TsureBen と共用の App Store Connect API キーで自動取得する。
#
# 事前準備:
#   - ../TsureBen/ios/.appstore.env が設定済みであること
#   - App Store Connect に Bundle ID com.itoguchi.MioCam の App レコードがあること
#   - xcodegen がインストールされていること
#
# 使い方:
#   ./scripts/upload-testflight.sh
#   ./scripts/upload-testflight.sh 2.0.1
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/MioCam.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT_DIR/ExportOptions.plist"
ENV_FILE="${APPSTORE_ENV:-$ROOT_DIR/../TsureBen/ios/.appstore.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE がありません。" >&2
  echo "TsureBen の ios/.appstore.env を設定するか、APPSTORE_ENV でパスを指定してください。" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${ASC_KEY_ID:?ASC_KEY_ID 未設定}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID 未設定}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH 未設定}"
ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "ERROR: API キーが見つかりません: $ASC_KEY_PATH" >&2
  exit 1
fi

MARKETING_VERSION="${1:-}"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

AUTH_ARGS=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

if ! xcodebuild -showsdks 2>/dev/null | grep -qi "iphoneos"; then
  echo "ERROR: iOS プラットフォームが未インストールです。次を実行してください:" >&2
  echo "  xcodebuild -downloadPlatform iOS" >&2
  exit 1
fi

if [[ -n "$MARKETING_VERSION" ]]; then
  echo "==> バージョン ${MARKETING_VERSION} に更新"
  sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"${MARKETING_VERSION}\"/" "$ROOT_DIR/project.yml"
  echo "$MARKETING_VERSION" > "$ROOT_DIR/VERSION"
fi

echo "==> 1/4 Xcode プロジェクト生成"
cd "$ROOT_DIR"
xcodegen generate

echo "==> 2/4 アーカイブ作成 (build $BUILD_NUMBER)"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$BUILD_DIR"
VERSION_OVERRIDE=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
[[ -n "$MARKETING_VERSION" ]] && VERSION_OVERRIDE+=(MARKETING_VERSION="$MARKETING_VERSION")

xcodebuild \
  -scheme MioCam \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  "${AUTH_ARGS[@]}" \
  "${VERSION_OVERRIDE[@]}" \
  archive

echo "==> 3/4 IPA 書き出し"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  "${AUTH_ARGS[@]}"

echo "==> 4/4 App Store Connect へアップロード"
IPA_PATH="$(ls "$EXPORT_PATH"/*.ipa | head -n1)"
xcrun altool --upload-app \
  --type ios \
  --file "$IPA_PATH" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo ""
echo "✅ アップロード完了 (build ${BUILD_NUMBER})"
echo "   App Store Connect → MioCam → TestFlight で処理完了を待ってください（5〜30分）"
