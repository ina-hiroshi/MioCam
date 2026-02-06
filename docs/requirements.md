# MioCam 要件定義書

## 1. プロジェクト概要

### 1.1 コンセプト

「古いiPhoneを、世界一シンプルな見守り窓に。」

### 1.2 ターゲットユーザー

- 安価かつ手軽にベビーモニター/ペットカメラを導入したいユーザー
- 既存アプリの操作が複雑で挫折したユーザー
- プライバシーを懸念するユーザー

### 1.3 価値提案（USP）

- **設定不要**: QRコードペアリングで簡単セットアップ
- **徹底した省エネ設計**: カメラ側のブラックアウトモード
- **エッジAIによる「意味のある通知」のみの提供**: 誤検知をカット
- **P2P通信**: サーバーに映像を保存しない

### 1.4 技術スタック

- **言語**: Swift
- **通信**: WebRTC (GoogleWebRTC)
- **検知**: Vision Framework / Core ML
- **バックエンド（シグナリング）**: Firebase (Cloud Firestore / Functions) ※接続の仲介のみに使用

---

## 2. フェーズ計画

本プロジェクトは4段階のフェーズに分けて開発を進める。

| Phase | 内容 |
| ----- | --- |
| **MVP (Phase 1)** | QRペアリング + ライブビュー(WebRTC) + ブラックアウトモード + Sign in with Apple + **1カメラ:複数モニター接続（台数無制限）** |
| **Phase 2** | エッジAI検知(Vision) + スマートプッシュ通知(スナップショット付き) |
| **Phase 3** | 双方向音声通話 + 複数カメラ対応 + 家族共有（他Apple IDのユーザーを招待） |
| **Phase 4** | 検知クリップのクラウド保存(有料) + フリーミアム課金 |

---

## 3. 機能要件（フェーズ別）

### 3.1 MVP (Phase 1)

#### 3.1.1 ペアリング・接続

- **QRコードペアリング**: カメラ側で表示したQRコードを、モニター側で読み取るだけで紐付け完了
- **アカウントレス体験**: Apple ID（Sign in with Apple）を利用し、ユーザーにメールアドレスやパスワードの入力を求めない
- **1カメラ:複数モニター接続**: 1台のカメラに複数のモニター端末が同時接続可能（台数無制限）

#### 3.1.2 カメラ側（撮影端末）の機能

- **省エネ・ブラックアウトモード**:
  - 録画・配信中、画面を真っ黒なレイヤーで覆う
  - システム輝度を自動的に最小化
- **バックグラウンド維持**: 無音オーディオ再生等によるプロセスの維持（OSによる強制終了防止）

#### 3.1.3 モニター側（閲覧端末）の機能

- **ワンタップ・ライブビュー**: アプリ起動と同時にカメラ映像を表示
- **ステータス表示**: カメラ側の「バッテリー残量」と「接続状態（オンライン/オフライン）」をモニター側に常に小さく表示

### 3.2 Phase 2

- **スマート検知（エッジAI）**: iOSのVisionフレームワークを使用し、人間または動物の動きのみを識別。カーテンの揺れなどの誤検知をカット
- **スマートプッシュ通知**: 検知時のスナップショット（静止画）を通知に添付。通知音を「ささやき声」や「微細な振動」に変更できるオプション

### 3.3 Phase 3

- **双方向音声通話**: リアルタイムで声をかける機能
- **複数カメラ対応**: 1つのモニター端末で複数のカメラを切り替えて表示可能
- **家族共有**: 他のApple IDのユーザーをモニターとして招待可能

### 3.4 Phase 4

- **検知クリップのクラウド保存**: 検知前後10秒のクリップをクラウドに保存（有料機能）
- **フリーミアム課金**: StoreKit 2によるサブスクリプション課金

---

## 4. 技術アーキテクチャ

### 4.1 WebRTC接続フロー（1カメラ:Nモニター対応）

MVPで1カメラに複数モニターが接続する構成をサポートする。カメラ側は**モニターごとに独立したRTCPeerConnection**を生成・維持する。

```mermaid
sequenceDiagram
    participant MonitorA as モニターA
    participant MonitorB as モニターB
    participant Firebase as Firebase Firestore
    participant Camera as カメラ側

    Note over Camera: カメラはペアリングコードを持つ永続的なカメラドキュメントを保持
    MonitorA->>Firebase: セッション作成 + SDP Offer書き込み
    Camera->>Firebase: MonitorAのOffer検知 -> PeerConnection#1生成
    Camera->>Firebase: SDP Answer書き込み
    MonitorA->>Firebase: ICE Candidates交換
    MonitorA-->>Camera: P2P接続#1確立

    MonitorB->>Firebase: セッション作成 + SDP Offer書き込み
    Camera->>Firebase: MonitorBのOffer検知 -> PeerConnection#2生成
    Camera->>Firebase: SDP Answer書き込み
    MonitorB->>Firebase: ICE Candidates交換
    MonitorB-->>Camera: P2P接続#2確立

    Note over Camera: 同一のカメラキャプチャセッションから各PeerConnectionにトラックを配信
```

**1:N接続の設計ポイント**:

- カメラ側は`AVCaptureSession`を1つだけ起動し、同じ映像トラックを複数のPeerConnectionに`addTrack`する
- H.264ハードウェアエンコーダは共有されるため、PeerConnection数に比例してCPU負荷が増えるわけではないが、**アップロード帯域幅はモニター数に比例**する
- カメラ側は接続中のモニター数を監視し、ネットワーク帯域が逼迫した場合は自動的に解像度/FPSを下げる（適応的品質制御）

**技術仕様**:

- **STUN/TURNサーバー**: Google公開STUN (`stun:stun.l.google.com:19302`) + 有料TURNサービス（Twilio NTS or Cloudflare TURN）のフォールバック
- **再接続ロジック**: 切断検知後、指数バックオフで自動再接続（最大5回、間隔: 1s -> 2s -> 4s -> 8s -> 16s）
- **映像コーデック**: H.264（ハードウェアエンコード対応のため古い端末でも低負荷）
- **解像度/FPS戦略**: 初期値720p/15fps、ネットワーク状態に応じて動的に調整。接続モニター数が3台以上の場合は480p/10fpsに自動降格
- **帯域見積もり**: 720p/15fps H.264で約1Mbps/モニター。モニター3台接続時に約3Mbpsのアップロード帯域が必要

