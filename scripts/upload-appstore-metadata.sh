#!/usr/bin/env bash
#
# App Store Connect へメタデータ & スクリーンショットを一括アップロード
#
# 使い方:
#   ./scripts/upload-appstore-metadata.sh
#   ./scripts/upload-appstore-metadata.sh --version 2.0.2
#   ./scripts/upload-appstore-metadata.sh --create-version
#   ./scripts/upload-appstore-metadata.sh --metadata-only
#   ./scripts/upload-appstore-metadata.sh --screenshots-only --locale en ja
#   ./scripts/upload-appstore-metadata.sh --dry-run
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${APPSTORE_ENV:-$ROOT_DIR/../TsureBen/ios/.appstore.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE がありません。" >&2
  echo "TsureBen の ios/.appstore.env を設定するか、APPSTORE_ENV でパスを指定してください。" >&2
  exit 1
fi

python3 "$ROOT_DIR/scripts/upload-appstore-metadata.py" --env-file "$ENV_FILE" "$@"
