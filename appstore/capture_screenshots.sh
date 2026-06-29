#!/bin/bash
# App Store 用スクリーンショット自動撮影（6.7" = iPhone 16 Pro Max, 1290×2796）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ID="${SIM_ID:-F2CE3B7D-8299-4BB3-BF94-2910F7AEFA1D}"
BUNDLE_ID="com.itoguchi.MioCam"
OUT_DIR="$ROOT/appstore/iphone16"
DERIVED="$ROOT/.derivedData"

mkdir -p "$OUT_DIR"

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

xcrun simctl uninstall "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIM_ID" "$APP"

xcrun simctl privacy "$SIM_ID" grant notifications "$BUNDLE_ID" 2>/dev/null || true

screens=(live_nursery live_livingroom camera_qr monitor_list role_selection)

for screen in "${screens[@]}"; do
  echo "==> 撮影: $screen"
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl spawn "$SIM_ID" defaults write "$BUNDLE_ID" APPSTORE_SCREENSHOT "$screen"
  sleep 1
  xcrun simctl launch --terminate-running-process "$SIM_ID" "$BUNDLE_ID"
  sleep 4
  outfile="$OUT_DIR/${screen}.png"
  xcrun simctl io "$SIM_ID" screenshot "$outfile"
  echo "    → $outfile"
done

xcrun simctl spawn "$SIM_ID" defaults delete "$BUNDLE_ID" APPSTORE_SCREENSHOT 2>/dev/null || true
xcrun simctl status_bar "$SIM_ID" clear 2>/dev/null || true

echo ""
echo "完了: $OUT_DIR に ${#screens[@]} 枚保存しました。"