### 4.2 Firebase シグナリング設計（1:N対応）

1カメラ:Nモニターに対応するため、シグナリング構造を「カメラ単位の永続ドキュメント + モニターごとのセッションサブコレクション」に変更する:

```
/cameras/{cameraId}  ← カメラ登録時に作成（永続）
  ├── ownerUserId: string
  ├── pairingCode: string (6桁英数字、QRに埋め込む)
  ├── deviceName: string
  ├── isOnline: boolean
  ├── lastSeenAt: Timestamp
  ├── createdAt: Timestamp
  └── /sessions/{sessionId}  ← モニター接続ごとに1つ作成（一時的）
        ├── monitorUserId: string
        ├── monitorDeviceId: string
        ├── offer: RTCSessionDescription
        ├── answer: RTCSessionDescription
        ├── status: "waiting" | "connected" | "disconnected"
        ├── createdAt: Timestamp
        └── /iceCandidates/{candidateId}
              ├── candidate: string
              ├── sdpMid: string
              ├── sdpMLineIndex: number
              └── sender: "monitor" | "camera"
```

**動作フロー**:

1. カメラ側が `/cameras/{cameraId}` を作成し、`pairingCode` を生成
2. モニター側がQRスキャンで `cameraId` + `pairingCode` を取得
3. モニター側が `/cameras/{cameraId}/sessions/{sessionId}` を作成し、SDP Offerを書き込む
4. カメラ側はFirestoreのリアルタイムリスナーで新しいセッションを検知し、PeerConnectionを生成してAnswerを返す
5. 複数のモニターが同時にセッションを作成でき、カメラ側はそれぞれに対して個別に応答する

**セッション管理**:

- **セッションの有効期限**: 作成から5分以内に`connected`にならなかった場合、Cloud Functionsで自動削除
- **切断済みセッションの掃除**: `disconnected`状態のセッションは1時間後に自動削除
- **セキュリティルール**: `pairingCode`を知っているユーザーのみセッション作成可。カメラの`ownerUserId`のみカメラドキュメントの編集可

### 4.3 バックグラウンド維持戦略

カメラ側アプリがバックグラウンドで動作し続けるための戦略:

- **AVAudioSession**: `.playback`カテゴリで無音ループ再生
- **Background Modes**: `audio`, `voip` (PushKitは将来Phase3で検討)
- **BGTaskScheduler**: `BGAppRefreshTask`で定期的にヘルスチェック
- **Apple審査対策**: 「見守りカメラとしてリアルタイム映像配信が必要」という正当な利用理由を説明文に記載

---

## 5. QRペアリング詳細フロー

QRコードは**カメラ側が表示**する設計。同じQRを複数のモニターが読み取ることで、自然にN台接続が成立する。

```mermaid
flowchart TD
    A["アプリ起動"] --> B["役割選択: モニター / カメラ"]
    B -->|カメラ| C["Sign in with Apple"]
    C --> D["Firebaseにカメラ登録 + pairingCode生成"]
    D --> E["cameraId + pairingCodeをQRコードとして表示"]
    E --> F["QRは常に表示可能（設定から再表示）"]

    B -->|モニター| G["Sign in with Apple"]
    G --> H["QRスキャン画面を起動"]
    H --> I["QR読み取り -> cameraId + pairingCode取得"]
    I --> J["Firestoreにセッション作成 + SDP Offer"]
    J --> K["カメラ側がセッションを検知 -> SDP Answer返却"]
    K --> L["P2P接続確立 -> ライブビュー開始"]
```

**QRコードに含める情報**（JSON -> Base64エンコード）:

- `cameraId`: Firestoreカメラドキュメントの一意識別子
- `pairingCode`: 6桁英数字の永続ペアリングコード

**重要な設計判断**:

- QRコードはカメラ側が表示する。これにより、同じQRを家族全員のモニターで読み取れる
- `pairingCode`は永続的（有効期限なし）。カメラ側の設定から「ペアリングコードを再生成」でリセット可能
- QRスキャン以外に、`pairingCode`の6桁を手入力する代替手段も提供（QR読み取りが困難な場合のフォールバック）

**2回目以降の接続**:

- モニター側はペアリング済みカメラの`cameraId`をローカルに保存
- アプリ再起動時は自動的にセッションを作成し、QRスキャンなしで再接続

---

## 6. UI/UX デザインシステム

### 6.1 デザイン原則

- **「監視」ではなく「見守り」**: 無機質さを排除し、温かみと安心感を演出する
- **情報の最小化**: 必要な情報だけを必要な時に表示。認知負荷を下げる
- **ワンアクション原則**: どの画面でも主要操作は1タップで完結
- **ダーク/ライト両対応**: システム設定に追従（`@Environment(\.colorScheme)`）

### 6.2 カラーパレット

#### ライトモード

- **プライマリ背景**: `#FFF8F0`（温かみのあるオフホワイト）
- **セカンダリ背景**: `#FFFFFF`（カード・シート用の純白）
- **プライマリテキスト**: `#2D2D2D`（柔らかいブラック）
- **セカンダリテキスト**: `#8E8E93`（iOS標準のセカンダリグレー）
- **アクセントカラー（メイン）**: `#FF9F6A`（温かみのあるコーラルオレンジ）
- **アクセントカラー（サブ）**: `#7EC8C8`（落ち着いたミントグリーン - 「接続中」の安心感を表現）
- **成功/オンライン**: `#6FCF97`（柔らかいグリーン）
- **警告**: `#F2C94C`（柔らかいイエロー）
- **エラー/オフライン**: `#EB5757`（柔らかいレッド）
- **バッテリー低下**: `#EB5757`（20%以下で使用）

#### ダークモード

- **プライマリ背景**: `#1C1C1E`（iOS標準のダーク背景）
- **セカンダリ背景**: `#2C2C2E`（カード・シート用）
- **プライマリテキスト**: `#F5F5F5`（柔らかいホワイト）
- **セカンダリテキスト**: `#8E8E93`（共通）
- **アクセントカラー（メイン）**: `#FFB088`（ライトモードより少し明るくしたコーラル）
- **アクセントカラー（サブ）**: `#8ED8D8`（少し明るくしたミント）
- **成功/警告/エラー**: ライトモードと同じ値を使用

#### SwiftUI実装方針

- `Color` extension でセマンティックカラーを定義
- `Assets.xcassets` にカラーセットを登録し、Light/Dark自動切替
- 例: `Color.mioPrimary`, `Color.mioAccent`, `Color.mioSuccess`

