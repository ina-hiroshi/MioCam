#!/usr/bin/env python3
"""App Store 6.7\" マーケティングスクリーンショット生成スクリプト.

使い方:
  python3 appstore/generate_marketing_screenshots.py

Xcode Preview またはシミュレータで撮影したアプリ画面 PNG を
appstore/marketing/screens/ に置くと、キャッチコピー付きの
1290×2796 px 画像を appstore/marketing/output/ に出力します。

screens/ が空の場合は、モック映像素材のみプレースホルダーを生成します。
"""

from __future__ import annotations

import json
import textwrap
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError:
    raise SystemExit(
        "Pillow が必要です: pip3 install Pillow"
    )

ROOT = Path(__file__).resolve().parents[1]
MARKETING = ROOT / "appstore" / "marketing"
SCREENS_DIR = MARKETING / "screens"
OUTPUT_DIR = MARKETING / "output"
ASSETS_DIR = ROOT / "MioCam" / "Resources" / "Assets.xcassets"

# App Store 6.7" Display (iPhone 15/16 Pro Max)
CANVAS_W = 1290
CANVAS_H = 2796

# MioCam ブランドカラー
MIO_PRIMARY = (255, 248, 240)      # #FFF8F0
MIO_ACCENT = (255, 159, 106)       # #FF9F6A
MIO_ACCENT_SUB = (126, 200, 200)   # #7EC8C8
MIO_TEXT = (45, 45, 45)            # #2D2D2D
MIO_TEXT_MUTED = (120, 120, 120)

SCREENSHOTS = [
    {
        "id": "01_live_nursery",
        "screen": "live_nursery.png",
        "headline": "どこからでも\n赤ちゃんをリアルタイムで見守る",
        "subheadline": "寝室・リビングをスマホからライブ確認",
        "feed_asset": "AppStoreMockFeedNursery.imageset/AppStoreMockFeedNursery.png",
    },
    {
        "id": "02_camera_qr",
        "screen": "camera_qr.png",
        "headline": "古い iPhone / iPad を\nカメラとして再利用",
        "subheadline": "QRコードですぐにペアリング",
        "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
    },
    {
        "id": "03_monitor_list",
        "screen": "monitor_list.png",
        "headline": "複数部屋のカメラを\n一元管理",
        "subheadline": "オンライン状態をひと目で確認",
        "feed_asset": None,
    },
    {
        "id": "04_live_livingroom",
        "screen": "live_livingroom.png",
        "headline": "マイク音声も\nワンタップで ON",
        "subheadline": "プッシュ・トゥ・トークで双方向コミュニケーション",
        "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
    },
    {
        "id": "05_role_selection",
        "screen": "role_selection.png",
        "headline": "お手持ちの端末を\n世界一シンプルな見守り窓に",
        "subheadline": "カメラとモニターを自由に使い分け",
        "feed_asset": None,
    },
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", 0),
        ("/System/Library/Fonts/Hiragino Sans GB.ttc", 1 if bold else 0),
        ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6 if bold else 0),
        ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0),
    ]
    for path, index in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size, index=index)
            except OSError:
                continue
    return ImageFont.load_default()


