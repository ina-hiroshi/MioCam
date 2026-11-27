#!/bin/bash
# App Store 用・加工なしスクリーンショット自動撮影（6.7" = iPhone 16 Pro Max）
# 各言語の raw 画像を appstore/screenshots/raw/<locale>/ に保存
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ID="${SIM_ID:-84443A16-8E0D-430F-9910-552F9AD1F7B8}"
BUNDLE_ID="com.itoguchi.MioCam"
DERIVED="$ROOT/.derivedData"

# 撮影する言語（フォルダ名: ja en es pt-BR ko）
LOCALES=(${LOCALES:-ja en es pt-BR ko})

# locale → AppleLanguages コード
locale_to_apple_lang() {
  case "$1" in
    ja) echo "ja" ;;
    en) echo "en" ;;
    es) echo "es" ;;
    pt-BR) echo "pt-BR" ;;
    ko) echo "ko" ;;
    *) echo "$1" ;;
  esac
}

screens=(qr_code camera_settings role_selection monitor_list live_nursery live_livingroom)
screen_files=(
  "01_qr_code"
  "02_camera_settings"
  "03_role_selection"
  "04_monitor_list"
  "05_live_nursery"
  "06_live_livingroom"
)

if [[ ! -f "$ROOT/MioCam.xcodeproj/project.pbxproj" ]]; then
  echo "==> Xcode プロジェクト生成"
  (cd "$ROOT" && xcodegen generate)
fi

echo "==> ビルド中..."
xcodebuild \
  -project "$ROOT/MioCam.xcodeproj" \
  -scheme MioCam \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DERIVED" \
  build > /dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/MioCam.app"

echo "==> シミュレータ準備..."
xcrun simctl shutdown "$SIM_ID" 2>/dev/null || true
xcrun simctl boot "$SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b

xcrun simctl status_bar "$SIM_ID" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4

for locale in "${LOCALES[@]}"; do
  apple_lang="$(locale_to_apple_lang "$locale")"
  OUT_DIR="$ROOT/appstore/screenshots/raw/$locale"
  mkdir -p "$OUT_DIR"

  echo ""
  echo "==> 言語: $locale ($apple_lang)"

  xcrun simctl spawn "$SIM_ID" defaults write "Apple Global Domain" AppleLanguages -array "$apple_lang"
  xcrun simctl spawn "$SIM_ID" defaults write "Apple Global Domain" AppleLocale -string "$apple_lang"

  xcrun simctl uninstall "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$SIM_ID" "$APP"
  xcrun simctl privacy "$SIM_ID" grant notifications "$BUNDLE_ID" 2>/dev/null || true

  for i in "${!screens[@]}"; do
    screen="${screens[$i]}"
    outfile_name="${screen_files[$i]}.png"
    echo "  撮影: $screen"
    xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl spawn "$SIM_ID" defaults write "$BUNDLE_ID" APPSTORE_SCREENSHOT "$screen"
    sleep 1
    xcrun simctl launch --terminate-running-process "$SIM_ID" "$BUNDLE_ID" -AppleLanguages "($apple_lang)"
    sleep 4
    outfile="$OUT_DIR/$outfile_name"
    xcrun simctl io "$SIM_ID" screenshot "$outfile"
    echo "    → $outfile"
  done

  xcrun simctl spawn "$SIM_ID" defaults delete "$BUNDLE_ID" APPSTORE_SCREENSHOT 2>/dev/null || true
done

xcrun simctl status_bar "$SIM_ID" clear 2>/dev/null || true

echo ""
echo "完了: appstore/screenshots/raw/ に ${#LOCALES[@]} 言語 × ${#screens[@]} 枚を保存しました。"