### 6.3 タイポグラフィ

#### フォントファミリー

- **見出し・ブランド表示**: **Rounded（SF Pro Rounded）** - iOS標準の丸みフォント
  - SwiftUI: `.font(.system(.title, design: .rounded))`
- **本文・説明テキスト**: **SF Pro Text** - iOS標準
  - SwiftUI: `.font(.system(.body))`
- **数値・ステータス表示**: **SF Mono Rounded** - 等幅の丸みフォント
  - バッテリー残量やモニター数などの数値に使用

#### フォントサイズ・ウェイト定義

- **大見出し（役割選択など）**: 28pt / Bold / Rounded / 行間 1.3
- **中見出し（画面タイトル）**: 22pt / Semibold / Rounded / 行間 1.3
- **本文（説明テキスト）**: 17pt / Regular / 行間 1.5
- **サブテキスト（補助情報）**: 15pt / Regular / セカンダリテキスト色 / 行間 1.4
- **キャプション（バッジ・ラベル）**: 13pt / Medium / 行間 1.3
- **ステータス数値（バッテリー等）**: 15pt / Semibold / Mono Rounded
- **ペアリングコード（6桁）**: 32pt / Bold / Mono Rounded / 文字間隔 4pt

#### Dynamic Type対応

- 全テキストはDynamic Typeに対応（アクセシビリティ）
- SwiftUIの `.font()` モディファイアを使用し、固定ptは使わず相対サイズで指定

### 6.4 コンポーネント仕様

#### ボタン

**プライマリボタン（CTA）**:

- サイズ: 幅100%（左右マージン24pt）、高さ56pt
- 角丸: 16pt
- 背景: アクセントカラー（コーラルオレンジ `#FF9F6A`）
- テキスト: 17pt / Bold / 白
- シャドウ: `color: accent.opacity(0.3), radius: 8, y: 4`
- タップ時: `scaleEffect(0.96)` + 0.15秒のバネアニメーション

**セカンダリボタン**:

- サイズ: 幅100%（左右マージン24pt）、高さ56pt
- 角丸: 16pt
- 背景: 透明
- ボーダー: 1.5pt / セカンダリテキスト色
- テキスト: 17pt / Semibold / プライマリテキスト色
- タップ時: `scaleEffect(0.96)` + 背景色が薄いグレーに変化

**アイコンボタン（オーバーレイ上）**:

- サイズ: 44x44pt（タップ領域）、表示サイズ 36x36pt
- 角丸: 完全な円形（`clipShape(Circle())`）
- 背景: `UIBlurEffect(.systemThinMaterial)` (すりガラス効果)
- アイコン: 20pt / 白（ダークモードではプライマリテキスト色）

#### カード

**役割選択カード**:

- サイズ: 幅100%（左右マージン24pt）、高さ160pt
- 角丸: 20pt
- 背景: セカンダリ背景色
- シャドウ: `color: .black.opacity(0.06), radius: 12, y: 4`
- 内容:
  - カスタムアイコン（64x64pt）上部中央
  - テキスト: 17pt / Semibold / 中央揃え
  - サブテキスト: 13pt / セカンダリ色 / 中央揃え
- 選択時: ボーダー 2pt / アクセントカラー + `scaleEffect(0.97)`

#### ステータスバッジ

**接続状態バッジ（オンライン/オフライン）**:

- サイズ: 自動幅、高さ 28pt
- 角丸: 14pt（カプセル型）
- 背景: `UIBlurEffect(.systemThinMaterial)` (すりガラス効果)
- 内容: 8ptの円形インジケータ（緑/赤）+ テキスト 13pt / Medium
- オンライン: 緑の円 + 「接続中」
- オフライン: 赤の円 + 「オフライン」

**バッテリーバッジ**:

- サイズ: 自動幅、高さ 28pt
- 角丸: 14pt（カプセル型）
- 背景: `UIBlurEffect(.systemThinMaterial)` (すりガラス効果)
- 内容: バッテリーアイコン（SF Symbol `battery.75`相当をカスタム化）+ 「85%」
- 色分け: 100-21%=成功色, 20-11%=警告色, 10-0%=エラー色

#### トースト/バナー通知

**アプリ内通知バナー**:

- 位置: 画面上部（SafeArea内側）、左右マージン16pt
- サイズ: 幅100%、高さ自動
- 角丸: 16pt
- 背景: `UIBlurEffect(.systemThickMaterial)` (すりガラス効果)
- アニメーション: 上からスライドイン（0.3秒、バネ）、3秒後に自動で上にスライドアウト
- 内容: アイコン（24pt）+ メッセージテキスト（15pt / Semibold）
- 例: 「カメラの通信状況が不安定です」「バッテリーが残り20%です」

### 6.5 アイコンシステム

#### スタイル

- **カスタム丸みアイコン**を基本とする
- 線幅: 2pt
- 角: すべて丸み処理
- サイズバリエーション: 20pt（ボタン内）/ 24pt（リスト内）/ 48pt（画面中央）/ 64pt（役割選択カード）

#### 主要アイコン一覧

- **カメラ**: 丸みのあるビデオカメラ（レンズ部分を強調）
- **モニター**: 丸みのあるスマートフォン + 目のアイコン
- **QRコード**: 丸みのあるQRコードフレーム
- **設定**: 丸みのある歯車
- **接続**: 丸みのあるリンクチェーン
- **マイク**: 丸みのあるマイクロフォン（Phase 3）
- **バッテリー**: 丸みのあるバッテリーシェイプ
- **切断**: 丸みのある×印
- **通知**: 丸みのあるベル

#### 実装

- SVGでデザインし、`Assets.xcassets` にPDF/SVGとして登録
- SwiftUIでは `Image("iconName")` で呼び出し
- `.renderingMode(.template)` で色を動的に変更

### 6.6 画面別レイアウト仕様（MVP）

詳細な画面レイアウト仕様は、プランファイルの「4. UI/UX デザインシステム」セクションを参照。

主要画面:

