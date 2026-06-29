# MioCam

見守りカメラアプリ - 「iPhoneを、世界一シンプルな見守り窓に。」

## プロジェクト概要

MioCamは、古いiPhoneを再利用してベビーモニター/ペットカメラとして活用できるアプリです。

### 主な特徴

- **設定不要**: QRコードペアリングで簡単セットアップ
- **省エネ設計**: カメラ側のブラックアウトモード
- **エッジAI検知**: 意味のある通知のみを提供
- **P2P通信**: サーバーに映像を保存しない

## 技術スタック

- **言語**: Swift
- **通信**: WebRTC (GoogleWebRTC)
- **検知**: Vision Framework / Core ML
- **バックエンド**: Firebase (Cloud Firestore / Functions)

## セットアップ

### 前提条件

- Xcode 14.0以上
- iOS 15.0以上をターゲット
- Apple Developer Programへの加入（年額$99）
- Firebaseプロジェクトの作成済み

### セットアップ手順

1. リポジトリをクローン
   ```bash
   git clone https://github.com/ina-hiroshi/MioCam.git
   cd MioCam
   ```

2. Firebase設定ファイルを配置
   - `GoogleService-Info.plist` を `MioCam/MioCam/Resources/` ディレクトリに配置

3. Xcodeでプロジェクトを開く
   ```bash
   open MioCam.xcodeproj
   ```

4. 依存関係をインストール
   - Swift Package Managerを使用（Xcodeで自動解決）

5. ビルド&実行
   - Xcodeでターゲットデバイスを選択して実行

### Xcode プロジェクトの生成

`.xcodeproj` は git 管理外のため、初回または `project.yml` 変更後に XcodeGen を実行します。

```bash
xcodegen generate
open MioCam.xcodeproj
```

### TestFlight への自動アップロード

TsureBen と共用の App Store Connect API キー（`../TsureBen/ios/.appstore.env`）を使い、1 コマンドで Archive から TestFlight アップロードまで実行できます。

**前提:**
- [`../TsureBen/ios/.appstore.env`](../TsureBen/ios/.appstore.env) が設定済み
- App Store Connect に `com.itoguchi.MioCam` の App レコードが存在
- `xcodegen` がインストール済み

```bash
# 現在の VERSION（2.0.0）のままアップロード
./scripts/upload-testflight.sh

# マーケティングバージョンを指定してアップロード
./scripts/upload-testflight.sh 2.0.1
```

ビルド番号は `YYYYMMDDHHMM` 形式で自動生成されます（重複アップロード回避）。アップロード後、App Store Connect → MioCam → TestFlight で処理完了を確認してください。

別の env ファイルを使う場合:

```bash
APPSTORE_ENV=/path/to/.appstore.env ./scripts/upload-testflight.sh
```

詳細は [docs/requirements.md](docs/requirements.md) を参照してください。

## 開発フェーズ

- **MVP (Phase 1)**: QRペアリング + ライブビュー + ブラックアウトモード
- **Phase 2**: エッジAI検知 + プッシュ通知
- **Phase 3**: 双方向音声通話 + 複数カメラ対応
- **Phase 4**: クラウドクリップ保存 + フリーミアム課金

## ライセンス

[ライセンスを記載]

## 貢献

[貢献ガイドラインを記載]
