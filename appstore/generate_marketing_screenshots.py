#!/usr/bin/env python3
"""App Store 6.7\" マーケティングスクリーンショット生成（5言語対応）.

使い方:
  python3 appstore/generate_marketing_screenshots.py           # 全言語
  python3 appstore/generate_marketing_screenshots.py --locale ja
  python3 appstore/generate_marketing_screenshots.py --locale en es ko

Xcode Preview またはシミュレータで撮影したアプリ画面 PNG を
appstore/marketing/screens/ に置くと、キャッチコピー付きの
1290×2796 px 画像を appstore/marketing/localized/<locale>/ に出力します。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError:
    raise SystemExit("Pillow が必要です: pip3 install Pillow")

ROOT = Path(__file__).resolve().parents[1]
MARKETING = ROOT / "appstore" / "marketing"
SCREENS_DIR = MARKETING / "screens"
LOCALIZED_DIR = MARKETING / "localized"
ASSETS_DIR = ROOT / "MioCam" / "Resources" / "Assets.xcassets"

CANVAS_W = 1290
CANVAS_H = 2796

MIO_PRIMARY = (255, 248, 240)
MIO_ACCENT = (255, 159, 106)
MIO_ACCENT_SUB = (126, 200, 200)
MIO_TEXT = (45, 45, 45)
MIO_TEXT_MUTED = (120, 120, 120)

LOCALE_UI = {
    "ja": {
        "connected_user": "パパ",
        "monitor_title": "モニター",
        "cameras": [("寝室のカメラ", "1台接続中"), ("リビングのカメラ", "オンライン")],
        "select_role": "このデバイスの役割を選んでください",
        "camera_btn": "カメラ",
        "monitor_btn": "モニター",
    },
    "en": {
        "connected_user": "Dad",
        "monitor_title": "Monitor",
        "cameras": [("Nursery Camera", "1 connected"), ("Living Room Camera", "Online")],
        "select_role": "Select this device's role",
        "camera_btn": "Camera",
        "monitor_btn": "Monitor",
    },
    "es": {
        "connected_user": "Papá",
        "monitor_title": "Monitor",
        "cameras": [("Cámara del dormitorio", "1 conectado"), ("Cámara del salón", "En línea")],
        "select_role": "Seleccione el rol de este dispositivo",
        "camera_btn": "Cámara",
        "monitor_btn": "Monitor",
    },
    "pt-BR": {
        "connected_user": "Papai",
        "monitor_title": "Monitor",
        "cameras": [("Câmera do quarto", "1 conectado"), ("Câmera da sala", "Online")],
        "select_role": "Selecione a função deste dispositivo",
        "camera_btn": "Câmera",
        "monitor_btn": "Monitor",
    },
    "ko": {
        "connected_user": "아빠",
        "monitor_title": "모니터",
        "cameras": [("아이 방 카메라", "1대 연결됨"), ("거실 카메라", "온라인")],
        "select_role": "이 기기의 역할을 선택하세요",
        "camera_btn": "카메라",
        "monitor_btn": "모니터",
    },
}

LOCALE_SCREENSHOTS = {
    "ja": [
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
    ],
    "en": [
        {
            "id": "01_live_nursery",
            "screen": "live_nursery.png",
            "headline": "Watch your baby\nlive from anywhere",
            "subheadline": "Check nursery and living room on your phone",
            "feed_asset": "AppStoreMockFeedNursery.imageset/AppStoreMockFeedNursery.png",
        },
        {
            "id": "02_camera_qr",
            "screen": "camera_qr.png",
            "headline": "Repurpose an old\niPhone or iPad as a camera",
            "subheadline": "Pair instantly with a QR code",
            "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
        },
        {
            "id": "03_monitor_list",
            "screen": "monitor_list.png",
            "headline": "Manage cameras\nacross every room",
            "subheadline": "See online status at a glance",
            "feed_asset": None,
        },
        {
            "id": "04_live_livingroom",
            "screen": "live_livingroom.png",
            "headline": "One tap to hear\nmicrophone audio",
            "subheadline": "Push-to-talk for two-way communication",
            "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
        },
        {
            "id": "05_role_selection",
            "screen": "role_selection.png",
            "headline": "Turn your device into\nthe simplest care window",
            "subheadline": "Switch freely between Camera and Monitor",
            "feed_asset": None,
        },
    ],
    "es": [
        {
            "id": "01_live_nursery",
            "screen": "live_nursery.png",
            "headline": "Vigile a su bebé\nen vivo desde cualquier lugar",
            "subheadline": "Revise dormitorio y salón desde el móvil",
            "feed_asset": "AppStoreMockFeedNursery.imageset/AppStoreMockFeedNursery.png",
        },
        {
            "id": "02_camera_qr",
            "screen": "camera_qr.png",
            "headline": "Reutilice un iPhone\no iPad antiguo como cámara",
            "subheadline": "Empareje al instante con código QR",
            "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
        },
        {
            "id": "03_monitor_list",
            "screen": "monitor_list.png",
            "headline": "Gestione cámaras\nde varias habitaciones",
            "subheadline": "Vea el estado en línea de un vistazo",
            "feed_asset": None,
        },
        {
            "id": "04_live_livingroom",
            "screen": "live_livingroom.png",
            "headline": "Audio del micrófono\ncon un solo toque",
            "subheadline": "Pulsar para hablar y comunicarse en ambos sentidos",
            "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
        },
        {
            "id": "05_role_selection",
            "screen": "role_selection.png",
            "headline": "Convierta su dispositivo\nen la ventana de cuidado más simple",
            "subheadline": "Use Cámara y Monitor a su manera",
            "feed_asset": None,
        },
    ],
    "pt-BR": [
        {
            "id": "01_live_nursery",
            "screen": "live_nursery.png",
            "headline": "Monitore seu bebê\nao vivo de qualquer lugar",
            "subheadline": "Confira quarto e sala pelo celular",
            "feed_asset": "AppStoreMockFeedNursery.imageset/AppStoreMockFeedNursery.png",
        },
        {
            "id": "02_camera_qr",
            "screen": "camera_qr.png",
            "headline": "Reutilize um iPhone\nou iPad antigo como câmera",
            "subheadline": "Emparelhe na hora com QR code",
            "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
        },
        {
            "id": "03_monitor_list",
            "screen": "monitor_list.png",
            "headline": "Gerencie câmeras\nde vários cômodos",
            "subheadline": "Veja o status online de relance",
            "feed_asset": None,
        },
        {
            "id": "04_live_livingroom",
            "screen": "live_livingroom.png",
            "headline": "Áudio do microfone\ncom um toque",
            "subheadline": "Push-to-talk para comunicação bidirecional",
            "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
        },
        {
            "id": "05_role_selection",
            "screen": "role_selection.png",
            "headline": "Transforme seu dispositivo\nna janela de cuidado mais simples",
            "subheadline": "Alterne livremente entre Câmera e Monitor",
            "feed_asset": None,
        },
    ],
    "ko": [
        {
            "id": "01_live_nursery",
            "screen": "live_nursery.png",
            "headline": "어디서든\n아기를 실시간으로 지켜보세요",
            "subheadline": "아이 방·거실을 스마트폰으로 라이브 확인",
            "feed_asset": "AppStoreMockFeedNursery.imageset/AppStoreMockFeedNursery.png",
        },
        {
            "id": "02_camera_qr",
            "screen": "camera_qr.png",
            "headline": "오래된 iPhone·iPad를\n카메라로 재활용",
            "subheadline": "QR 코드로 즉시 페어링",
            "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
        },
        {
            "id": "03_monitor_list",
            "screen": "monitor_list.png",
            "headline": "여러 방의 카메라를\n한곳에서 관리",
            "subheadline": "온라인 상태를 한눈에 확인",
            "feed_asset": None,
        },
        {
            "id": "04_live_livingroom",
            "screen": "live_livingroom.png",
            "headline": "마이크 음성도\n원터치로 ON",
            "subheadline": "푸시 투 토크로 양방향 소통",
            "feed_asset": "AppStoreMockFeedLivingRoom.imageset/AppStoreMockFeedLivingRoom.png",
        },
        {
            "id": "05_role_selection",
            "screen": "role_selection.png",
            "headline": "기기를 세계에서\n가장 간단한 케어 창으로",
            "subheadline": "카메라와 모니터를 자유롭게 전환",
            "feed_asset": None,
        },
    ],
}


def load_font(size: int, bold: bool = False, locale: str = "ja") -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", 0),
        ("/System/Library/Fonts/Hiragino Sans GB.ttc", 1 if bold else 0),
        ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6 if bold else 0),
        ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0),
    ]
    if locale in ("ja",):
        candidates.insert(0, ("/System/Library/Fonts/Hiragino Sans GB.ttc", 2 if bold else 0))
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
    locale: str,
) -> int:
    title_font = load_font(68 if locale == "en" else 72, bold=True, locale=locale)
    sub_font = load_font(34 if locale in ("es", "pt-BR") else 36, locale=locale)

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
    phone_w = 980
    phone_h = int(phone_w * (CANVAS_H * 0.62) / CANVAS_W)

    frame = Image.new("RGBA", (CANVAS_W, phone_h + 40), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)

    shadow = Image.new("RGBA", (phone_w + 40, phone_h + 40), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((20, 20, phone_w + 20, phone_h + 20), radius=64, fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(16))
    frame.paste(shadow, ((CANVAS_W - phone_w) // 2 - 20, 0), shadow)

    x0 = (CANVAS_W - phone_w) // 2
    rounded_rect(draw, (x0, 10, x0 + phone_w, 10 + phone_h), 56, (20, 20, 20, 255))

    content = content.convert("RGBA")
    cw, ch = content.size
    scale = min(phone_w / cw, (phone_h - 20) / ch)
    nw, nh = int(cw * scale), int(ch * scale)
    resized = content.resize((nw, nh), Image.Resampling.LANCZOS)
    px = x0 + (phone_w - nw) // 2
    py = 10 + (phone_h - nh) // 2
    frame.paste(resized, (px, py), resized if resized.mode == "RGBA" else None)

    island_w, island_h = 180, 44
    ix = x0 + (phone_w - island_w) // 2
    rounded_rect(draw, (ix, 28, ix + island_w, 28 + island_h), 22, (0, 0, 0, 255))

    return frame


def build_live_placeholder(feed_path: Path, locale: str) -> Image.Image:
    ui = LOCALE_UI[locale]
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

    font = load_font(24, locale=locale)
    user = ui["connected_user"]
    user_w = draw.textbbox((0, 0), user, font=font)[2] + 40
    img = pill(40, 120, max(140, user_w), 36)
    draw = ImageDraw.Draw(img)
    draw.ellipse((52, 130, 64, 142), fill=(76, 175, 80))
    draw.text((72, 126), user, fill=(255, 255, 255), font=font)

    img = pill(w - 160, 120, 120, 36)
    draw = ImageDraw.Draw(img)
    draw.text((w - 148, 126), "100%", fill=(255, 255, 255), font=font)

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


def build_list_placeholder(locale: str) -> Image.Image:
    ui = LOCALE_UI[locale]
    w, h = 1179, 2556
    img = Image.new("RGB", (w, h), MIO_PRIMARY)
    draw = ImageDraw.Draw(img)

    title_font = load_font(40, bold=True, locale=locale)
    title = ui["monitor_title"]
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    draw.text(((w - (title_bbox[2] - title_bbox[0])) // 2, 100), title, fill=MIO_TEXT, font=title_font)

    card_font = load_font(32 if locale in ("es", "pt-BR") else 34, locale=locale)
    sub_font = load_font(24 if locale in ("es", "pt-BR") else 26, locale=locale)

    y = 220
    for name, status in ui["cameras"]:
        rounded_rect(draw, (60, y, w - 60, y + 120), 28, (255, 255, 255))
        draw.ellipse((90, y + 48, 102, y + 60), fill=(76, 175, 80))
        draw.text((120, y + 28), name, fill=MIO_TEXT, font=card_font)
        draw.text((120, y + 72), status, fill=(76, 175, 80), font=sub_font)
        y += 150

    return img


def build_role_placeholder(locale: str) -> Image.Image:
    ui = LOCALE_UI[locale]
    w, h = 1179, 2556
    img = Image.new("RGB", (w, h), MIO_PRIMARY)
    draw = ImageDraw.Draw(img)

    title_font = load_font(52, bold=True, locale=locale)
    body_font = load_font(28 if locale in ("es", "pt-BR") else 30, locale=locale)
    btn_font = load_font(32, bold=True, locale=locale)

    draw.text((w // 2 - 120, 380), "MioCam", fill=MIO_TEXT, font=title_font)
    role = ui["select_role"]
    role_bbox = draw.textbbox((0, 0), role, font=body_font)
    draw.text(((w - (role_bbox[2] - role_bbox[0])) // 2, 460), role, fill=MIO_TEXT_MUTED, font=body_font)

    rounded_rect(draw, (80, 700, w - 80, 860), 28, MIO_ACCENT)
    draw.text((140, 760), ui["camera_btn"], fill=(255, 255, 255), font=btn_font)

    rounded_rect(draw, (80, 900, w - 80, 1060), 28, MIO_ACCENT_SUB)
    draw.text((140, 960), ui["monitor_btn"], fill=(255, 255, 255), font=btn_font)

    return img


def resolve_screen_image(spec: dict, locale: str) -> Image.Image:
    screen_path = SCREENS_DIR / spec["screen"]
    if screen_path.exists() and locale == "ja":
        return Image.open(screen_path).convert("RGB")

    feed_asset = spec.get("feed_asset")
    if feed_asset and "Nursery" in feed_asset:
        feed = ASSETS_DIR / feed_asset
        return build_live_placeholder(feed, locale)
    if feed_asset and "LivingRoom" in feed_asset:
        feed = ASSETS_DIR / feed_asset
        return build_live_placeholder(feed, locale)
    if "monitor_list" in spec["id"]:
        return build_list_placeholder(locale)
    if "role_selection" in spec["id"]:
        return build_role_placeholder(locale)
    return build_list_placeholder(locale)


def compose_marketing_screenshot(spec: dict, locale: str) -> Image.Image:
    canvas = Image.new("RGB", (CANVAS_W, CANVAS_H), MIO_PRIMARY)
    draw = ImageDraw.Draw(canvas)

    accent = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(accent)
    ad.ellipse((-200, -400, 600, 400), fill=(*MIO_ACCENT, 30))
    ad.ellipse((CANVAS_W - 400, 100, CANVAS_W + 200, 700), fill=(*MIO_ACCENT_SUB, 25))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), accent).convert("RGB")
    draw = ImageDraw.Draw(canvas)

    draw_headline_block(draw, spec["headline"], spec["subheadline"], y_start=180, locale=locale)

    screen = resolve_screen_image(spec, locale)
    phone = create_phone_frame(screen)
    canvas.paste(phone, (0, 400), phone)

    return canvas


def generate_locale(locale: str) -> list[dict]:
    if locale not in LOCALE_SCREENSHOTS:
        raise ValueError(f"Unknown locale: {locale}")

    out_dir = LOCALIZED_DIR / locale
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = []

    for i, spec in enumerate(LOCALE_SCREENSHOTS[locale], start=1):
        out_name = f"{i:02d}_{spec['id'].split('_', 1)[1]}_1290x2796.png"
        out_path = out_dir / out_name
        img = compose_marketing_screenshot(spec, locale)
        img.save(out_path, "PNG", optimize=True)
        rel = str(out_path.relative_to(ROOT))
        manifest.append({"id": spec["id"], "locale": locale, "output": rel})
        print(f"✓ [{locale}] {out_name}")

    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description="Generate localized App Store marketing screenshots")
    parser.add_argument(
        "--locale",
        nargs="*",
        choices=list(LOCALE_SCREENSHOTS.keys()),
        default=list(LOCALE_SCREENSHOTS.keys()),
        help="Locales to generate (default: all)",
    )
    args = parser.parse_args()

    SCREENS_DIR.mkdir(parents=True, exist_ok=True)
    LOCALIZED_DIR.mkdir(parents=True, exist_ok=True)

    all_manifest = []
    for locale in args.locale:
        all_manifest.extend(generate_locale(locale))

    summary_path = LOCALIZED_DIR / "manifest.json"
    summary_path.write_text(json.dumps(all_manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n{len(all_manifest)} 枚を {LOCALIZED_DIR} に出力しました。")


if __name__ == "__main__":
    main()