1. **スプラッシュ画面**: ロゴ + ローディングアニメーション
2. **Sign in with Apple画面**: ロゴ + 説明テキスト + Apple標準ボタン
3. **役割選択画面**: 2つのカード（カメラ/モニター）を縦に配置
4. **[カメラ] QR表示画面**: QRコード + ペアリングコード + 接続状態
5. **[カメラ] ブラックアウト画面**: 純黒背景 + 最小限のステータス表示
6. **[モニター] QRスキャン画面**: カメラプレビュー + スキャンガイド枠
7. **[モニター] ライブビュー画面**: WebRTC映像 + オーバーレイUI
8. **設定オーバーレイ（カメラ側）**: ハーフモーダルシート
9. **設定オーバーレイ（モニター側）**: ハーフモーダルシート

### 6.7 インタラクション・アニメーション仕様

#### トランジション（画面遷移）

- **標準遷移**: iOS標準の水平スライド（`NavigationStack` のデフォルト）
- **役割選択 → QR表示/スキャン**: `matchedGeometryEffect` で選択カードが拡大しながら遷移（0.4秒、バネ）
- **QRスキャン → ライブビュー**: QRスキャン成功後、成功アニメーション（チェックマーク 0.5秒）→ クロスフェード（0.3秒）でライブビューに遷移
- **モーダル表示（設定）**: iOS標準の `.sheet` トランジション（下からスライドアップ）

#### ジェスチャー

- **タップ**: ボタン、カード、リスト行の選択
- **ロングプレス**: なし（MVP）
- **スワイプダウン**: モーダルシートの閉じ操作
- **ピンチ**: ライブビュー画面でのズームイン/アウト（1.0x - 3.0x）
- **ダブルタップ**: ライブビュー画面でズームトグル（1.0x ↔ 2.0x）

#### フィードバック

- **タップフィードバック**: `UIImpactFeedbackGenerator(.light)` - ボタンタップ時
- **成功フィードバック**: `UINotificationFeedbackGenerator(.success)` - QRスキャン成功、ペアリング完了
- **警告フィードバック**: `UINotificationFeedbackGenerator(.warning)` - バッテリー低下通知
- **エラーフィードバック**: `UINotificationFeedbackGenerator(.error)` - 接続切断

#### ローディング状態

- **接続待ち（QR表示画面）**: アクセントカラーの点がパルスアニメーション
- **再接続中（ライブビュー）**: 映像にブラーオーバーレイ + 白いスピナー（`ProgressView`）+ 「再接続中...」テキスト
- **データ読み込み中**: スケルトンUI（シマーアニメーション）は不要（データ量が少ないため）

#### マイクロインタラクション

- **モニター接続/切断**: ステータスバッジの数字が `scaleEffect` でバウンス（0.3秒）
- **バッテリー更新**: 数値が変わる際に `ContentTransition.numericText()` で滑らかに変化
- **オンライン/オフライン切替**: インジケータの色が0.5秒でクロスフェード

### 6.8 画面遷移図

```mermaid
flowchart LR
    Splash --> SignIn["Sign in with Apple"]
    SignIn --> RoleSelect["役割選択"]
    RoleSelect -->|カメラ| QRDisplay["QR表示"]
    RoleSelect -->|モニター| QRScan["QRスキャン"]
    QRDisplay -->|モニター接続| Blackout["ブラックアウト"]
    QRScan -->|ペアリング成功| LiveView["ライブビュー"]
    Blackout -->|タップ| CameraSettings["設定シート（カメラ）"]
    CameraSettings -->|閉じる| Blackout
    LiveView -->|歯車タップ| MonitorSettings["設定シート（モニター）"]
    MonitorSettings -->|閉じる| LiveView
    CameraSettings -->|カメラ停止| RoleSelect
    MonitorSettings -->|接続解除| RoleSelect
```

### 6.9 アクセシビリティ

- **VoiceOver**: 全UI要素に `accessibilityLabel` と `accessibilityHint` を設定
- **Dynamic Type**: 全テキストが拡大縮小に対応
- **カラーコントラスト**: WCAG AA基準（4.5:1以上）を満たす配色
- **Reduce Motion**: `@Environment(\.accessibilityReduceMotion)` でアニメーションを簡略化（フェードのみに）
- **ライブビュー画面**: 映像にVoiceOverで「ライブカメラ映像」と読み上げ

---

## 7. データモデル（Firestore設計）

```
/users/{userId}
  ├── appleUserId: string
  ├── displayName: string (匿名化されたSign in with Appleの名前)
  ├── createdAt: Timestamp
  └── /subscription  ← Phase 4: 課金情報
        ├── plan: "free" | "premium"
        ├── expiresAt: Timestamp
        └── originalTransactionId: string

/cameras/{cameraId}  ← カメラ登録時に作成（永続）
  ├── ownerUserId: string
  ├── pairingCode: string (6桁英数字)
  ├── deviceName: string (例: "リビングのカメラ")
  ├── deviceModel: string (例: "iPhone 7")
  ├── osVersion: string
  ├── pushToken: string (APNsトークン)
  ├── isOnline: boolean
  ├── batteryLevel: number (0-100)
  ├── lastSeenAt: Timestamp
  ├── createdAt: Timestamp
  ├── connectedMonitorCount: number  ← リアルタイムで更新
  └── /sessions/{sessionId}  ← モニター接続ごと（一時的）
        ├── monitorUserId: string
        ├── monitorDeviceId: string
        ├── monitorDeviceName: string
        ├── offer: map (SDP)
        ├── answer: map (SDP)
        ├── status: "waiting" | "connected" | "disconnected"
        ├── createdAt: Timestamp
        └── /iceCandidates/{candidateId}
              ├── candidate: string
              ├── sdpMid: string
              ├── sdpMLineIndex: number
              └── sender: "monitor" | "camera"

/monitorLinks/{monitorUserId}_{cameraId}  ← モニターがペアリング済みのカメラ一覧（永続）
  ├── monitorUserId: string
  ├── cameraId: string
  ├── cameraDeviceName: string
  ├── pairedAt: Timestamp
  └── isActive: boolean
```

**Firestoreセキュリティルール方針**:

- `/users/{userId}` は本人のみ読み書き可
- `/cameras/{cameraId}` は `ownerUserId` のみ編集可。`pairingCode`を知っているユーザーはセッション作成可
- `/cameras/{cameraId}/sessions/{sessionId}` はセッション作成者(monitor)とカメラオーナーのみ読み書き可
- `/monitorLinks/{docId}` は該当する`monitorUserId`のみ読み書き可

