#!/usr/bin/env python3
"""App Store Connect へメタデータとスクリーンショットを一括アップロード.

appstore/metadata/*.json と appstore/marketing/localized/<locale>/ を読み込み、
App Store Connect API 経由で反映します。

前提:
  - ../TsureBen/ios/.appstore.env に API キーが設定済み
  - 対象バージョン (例: 2.0.2) が ASC 上で編集可能な状態
  - 新規言語の subtitle 用 appInfoLocalization は ASC UI で言語追加が必要な場合あり

使い方:
  ./scripts/upload-appstore-metadata.sh
  ./scripts/upload-appstore-metadata.sh --version 2.0.2
  ./scripts/upload-appstore-metadata.sh --metadata-only
  ./scripts/upload-appstore-metadata.sh --screenshots-only --locale en ja
  ./scripts/upload-appstore-metadata.sh --dry-run
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any

import jwt
import requests

try:
    from PIL import Image
except ImportError:
    Image = None  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
METADATA_DIR = ROOT / "appstore" / "metadata"
SCREENSHOTS_DIR = ROOT / "appstore" / "screenshots" / "raw"
DEFAULT_ENV = ROOT.parent / "TsureBen" / "ios" / ".appstore.env"
BUNDLE_ID = "com.itoguchi.MioCam"
API_BASE = "https://api.appstoreconnect.apple.com/v1"

# AppMockUp 出力フォルダ名 → App Store Connect display type
MOCKUP_DEVICE_FOLDERS: list[tuple[str, str]] = [
    ("Apple iPhone 16 Pro Max (1320x2868)", "APP_IPHONE_69"),
    ("Apple iPhone 14 Plus (1284x2778)", "APP_IPHONE_65"),
    ("Apple iPad Pro 12.9 Inch (2048x2732)", "APP_IPAD_PRO_129"),
]

# metadata/<file>.json → screenshots/<dir>/
LOCALE_FOLDER_MAP = {
    "ja": "ja",
    "en": "en",
    "es": "es",
    "pt-BR": "pt-BR",
    "ko": "ko",
}

EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_MISSING",
    "WAITING_FOR_REVIEW",
    "READY_FOR_REVIEW",
}


class ASCClient:
    def __init__(self, key_id: str, issuer_id: str, key_path: Path, dry_run: bool = False):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_path = key_path
        self.dry_run = dry_run
        self._private_key = key_path.read_text(encoding="utf-8")
        self.session = requests.Session()

    def _token(self) -> str:
        now = int(time.time())
        payload = {
            "iss": self.issuer_id,
            "iat": now,
            "exp": now + 1200,
            "aud": "appstoreconnect-v1",
        }
        headers = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        return jwt.encode(payload, self._private_key, algorithm="ES256", headers=headers)

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict | None = None,
        json_body: dict | None = None,
        raw: bool = False,
        retries: int = 3,
    ) -> requests.Response:
        url = f"{API_BASE}{path}" if path.startswith("/") else path
        headers = {"Authorization": f"Bearer {self._token()}"}
        if not raw:
            headers["Content-Type"] = "application/json"

        for attempt in range(retries):
            response = self.session.request(
                method,
                url,
                headers=headers,
                params=params,
                json=json_body,
                timeout=120,
            )
            if response.status_code == 429 and attempt + 1 < retries:
                time.sleep(2 ** attempt)
                continue
            return response
        return response

    def get_json(self, path: str, *, params: dict | None = None) -> dict:
        response = self.request("GET", path, params=params)
        if not response.ok:
            raise RuntimeError(f"GET {path} failed ({response.status_code}): {response.text[:500]}")
        return response.json()

    def mutate(self, method: str, path: str, body: dict, *, ignore_status: set[int] | None = None) -> dict | None:
        if self.dry_run:
            print(f"  [dry-run] {method} {path}")
            return None
        response = self.request(method, path, json_body=body)
        if ignore_status and response.status_code in ignore_status:
            return None
        if not response.ok:
            raise RuntimeError(f"{method} {path} failed ({response.status_code}): {response.text[:500]}")
        if not response.text.strip():
            return None
        return response.json()


def expand_path(value: str) -> str:
    value = value.strip().strip('"').strip("'")
    if value.startswith("$HOME"):
        return os.path.expanduser("~") + value[5:]
    if value.startswith("~"):
        return os.path.expanduser(value)
    return value


def load_env(env_file: Path) -> dict[str, str]:
    if not env_file.exists():
        raise FileNotFoundError(f"env file not found: {env_file}")
    env: dict[str, str] = {}
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key] = expand_path(value)
    for required in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
        if required not in env:
            raise RuntimeError(f"{required} is missing in {env_file}")
    key_path = Path(env["ASC_KEY_PATH"])
    if not key_path.exists():
        raise FileNotFoundError(f"API key not found: {key_path}")
    return env


def load_metadata(locale_filter: set[str] | None) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for path in sorted(METADATA_DIR.glob("*.json")):
        if path.name in {"screenshots.json"}:
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        locale = data["locale"]
        folder = LOCALE_FOLDER_MAP.get(path.stem, path.stem)
        if locale_filter and folder not in locale_filter and locale not in locale_filter:
            continue
        data["_folder"] = folder
        data["_path"] = path
        items.append(data)
    if not items:
        raise RuntimeError("No metadata files matched the locale filter.")
    return items


def find_app(client: ASCClient) -> dict:
    payload = client.get_json("/apps", params={"filter[bundleId]": BUNDLE_ID})
    apps = payload.get("data", [])
    if not apps:
        raise RuntimeError(f"App not found for bundle id {BUNDLE_ID}")
    return apps[0]


def find_app_info(client: ASCClient, app_id: str) -> dict:
    payload = client.get_json(f"/apps/{app_id}/appInfos")
    infos = payload.get("data", [])
    if not infos:
        raise RuntimeError("No appInfos found.")
    return infos[0]


def find_or_create_version(client: ASCClient, app_id: str, version_string: str, create: bool) -> dict:
    payload = client.get_json(
        f"/apps/{app_id}/appStoreVersions",
        params={"filter[platform]": "IOS", "limit": 20},
    )
    matches = [
        item for item in payload.get("data", [])
        if item["attributes"].get("versionString") == version_string
    ]
    if matches:
        version = matches[0]
        print(f"==> Version {version_string} ({version['attributes'].get('appStoreState')})")
        return version

    if not create:
        raise RuntimeError(
            f"Version {version_string} not found in App Store Connect. "
            f"Re-run with --create-version or create it in the web UI."
        )

    print(f"==> Creating version {version_string}")
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": version_string,
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    }
    created = client.mutate("POST", "/appStoreVersions", body)
    return created["data"]


def index_by_locale(items: list[dict], attr: str = "locale") -> dict[str, dict]:
    return {item["attributes"][attr]: item for item in items}


def ensure_version_localization(client: ASCClient, version_id: str, locale: str) -> dict:
    payload = client.get_json(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    existing = index_by_locale(payload.get("data", []))
    if locale in existing:
        return existing[locale]

    print(f"  + create version localization: {locale}")
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": locale},
            "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
            },
        }
    }
    created = client.mutate("POST", "/appStoreVersionLocalizations", body)
    return created["data"]


def ensure_info_localization(client: ASCClient, app_info_id: str, locale: str, name: str) -> dict | None:
    payload = client.get_json(f"/appInfos/{app_info_id}/appInfoLocalizations")
    existing = index_by_locale(payload.get("data", []))
    if locale in existing:
        return existing[locale]

    print(f"  + create app info localization: {locale}")
    body = {
        "data": {
            "type": "appInfoLocalizations",
            "attributes": {"locale": locale, "name": name},
            "relationships": {
                "appInfo": {"data": {"type": "appInfos", "id": app_info_id}},
            },
        }
    }
    try:
        created = client.mutate("POST", "/appInfoLocalizations", body)
        return created["data"]
    except RuntimeError:
        print(f"  ! app info localization {locale} could not be created via API")
        print("    → App Store Connect → アプリ情報 → 言語を追加 から一度だけ手動追加が必要な場合があります。")
        return None


def patch_info_subtitle(client: ASCClient, info_loc_id: str, subtitle: str) -> None:
    body = {
        "data": {
            "type": "appInfoLocalizations",
            "id": info_loc_id,
            "attributes": {"subtitle": subtitle},
        }
    }
    try:
        client.mutate("PATCH", f"/appInfoLocalizations/{info_loc_id}", body)
        print("  ✓ subtitle")
    except RuntimeError:
        print("  ! subtitle skipped (API 更新不可の状態の可能性)")
        print("    → サブタイトルは App Store Connect UI から設定してください。")


def upload_metadata_for_locale(
    client: ASCClient,
    meta: dict[str, Any],
    app_info_id: str,
    version_id: str,
) -> None:
    locale = meta["locale"]
    folder = meta["_folder"]
    print(f"\n[metadata] {folder} ({locale})")

    info_loc = ensure_info_localization(client, app_info_id, locale, meta.get("app_name", "MioCam"))
    if info_loc and meta.get("subtitle"):
        patch_info_subtitle(client, info_loc["id"], meta["subtitle"])

    version_loc = ensure_version_localization(client, version_id, locale)
    attrs = {
        "description": meta["description"],
        "keywords": meta["keywords"],
        "promotionalText": meta["promotional_text"],
        "whatsNew": meta["whats_new"],
    }
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": version_loc["id"],
            "attributes": attrs,
        }
    }
    client.mutate("PATCH", f"/appStoreVersionLocalizations/{version_loc['id']}", body)
    print("  ✓ description / keywords / promotional text / what's new")


def find_appmockup_dir(folder: str) -> Path | None:
    locale_dir = SCREENSHOTS_DIR / folder
    if not locale_dir.exists():
        return None
    matches = sorted(
        p for p in locale_dir.iterdir()
        if p.is_dir() and p.name.startswith("AppMockUp Screenshots")
    )
    return matches[0] if matches else None


def screenshot_sort_key(path: Path) -> tuple[int, str]:
    match = re.search(r"Screenshot\s+(\d+)", path.name, re.IGNORECASE)
    if match:
        return (int(match.group(1)), path.name)
    return (999, path.name)


def prepare_png_bytes(image_path: Path) -> bytes:
    raw = image_path.read_bytes()
    if Image is None:
        return raw
    with Image.open(image_path) as img:
        if img.mode == "RGBA":
            background = Image.new("RGB", img.size, (255, 248, 240))
            background.paste(img, mask=img.split()[3])
            buffer = io.BytesIO()
            background.save(buffer, format="PNG", optimize=True)
            return buffer.getvalue()
        if img.mode != "RGB":
            buffer = io.BytesIO()
            img.convert("RGB").save(buffer, format="PNG", optimize=True)
            return buffer.getvalue()
    return raw


def list_screenshot_files(folder: str) -> list[Path]:
    mockup_dir = find_appmockup_dir(folder)
    if mockup_dir:
        device_folder, _ = MOCKUP_DEVICE_FOLDERS[0]
        device_dir = mockup_dir / device_folder
        files = sorted(device_dir.glob("*.png"), key=screenshot_sort_key)
        if files:
            return files

    locale_dir = SCREENSHOTS_DIR / folder
    if not locale_dir.exists():
        raise FileNotFoundError(f"Screenshot directory not found: {locale_dir}")
    files = sorted(locale_dir.glob("*.png"), key=screenshot_sort_key)
    if not files:
        raise FileNotFoundError(f"No screenshots in {locale_dir}")
    return files


def list_mockup_device_screenshots(mockup_dir: Path, device_folder: str) -> list[Path]:
    device_dir = mockup_dir / device_folder
    if not device_dir.exists():
        return []
    return sorted(device_dir.glob("*.png"), key=screenshot_sort_key)


def ensure_screenshot_set(client: ASCClient, version_loc_id: str, display_type: str) -> dict:
    payload = client.get_json(
        f"/appStoreVersionLocalizations/{version_loc_id}/appScreenshotSets",
        params={"filter[screenshotDisplayType]": display_type},
    )
    sets = payload.get("data", [])
    if sets:
        return sets[0]

    body = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": version_loc_id},
                },
            },
        }
    }
    created = client.mutate("POST", "/appScreenshotSets", body)
    return created["data"]


def delete_existing_screenshots(client: ASCClient, screenshot_set_id: str) -> None:
    payload = client.get_json(f"/appScreenshotSets/{screenshot_set_id}/appScreenshots")
    for item in payload.get("data", []):
        client.mutate(
            "DELETE",
            f"/appScreenshots/{item['id']}",
            {},
            ignore_status={404},
        )


def upload_screenshot(client: ASCClient, screenshot_set_id: str, image_path: Path) -> None:
    data = prepare_png_bytes(image_path)
    checksum = hashlib.md5(data).hexdigest()
    reserve_body = {
        "data": {
            "type": "appScreenshots",
            "attributes": {
                "fileName": image_path.name,
                "fileSize": len(data),
            },
            "relationships": {
                "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": screenshot_set_id}},
            },
        }
    }
    reserved = client.mutate("POST", "/appScreenshots", reserve_body)
    shot = reserved["data"]
    shot_id = shot["id"]

    for op in shot["attributes"].get("uploadOperations", []):
        headers = {header["name"]: header["value"] for header in op.get("requestHeaders", [])}
        chunk = data[op["offset"] : op["offset"] + op["length"]]
        if client.dry_run:
            continue
        upload_response = requests.request(
            op["method"],
            op["url"],
            headers=headers,
            data=chunk,
            timeout=120,
        )
        if not upload_response.ok:
            raise RuntimeError(
                f"Screenshot upload chunk failed ({upload_response.status_code}): "
                f"{upload_response.text[:300]}"
            )

    commit_body = {
        "data": {
            "type": "appScreenshots",
            "id": shot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": checksum,
            },
        }
    }
    client.mutate("PATCH", f"/appScreenshots/{shot_id}", commit_body)


def upload_screenshots_for_locale(
    client: ASCClient,
    meta: dict[str, Any],
    version_id: str,
) -> None:
    locale = meta["locale"]
    folder = meta["_folder"]
    print(f"\n[screenshots] {folder} ({locale})")

    version_loc = ensure_version_localization(client, version_id, locale)
    mockup_dir = find_appmockup_dir(folder)

    if mockup_dir:
        print(f"  source: {mockup_dir.name}")
        for device_folder, display_type in MOCKUP_DEVICE_FOLDERS:
            files = list_mockup_device_screenshots(mockup_dir, device_folder)
            if not files:
                print(f"  - skip {device_folder} (no files)")
                continue
            print(f"  device: {device_folder} ({display_type})")
            screenshot_set = ensure_screenshot_set(client, version_loc["id"], display_type)
            delete_existing_screenshots(client, screenshot_set["id"])
            for index, image_path in enumerate(files, start=1):
                upload_screenshot(client, screenshot_set["id"], image_path)
                print(f"    ✓ {index}/{len(files)} {image_path.name}")
        return

    screenshot_set = ensure_screenshot_set(client, version_loc["id"], MOCKUP_DEVICE_FOLDERS[0][1])
    delete_existing_screenshots(client, screenshot_set["id"])
    files = list_screenshot_files(folder)
    for index, image_path in enumerate(files, start=1):
        upload_screenshot(client, screenshot_set["id"], image_path)
        print(f"  ✓ {index}/{len(files)} {image_path.name}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Upload App Store metadata and screenshots via API")
    parser.add_argument("--version", default=None, help="Marketing version (default: VERSION file)")
    parser.add_argument("--env-file", default=str(DEFAULT_ENV), help="Path to .appstore.env")
    parser.add_argument("--create-version", action="store_true", help="Create version if missing")
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--screenshots-only", action="store_true")
    parser.add_argument("--locale", nargs="*", help="Limit to locale folders (ja, en, es, pt-BR, ko)")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    version_string = args.version or (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    locale_filter = set(args.locale) if args.locale else None
    upload_metadata = not args.screenshots_only
    upload_screenshots = not args.metadata_only

    env = load_env(Path(args.env_file))
    client = ASCClient(
        key_id=env["ASC_KEY_ID"],
        issuer_id=env["ASC_ISSUER_ID"],
        key_path=Path(env["ASC_KEY_PATH"]),
        dry_run=args.dry_run,
    )
    metadata_items = load_metadata(locale_filter)

    print(f"==> App Store Connect upload for {BUNDLE_ID} v{version_string}")
    if args.dry_run:
        print("==> DRY RUN (no changes will be sent)")

    app = find_app(client)
    app_info = find_app_info(client, app["id"])
    version = find_or_create_version(client, app["id"], version_string, args.create_version)

    state = version["attributes"].get("appStoreState")
    if state not in EDITABLE_VERSION_STATES and not args.dry_run:
        print(f"WARNING: version state is {state}. Metadata/screenshot updates may fail.")

    if upload_metadata:
        print("\n==> Uploading metadata")
        for meta in metadata_items:
            upload_metadata_for_locale(client, meta, app_info["id"], version["id"])

    if upload_screenshots:
        print("\n==> Uploading screenshots")
        for meta in metadata_items:
            upload_screenshots_for_locale(client, meta, version["id"])

    print("\n✅ Done.")
    print("   App Store Connect → MioCam → バージョン → 各言語の内容を確認してください。")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