def rounded_rect(draw: ImageDraw.ImageDraw, xy, radius: int, fill):
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def draw_headline_block(
    draw: ImageDraw.ImageDraw,
    headline: str,
    subheadline: str,
    y_start: int,
) -> int:
    title_font = load_font(72, bold=True)
    sub_font = load_font(36)

    lines = headline.split("\n")
    y = y_start
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=title_font)
        tw = bbox[2] - bbox[0]
        x = (CANVAS_W - tw) // 2
        draw.text((x, y), line, fill=MIO_TEXT, font=title_font)
        y += 88

    sub_bbox = draw.textbbox((0, 0), subheadline, font=sub_font)
    sub_w = sub_bbox[2] - sub_bbox[0]
    draw.text(
        ((CANVAS_W - sub_w) // 2, y + 16),
        subheadline,
        fill=MIO_TEXT_MUTED,
        font=sub_font,
    )
    return y + 80


def create_phone_frame(content: Image.Image) -> Image.Image:
    """アプリ画面を iPhone 風フレームに配置."""
    phone_w = 980
    phone_h = int(phone_w * (CANVAS_H * 0.62) / CANVAS_W)
    margin_top = 520

    frame = Image.new("RGBA", (CANVAS_W, phone_h + 40), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)

    # 端末シャドウ
    shadow = Image.new("RGBA", (phone_w + 40, phone_h + 40), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((20, 20, phone_w + 20, phone_h + 20), radius=64, fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(16))
    frame.paste(shadow, ((CANVAS_W - phone_w) // 2 - 20, 0), shadow)

    # 端末本体
    x0 = (CANVAS_W - phone_w) // 2
    rounded_rect(draw, (x0, 10, x0 + phone_w, 10 + phone_h), 56, (20, 20, 20, 255))

    # コンテンツをクロップしてフィット
    content = content.convert("RGBA")
    cw, ch = content.size
    scale = min(phone_w / cw, (phone_h - 20) / ch)
    nw, nh = int(cw * scale), int(ch * scale)
    resized = content.resize((nw, nh), Image.Resampling.LANCZOS)
    px = x0 + (phone_w - nw) // 2
    py = 10 + (phone_h - nh) // 2
    frame.paste(resized, (px, py), resized if resized.mode == "RGBA" else None)

    # Dynamic Island
    island_w, island_h = 180, 44
    ix = x0 + (phone_w - island_w) // 2
    rounded_rect(draw, (ix, 28, ix + island_w, 28 + island_h), 22, (0, 0, 0, 255))

    return frame


def build_live_placeholder(feed_path: Path) -> Image.Image:
    """ライブ画面プレースホルダー（モック映像 + UI 簡易版）."""
    w, h = 1179, 2556
    img = Image.new("RGB", (w, h), (0, 0, 0))
    draw = ImageDraw.Draw(img)

    if feed_path.exists():
        feed = Image.open(feed_path).convert("RGB")
        fw, fh = feed.size
        scale = max(w / fw, h / fh)
        nw, nh = int(fw * scale), int(fh * scale)
        feed = feed.resize((nw, nh), Image.Resampling.LANCZOS)
        ox = (nw - w) // 2
        oy = (nh - h) // 2
        img.paste(feed.crop((ox, oy, ox + w, oy + h)))

    def pill(x, y, pw, ph, alpha=160):
        overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.rounded_rectangle((x, y, x + pw, y + ph), radius=ph // 2, fill=(255, 255, 255, alpha))
        return Image.alpha_composite(img.convert("RGBA"), overlay)

    img = pill(40, 120, 140, 36)
    draw = ImageDraw.Draw(img)
    draw.ellipse((52, 130, 64, 142), fill=(76, 175, 80))
    font = load_font(24)
    draw.text((72, 126), "パパ", fill=(255, 255, 255), font=font)

    img = pill(w - 160, 120, 120, 36)
    draw = ImageDraw.Draw(img)
    draw.text((w - 148, 126), "100%", fill=(255, 255, 255), font=font)

    # 下部コントロール
    for cx in [80, w // 2 - 30, w - 80]:
        overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.ellipse((cx - 28, h - 180, cx + 28, h - 124), fill=(255, 255, 255, 140))
        img = Image.alpha_composite(img, overlay)

    mic_r = 36
    mx = w // 2
    my = h - 152
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse((mx - mic_r, my - mic_r, mx + mic_r, my + mic_r), outline=(255, 255, 255, 180), width=3)
    img = Image.alpha_composite(img, overlay)

    return img.convert("RGB")


def build_list_placeholder() -> Image.Image:
    w, h = 1179, 2556
    img = Image.new("RGB", (w, h), MIO_PRIMARY)
    draw = ImageDraw.Draw(img)

    title_font = load_font(40, bold=True)
    draw.text((w // 2 - 60, 100), "モニター", fill=MIO_TEXT, font=title_font)

    card_font = load_font(34)
    sub_font = load_font(26)
    cameras = [("寝室のカメラ", "1台接続中"), ("リビングのカメラ", "オンライン")]

    y = 220
    for name, status in cameras:
        rounded_rect(draw, (60, y, w - 60, y + 120), 28, (255, 255, 255))
        draw.ellipse((90, y + 48, 102, y + 60), fill=(76, 175, 80))
        draw.text((120, y + 28), name, fill=MIO_TEXT, font=card_font)
        draw.text((120, y + 72), status, fill=(76, 175, 80), font=sub_font)
        y += 150

    return img


def build_role_placeholder() -> Image.Image:
    w, h = 1179, 2556
    img = Image.new("RGB", (w, h), MIO_PRIMARY)
    draw = ImageDraw.Draw(img)

    title_font = load_font(52, bold=True)
    body_font = load_font(30)
    btn_font = load_font(32, bold=True)

    draw.text((w // 2 - 120, 380), "MioCam", fill=MIO_TEXT, font=title_font)
    draw.text((w // 2 - 280, 460), "このデバイスの役割を選んでください", fill=MIO_TEXT_MUTED, font=body_font)

    rounded_rect(draw, (80, 700, w - 80, 860), 28, MIO_ACCENT)
    draw.text((140, 760), "カメラ", fill=(255, 255, 255), font=btn_font)

    rounded_rect(draw, (80, 900, w - 80, 1060), 28, MIO_ACCENT_SUB)
    draw.text((140, 960), "モニター", fill=(255, 255, 255), font=btn_font)

    return img


def resolve_screen_image(spec: dict) -> Image.Image:
    screen_path = SCREENS_DIR / spec["screen"]
    if screen_path.exists():
        return Image.open(screen_path).convert("RGB")

    feed_asset = spec.get("feed_asset")
    if feed_asset and "Nursery" in feed_asset:
        feed = ASSETS_DIR / feed_asset
        return build_live_placeholder(feed)
    if feed_asset and "LivingRoom" in feed_asset:
        feed = ASSETS_DIR / feed_asset
        if "02_camera" in spec["id"]:
            return build_live_placeholder(feed)  # QR overlay は簡易版
        return build_live_placeholder(feed)
    if "monitor_list" in spec["id"]:
        return build_list_placeholder()
    if "role_selection" in spec["id"]:
        return build_role_placeholder()
    return build_list_placeholder()


def compose_marketing_screenshot(spec: dict) -> Image.Image:
    canvas = Image.new("RGB", (CANVAS_W, CANVAS_H), MIO_PRIMARY)
    draw = ImageDraw.Draw(canvas)

    # 上部アクセント装飾
    accent = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(accent)
    ad.ellipse((-200, -400, 600, 400), fill=(*MIO_ACCENT, 30))
    ad.ellipse((CANVAS_W - 400, 100, CANVAS_W + 200, 700), fill=(*MIO_ACCENT_SUB, 25))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), accent).convert("RGB")
    draw = ImageDraw.Draw(canvas)

    draw_headline_block(draw, spec["headline"], spec["subheadline"], y_start=180)

    screen = resolve_screen_image(spec)
    phone = create_phone_frame(screen)
    canvas.paste(phone, (0, 400), phone)

    return canvas


def main():
    SCREENS_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    manifest = []
    for spec in SCREENSHOTS:
        out_path = OUTPUT_DIR / f"{spec['id']}_{spec['screen'].replace('.png', '')}_1290x2796.png"
        img = compose_marketing_screenshot(spec)
        img.save(out_path, "PNG", optimize=True)
        manifest.append({"id": spec["id"], "output": str(out_path.relative_to(ROOT))})
        print(f"✓ {out_path.name}")

    manifest_path = OUTPUT_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n{len(manifest)} 枚を {OUTPUT_DIR} に出力しました。")
    print("Xcode Preview から高精細キャプチャする場合は AppStoreMockScreens.swift の Preview を使用してください。")


if __name__ == "__main__":
    main()