**Firestoreセキュリティルール**:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // ユーザー情報
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      match /subscription {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
    
    // カメラ情報
    match /cameras/{cameraId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
        (resource == null && request.resource.data.ownerUserId == request.auth.uid ||
         resource != null && resource.data.ownerUserId == request.auth.uid);
      
      // セッション（シグナリング）
      match /sessions/{sessionId} {
        allow create: if request.auth != null && 
          request.resource.data.monitorUserId == request.auth.uid &&
          request.resource.data.pairingCode == get(/databases/$(database)/documents/cameras/$(cameraId)).data.pairingCode;
        allow read, write: if request.auth != null && 
          (request.auth.uid == resource.data.monitorUserId ||
           request.auth.uid == get(/databases/$(database)/documents/cameras/$(cameraId)).data.ownerUserId);
      }
    }
    
    // モニターリンク
    match /monitorLinks/{linkId} {
      allow read, write: if request.auth != null && 
        resource.data.monitorUserId == request.auth.uid;
    }
  }
}
```

**インデックス**:

- `/cameras/{cameraId}/sessions`: `status` + `createdAt` (降順)
- `/monitorLinks`: `monitorUserId` + `isActive` + `pairedAt` (降順)

---

## 8. エッジAI検知の詳細仕様（Phase 2）

Phase 2向けだが、設計方針は今から定義しておく:

- **使用API**: `VNDetectHumanBodyPoseRequest` + `VNRecognizeAnimalsRequest`
- **検知ロジック**:
  1. 映像フレームを0.5秒間隔でサンプリング（全フレーム処理しない）
  2. 人体または動物が検出された場合、信頼度スコア > 0.7 のみ有効と判定
  3. 検出エリアのバウンディングボックスが前フレームから一定以上移動した場合のみ「動き」と判定（静止している人物では通知しない）
- **クールダウン**: 同種の検知通知は最低30秒間隔（ユーザー設定で変更可: 30秒/1分/5分）
- **スナップショット**: 検知時のフレームをJPEG (品質80%) でキャプチャし、APNs経由でリッチ通知として送信

---

## 9. エッジケース・異常系ハンドリング

現在の要件定義書で未定義のエッジケースを追加:

- **ネットワーク切断時**: モニター側に「接続が切れました。再接続しています...」とオーバーレイ表示。指数バックオフで再接続試行。
- **カメラ側アプリがOSに強制終了された場合**: プッシュ通知でユーザーに「カメラアプリが停止しました。再起動してください」と通知。
- **バッテリー残量低下**: カメラ側が20%以下になったらモニター側に警告通知、10%以下で赤色表示。
- **WiFiからセルラーへの切り替え**: ICE Restartを発火し、新しいネットワークパスで再接続。
- **両端末が同じApple IDの場合**: 正常動作すること（1ユーザーが2台持ちで利用するケース）。
- **ペアリング解除フロー**: モニター側の設定から「カメラの接続を解除」-> Firestoreの`monitorLinks`を`isActive: false`に更新 -> セッションを切断。カメラ側は他のモニターへの配信を継続。
- **カメラ側からの全モニター切断**: カメラ側設定から「ペアリングコードを再生成」-> 既存の全セッションを切断 + 旧pairingCodeを無効化。
- **モニター多数接続時の品質劣化**: カメラ側が3台以上のモニターを検知した場合、各モニターに「接続数が多いため映像品質を自動調整しています」とバナー表示。
- **カメラ側の帯域不足**: WebRTC統計API(`RTCStatsReport`)でアップロード帯域を監視。帯域不足時に解像度/FPSを段階的に下げ、それでも不足なら最も古いセッション以外に「カメラの通信状況が不安定です」と通知。

---

## 10. フリーミアム課金設計

### 10.1 無料プラン

- QRペアリング（**カメラ1台** + **モニター台数無制限**）
- ライブビュー
- ブラックアウトモード
- エッジAI検知 + プッシュ通知（Phase 2）
- 双方向音声（Phase 3）

### 10.2 プレミアムプラン（月額 or 年額）

- **複数カメラ接続**（2台目以降のカメラ追加 - 例: リビング+寝室）
- **クラウドクリップ保存**（検知前後10秒のクリップを最大7日間保存）
- **カスタム検知ゾーン**（画面内の特定エリアのみを検知対象に設定）
- **タイムラプス再生**（1日の動きを早送りで確認）

> 注: 「家族共有（他Apple IDのモニター招待）」は無料プランでも可能。同じQRコードを読み取るだけなので、課金ゲートにはしない。

### 10.3 技術的な課金実装

- StoreKit 2 を使用
- サーバーサイド検証: App Store Server Notifications V2 を Firebase Functions で受信
- サブスクリプションステータスは `/users/{userId}/subscription` に保存

---

## 11. セキュリティ・プライバシー

- **映像データ**: E2E暗号化はWebRTC DTLSにより標準で適用。サーバー経由(TURN)の場合も暗号化維持。
- **Firebaseに保存するデータ**: シグナリング情報（一時的）+ デバイス情報 + ペアリング情報のみ。映像・音声データは一切保存しない。
- **クラウドクリップ（Phase 4有料機能）**: Firebase Storage (またはCloudflare R2) に暗号化保存。7日後に自動削除。暗号化キーはユーザーのApple IDに紐づく。
- **App Tracking Transparency**: トラッキングなし。ATTダイアログ不要。
- **プライバシーポリシー**: 「映像はサーバーに保存されません」を明記。Apple Privacy Nutrition Labels に対応。

---

## 12. 非機能要件

- **起動時間**: コールドスタートからライブビュー表示まで3秒以内（ペアリング済みの場合）
- **映像遅延**: P2P時 500ms以内、TURN経由時 1000ms以内
- **バッテリー消費**: カメラ側でブラックアウト時、1時間あたりのバッテリー消費を15%以下に抑える
- **発熱制御**: CPU温度監視API(`ProcessInfo.thermalState`)を使用し、`.serious`以上でフレームレートを5fpsに制限
- **対応端末**: iOS 15以上 / iPhone 6s以降
- **アプリサイズ**: 50MB以下（WebRTCフレームワーク込み）
- **クラッシュフリー率**: 99.5%以上（Firebase Crashlytics で監視）

---

## 13. Firebase設定要件

実装フェーズでエージェントが設定作業を実施する。要件定義書には以下を明記する:

### 13.1 Firebaseプロジェクト作成（ユーザー作業: 詳細手順）

1. **Firebase Consoleにアクセス**
   - https://console.firebase.google.com にアクセス
   - Googleアカウントでログイン
2. **新規プロジェクトの作成**
   - 「プロジェクトを追加」をクリック
   - **プロジェクト名**: `miocam` または任意の名前（例: `MioCam`）
   - 「続行」をクリック
3. **Google Analyticsの設定**
   - 「Google Analyticsを有効にする」は任意（有効推奨）
   - Analyticsアカウントを選択（または新規作成）
   - 「プロジェクトを作成」をクリック
4. **プロジェクトの準備完了**
   - 数秒待つとプロジェクトが作成される
   - 「続行」をクリックしてプロジェクトダッシュボードに移動
5. **プロジェクトIDの確認**
   - プロジェクト設定（歯車アイコン → 「プロジェクトの設定」）で「プロジェクトID」を確認
   - 例: `miocam-12345` のような形式
   - このIDは後でSign in with Appleの設定で使用する
6. **リージョンの設定（後で実施）**
   - Firestoreデータベース作成時に `asia-northeast1` (東京) を選択
   - レイテンシ低減のため、日本リージョンを推奨

### 13.2 iOSアプリ登録（ユーザー作業: 詳細手順）

#### ステップ1: Bundle IDの予約（App Store Connect）

1. **App Store Connectにアクセス**
   - https://appstoreconnect.apple.com にログイン
   - Apple Developer Programに加入済みであること（年額$99）
2. **Bundle IDの作成**
   - 左メニュー「Certificates, Identifiers & Profiles」をクリック
   - 「Identifiers」→「+」ボタン
   - 「App IDs」を選択 → 「Continue」
   - 「App」を選択 → 「Continue」
   - **Description**: `MioCam` (任意の説明)
   - **Bundle ID**: `Explicit` を選択
   - **Bundle ID**: `com.[your-domain].MioCam` を入力
     - 例: `com.yourcompany.MioCam` または `com.yourname.MioCam`
     - 注意: このBundle IDは後で変更できないため、慎重に決める
   - **Capabilities** で以下を有効化:
     - ✅ **Sign In with Apple** (必須)
     - ✅ **Push Notifications** (Phase 2以降で必要)
     - ✅ **In-App Purchase** (Phase 4のフリーミアム課金で必要)
       - **重要**: 後から追加も可能だが、最初から有効にしておくことを推奨
       - StoreKit 2を使用するため、このCapabilityが必要
   - 「Continue」→「Register」
3. **確認**
   - Identifiers一覧に作成したBundle IDが表示されることを確認

#### ステップ2: Firebase ConsoleでiOSアプリを登録

1. **Firebase Consoleにアクセス**
   - https://console.firebase.google.com にログイン
   - プロジェクトを選択（または新規作成）
2. **iOSアプリの追加**
   - プロジェクトのホーム画面で「iOSアプリを追加」をクリック
   - **iOS Bundle ID**: ステップ1で作成したBundle IDを入力（例: `com.yourcompany.MioCam`）
   - **App nickname**: `MioCam` (任意)
   - **App Store ID**: この時点では空欄でOK（リリース後に設定）
   - 「アプリを登録」をクリック
3. **GoogleService-Info.plist のダウンロード**
   - ダウンロード画面が表示される
   - 「GoogleService-Info.plist をダウンロード」をクリック
   - ファイルを保存（デスクトップなど、分かりやすい場所に）
   - **重要**: このファイルは後でエージェントがXcodeプロジェクトに追加する
4. **次のステップはスキップ**
   - 「次のステップ」画面は一旦閉じてOK（エージェントが実装時に設定）

#### ステップ3: Xcodeプロジェクトでの設定（エージェントが実施）

実装時にエージェントが以下を実施:

- `GoogleService-Info.plist` をXcodeプロジェクトのルートに追加
- Targetの「Signing & Capabilities」でBundle IDを設定
- 「Sign in with Apple」と「Push Notifications」のCapabilityを追加

### 13.3 Firestoreデータベース

- **モード**: 本番モード（テストモードではない）
- **リージョン**: `asia-northeast1` (東京)
- **コレクション構造**: セクション7で定義した `/cameras`, `/users`, `/monitorLinks` の構造に従って作成
- **インデックス**: 以下の複合インデックスを作成
  - `/cameras/{cameraId}/sessions`: `status` + `createdAt` (降順)
  - `/monitorLinks`: `monitorUserId` + `isActive` + `pairedAt` (降順)

### 13.4 Firestoreセキュリティルール

要件定義書に完全なルール定義を記載する。実装時にエージェントが `firestore.rules` として配置する。

セキュリティルールの詳細は、セクション7「データモデル（Firestore設計）」を参照。

### 13.5 Cloud Functions

以下のFunctionsを実装・デプロイする:

1. **セッション自動削除**: 5分以内に`connected`にならなかったセッションを削除
2. **切断済みセッション掃除**: `disconnected`状態のセッションを1時間後に削除
3. **App Store Server Notifications受信** (Phase 4): StoreKit 2のサブスクリプション検証

実装時にエージェントが `functions/` ディレクトリにTypeScriptで実装する。

### 13.6 Authentication設定（Sign in with Apple: ユーザー作業: 詳細手順）

#### ステップ1: Apple Developer PortalでService IDを作成

1. **Apple Developer Portalにアクセス**
   - https://developer.apple.com/account にログイン
   - 「Certificates, Identifiers & Profiles」をクリック
2. **Service IDの作成**
   - 左メニュー「Identifiers」をクリック
   - 「+」ボタンをクリック
   - 「Services IDs」を選択 → 「Continue」
   - **Description**: `MioCam Sign In with Apple` (任意の説明)
   - **Identifier**: `com.[your-domain].MioCam.signin` を入力
     - 例: `com.yourcompany.MioCam.signin`
     - 注意: Bundle IDとは別の識別子。Service ID専用
   - 「Continue」→「Register」
3. **Sign in with Appleの設定**
   - 作成したService IDをクリック
   - 「Sign In with Apple」のチェックボックスをON
   - 「Configure」をクリック
   - **Primary App ID**: ステップ1で作成したBundle IDを選択（例: `com.yourcompany.MioCam`）
   - **Website URLs** セクション:
     - **Domains**: `[your-project-id].firebaseapp.com` を入力
       - `[your-project-id]` はFirebase Consoleのプロジェクト設定で確認可能
     - **Return URLs**: `https://[your-project-id].firebaseapp.com/__/auth/handler` を追加
       - 例: `https://miocam-12345.firebaseapp.com/__/auth/handler`
   - 「Next」→「Done」→「Continue」→「Save」
4. **Service IDとBundle IDの紐付け確認**
   - Service IDの詳細画面で「Sign In with Apple」が有効になっていることを確認

#### ステップ2: Firebase ConsoleでSign in with Appleを有効化

1. **Firebase ConsoleでAuthentication設定**
   - Firebase Console → プロジェクト選択
   - 左メニュー「Authentication」→「Sign-in method」タブ
2. **Sign in with Appleを有効化**
   - 「Sign in with Apple」の行をクリック
   - 「有効にする」をON
   - **OAuth code flow configuration**:
     - **Service ID**: ステップ1で作成したService IDを入力（例: `com.yourcompany.MioCam.signin`）
     - **OAuth code flow**: 「Web configuration」セクションで以下を設定:
       - **Apple Team ID**: Apple Developer Portalの右上に表示されるTeam ID（例: `ABC123DEF4`）
       - **Key ID**: 次のステップ3で作成する認証キーのKey ID
       - **Private Key**: ステップ3でダウンロードした`.p8`ファイルの内容をペースト
   - 「保存」をクリック

#### ステップ3: Apple Developer Portalで認証キーを作成

1. **Keysセクションに移動**
   - Apple Developer Portal → 「Certificates, Identifiers & Profiles」
   - 左メニュー「Keys」をクリック
   - 「+」ボタンをクリック
2. **認証キーの作成**
   - **Key Name**: `MioCam Sign In with Apple Key` (任意の名前)
   - **Sign In with Apple** のチェックボックスをON
   - 「Configure」をクリック
   - **Primary App ID**: Bundle IDを選択（例: `com.yourcompany.MioCam`）
   - 「Save」→「Continue」→「Register」
3. **認証キーのダウンロード**
   - **重要**: この画面で一度だけ`.p8`ファイルがダウンロード可能
   - 「Download」をクリックして`.p8`ファイルを保存
   - **Key ID**をメモ（例: `XYZ789ABC1`）- Firebase Consoleの設定で使用
4. **Firebase Consoleに戻る**
   - ステップ2のFirebase Console設定画面で:
     - **Key ID**: ステップ3でメモしたKey IDを入力
     - **Private Key**: `.p8`ファイルをテキストエディタで開き、内容をコピー&ペースト
       - ファイル形式: `-----BEGIN PRIVATE KEY-----` で始まるテキスト
   - 「保存」をクリック

#### 確認

- Firebase Consoleの「Sign-in method」で「Sign in with Apple」が緑色（有効）になっていることを確認

### 13.7 Cloud Messaging (APNs: プッシュ通知設定: ユーザー作業: 詳細手順）

> **注意**: APNs認証キーは、Sign in with Apple用のキーとは別物です。プッシュ通知用に専用のキーを作成します。

#### ステップ1: Apple Developer PortalでAPNs認証キーを作成

1. **Apple Developer Portalにアクセス**
   - https://developer.apple.com/account にログイン
   - 「Certificates, Identifiers & Profiles」をクリック
2. **APNs認証キーの作成**
   - 左メニュー「Keys」をクリック
   - 「+」ボタンをクリック
   - **Key Name**: `MioCam APNs Key` (任意の名前)
   - **Apple Push Notifications service (APNs)** のチェックボックスをON
   - 「Continue」→「Register」
3. **認証キーのダウンロード**
   - **重要**: この画面で一度だけ`.p8`ファイルがダウンロード可能
   - 「Download」をクリックして`.p8`ファイルを保存
   - ファイル名は `AuthKey_[KeyID].p8` の形式（例: `AuthKey_XYZ789ABC1.p8`）
   - **Key ID**をメモ（例: `XYZ789ABC1`）- Firebase Consoleの設定で使用
   - **Team ID**もメモ（Apple Developer Portalの右上に表示）
4. **確認**
   - Keys一覧に作成したAPNsキーが表示されることを確認
   - 「Apple Push Notifications service (APNs)」が有効になっていることを確認

#### ステップ2: Firebase ConsoleでAPNs認証キーをアップロード

1. **Firebase ConsoleでCloud Messaging設定**
   - Firebase Console → プロジェクト選択
   - 左メニュー「プロジェクトの設定」（歯車アイコン）をクリック
   - 「Cloud Messaging」タブをクリック
2. **APNs認証キーのアップロード**
   - **Apple app configuration** セクション:
     - **APNs認証キー** を選択（「APNs認証キー」と「APNs証明書」の2択があるが、認証キーを推奨）
   - **Key ID**: ステップ1でメモしたKey IDを入力
   - **Team ID**: ステップ1でメモしたTeam IDを入力
   - **認証キー**: `.p8`ファイルをアップロード
     - 「ファイルを選択」をクリック
     - ダウンロードした`.p8`ファイルを選択
   - 「アップロード」をクリック
3. **確認**
   - 「Cloud Messaging」タブで「APNs認証キー」が緑色のチェックマークになっていることを確認
   - 「Apple app configuration」にKey IDとTeam IDが表示されていることを確認

#### ステップ3: Bundle IDの確認

- Firebase Consoleの「Cloud Messaging」タブで、正しいBundle IDが表示されていることを確認
- Apple Developer Portalで作成したBundle IDと一致していること

#### トラブルシューティング

- **エラー: "Invalid key"**: `.p8`ファイルが正しくダウンロードされていない可能性。再度作成が必要な場合は、Apple Developer Portalで新しいキーを作成する必要がある（一度ダウンロードしたキーは再ダウンロード不可）
- **エラー: "Key ID mismatch"**: Key IDが正しく入力されているか確認
- **エラー: "Team ID mismatch"**: Team IDが正しく入力されているか確認

### 13.8 環境変数・設定ファイル

実装時にエージェントが以下を作成:

- `GoogleService-Info.plist`: Xcodeプロジェクトに追加
- `.env` (Cloud Functions用): 必要に応じて
- `firebase.json`: FirestoreルールとFunctionsのデプロイ設定

### 13.9 実装時のエージェント作業フロー

1. Firebase CLI (`firebase-tools`) をインストール
2. `firebase login` で認証
3. `firebase init` でプロジェクト初期化
4. Firestoreルールを `firestore.rules` に配置
5. Cloud Functionsを `functions/` に実装
6. `firebase deploy` でデプロイ

**注意**: Firebaseプロジェクトの作成自体は手動で行う必要があるが、それ以外の設定（ルール、Functions、セキュリティ設定）はエージェントが実施可能。

---

## 14. GitHubリポジトリ作成・初期設定

### 14.1 リポジトリ作成（ユーザー作業）

1. **GitHubにアクセス**
   - https://github.com にログイン
   - 右上の「+」→「New repository」をクリック

2. **リポジトリ情報を入力**
   - **Repository name**: `MioCam`
   - **Description**: `見守りカメラアプリ - 古いiPhoneを世界一シンプルな見守り窓に`
   - **Visibility**: `Private`（プライベート）を選択
   - **Initialize this repository with**:
     - ✅ `Add a README file` はチェックしない（エージェントが作成）
     - ✅ `Add .gitignore` はチェックしない（エージェントが作成）
     - ✅ `Choose a license` はチェックしない（必要に応じて後で追加）
   - 「Create repository」をクリック

3. **リポジトリURLの確認**
   - 作成されたリポジトリのURLを確認
   - 例: `https://github.com/[your-username]/MioCam.git`
   - このURLをメモ（後でローカルリポジトリと接続する際に使用）

### 14.2 初期ファイル構成（エージェントが実施）

実装時にエージェントが以下を作成:

**ルートディレクトリ構成**:
```
MioCam/
├── .gitignore          # iOS/Xcode用の.gitignore
├── README.md           # プロジェクト概要・セットアップ手順
├── LICENSE             # ライセンスファイル（必要に応じて）
├── docs/
│   └── requirements.md # 要件定義書
├── MioCam/             # Xcodeプロジェクト（実装時に作成）
│   ├── MioCam.xcodeproj
│   ├── MioCam/
│   │   ├── AppDelegate.swift
│   │   ├── Info.plist
│   │   └── GoogleService-Info.plist
│   └── ...
└── firebase/           # Firebase設定（実装時に作成）
    ├── firebase.json
    ├── firestore.rules
    └── functions/
```

### 14.3 .gitignoreの内容

iOS/Xcodeプロジェクト用の`.gitignore`を作成:

```
# Xcode
*.xcodeproj/*
!*.xcodeproj/project.pbxproj
!*.xcodeproj/xcshareddata/
*.xcworkspace/*
!*.xcworkspace/contents.xcworkspacedata
!*.xcworkspace/xcshareddata/

# Build
build/
DerivedData/
*.hmap
*.ipa
*.dSYM.zip
*.dSYM

# Swift Package Manager
.swiftpm/
.build/
*.xcodeproj

# CocoaPods
Pods/
*.xcworkspace

# Carthage
Carthage/Build/

# Fastlane
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/**/*.png
fastlane/test_output

# Firebase
GoogleService-Info.plist  # 注意: 実際のファイルは含めるが、サンプルは除外
firebase-debug.log
.firebase/

# 認証キー（機密情報）
*.p8
AuthKey_*.p8

# 環境変数
.env
.env.local

# macOS
.DS_Store
.AppleDouble
.LSOverride

# 一時ファイル
*.swp
*~.nib
*.tmp
```

**注意**: `GoogleService-Info.plist` と `*.p8` ファイルは機密情報のため、`.gitignore`に含める。ただし、開発チーム内で共有する必要がある場合は、別途安全な方法で共有する。

### 14.4 README.mdの内容

プロジェクト概要・セットアップ手順を含むREADMEを作成:

```markdown
# MioCam

見守りカメラアプリ - 「古いiPhoneを、世界一シンプルな見守り窓に。」

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
   git clone https://github.com/[your-username]/MioCam.git
   cd MioCam
   ```

2. Firebase設定ファイルを配置
   - `GoogleService-Info.plist` を `MioCam/MioCam/` ディレクトリに配置

3. Xcodeでプロジェクトを開く
   ```bash
   open MioCam.xcodeproj
   ```

4. 依存関係をインストール
   - CocoaPodsまたはSwift Package Managerを使用

5. ビルド&実行
   - Xcodeでターゲットデバイスを選択して実行

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
```

### 14.5 初期コミットの内容

エージェントが以下を初期コミット:

1. `.gitignore` の作成
2. `README.md` の作成
3. `docs/requirements.md` の作成（要件定義書）
4. 基本的なプロジェクト構造の作成

### 14.6 ブランチ戦略

シンプルなブランチ戦略を採用:

- **main**: 本番リリース用ブランチ
- 機能開発は `main` ブランチから直接ブランチを作成
- プルリクエストで `main` にマージ

将来的にGit Flowが必要になった場合は、`develop` ブランチを追加。

### 14.7 実装時のエージェント作業フロー

1. GitHubでリポジトリが作成済みであることを確認
2. ローカルで `git init` を実行
3. `.gitignore` を作成
4. `README.md` を作成
5. `docs/requirements.md` を作成
6. 初期コミットを実行
7. GitHubリモートリポジトリと接続
   ```bash
   git remote add origin https://github.com/[your-username]/MioCam.git
   git branch -M main
   git push -u origin main
   ```

**注意**: GitHubリポジトリの作成自体は手動で行う必要があるが、それ以外の設定（.gitignore、README、初期コミット）はエージェントが実施可能。

---

## 15. 用語集

- **P2P**: Peer-to-Peer。端末間直接通信のこと。MioCamではWebRTCを使用してP2P接続を確立する。
- **シグナリング**: WebRTC接続を確立するために必要な情報（SDP、ICE Candidates）を交換するプロセス。MioCamではFirebase Firestoreを使用。
- **ペアリングコード**: カメラとモニターを紐付ける6桁の英数字コード。QRコードに含まれる。
- **ブラックアウトモード**: カメラ側の画面を真っ黒にして、省エネとプライバシーを確保する機能。
- **エッジAI**: 端末側で実行されるAI処理。MioCamではVision Frameworkを使用して人間や動物の動きを検知。
- **STUN/TURN**: WebRTC接続を確立するためのサーバー。STUNはNAT越え、TURNはリレーサーバーとして機能。
- **SDP**: Session Description Protocol。WebRTC接続の設定情報を含む。
- **ICE Candidates**: Interactive Connectivity Establishment。WebRTC接続に使用可能なネットワークパス情報。

---

## 改訂履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|---------|
| 2026-02-06 | 1.0 | 初版作成 |
