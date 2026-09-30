# ReadImage on Device

**Mac の中だけで完結する、オンデバイス画像リーダー。**

画像を渡すと「何が写っているか」を日本語の文章で返します。処理はすべて Apple のオンデバイスフレームワーク（Vision / Foundation Models）で行われるため、**画像がネットワークに送られることはありません**。API キーも不要です。

そして、同じ API のまま、**動いている macOS ごとに「その OS が出せる最高精度」**を使います。新しい OS ほど賢くなり、古い OS でも動きます。

- **macOS 11 以降**で動作（M シリーズ / Intel）
- **完全オフライン・オンデバイス**（通信なし・API キー不要）
- **OS に応じて自動で最高精度を選択**（Vision の revision を自動で最新に）
- **共通規格風のかんたん API**（stdin/stdout の JSON、Swift からも数行）

```bash
$ readimage photo.jpg

この画像は、白い紙に印刷された日本語の請求書のスクリーンショットです。
請求金額は128,000円、発行日は2026年10月1日と記載されています。
```

## 使い方

### インストール

Swift Package Manager で使えます。

```swift
dependencies: [
    .package(url: "https://github.com/hibachi-inc/ReadImage-on-Device", from: "0.1.0")
]
```

CLI として使う場合:

```bash
git clone https://github.com/hibachi-inc/ReadImage-on-Device
cd ReadImage-on-Device
swift build -c release
.build/release/readimage photo.jpg
```

### CLI

```bash
readimage <画像> [<画像> ...] [options]
cat image.png | readimage -          # 標準入力からも読める

readimage --raw photo.jpg            # AI を使わず、Vision の抽出結果だけを返す
readimage --json photo.jpg           # 客観情報を JSON で返す
readimage --languages ja-JP,en-US a.jpg b.png
```

主なオプション:

| オプション | 説明 |
| --- | --- |
| `--raw` | AI を使わず、Vision の生の抽出結果（AI 整形前テキスト）だけを返す。全 macOS 対応 |
| `--explain` | その OS で使える最善の方法で解説文を生成する（既定） |
| `-p, --prompt <text>` | 解説の依頼文を差し替える |
| `-i, --instructions <text>` | 生成時の system 指示を差し替える |
| `--languages <a,b>` | OCR 言語（既定: `ja-JP,en-US`） |
| `--json` | Vision の客観情報を JSON で出力する |
| `--no-animals` | 動物検出を行わない |
| `--no-barcodes` | バーコード / QR 検出を行わない |

### Swift から

```swift
import ReadImageOnDevice

// 解説文を生成（その OS で最高の経路を自動選択）
let result = try await ReadImage.read(path: "photo.jpg")
print(result.route)   // 例: "vision+fm(macOS26)"
print(result.text)    // 日本語の解説文

// AI 整形前の生テキストだけが欲しいとき
let raw = try ReadImage.rawText(at: "photo.jpg")
print(raw)

// 同期版（macOS 11〜25 でも Swift 並行ランタイム無しで動く）
let sync = try ReadImage.readSync(path: "photo.jpg", mode: .raw)
```

## どの OS でどう動くか

同じ `ReadImage.read(path:)` が、実行中の macOS に応じて経路を選びます。

| 実行環境 | 採用する経路 | 返すもの |
| --- | --- | --- |
| **macOS 27 以降** + Apple Intelligence | `native-multimodal(macOS27)` | 画像を Foundation Models に直接渡して解説文を生成 |
| **macOS 26** + Apple Intelligence | `vision+fm(macOS26)` | Vision で客観情報を抽出 → Foundation Models で日本語化 |
| **macOS 11〜25** / Apple Intelligence 無効 | `vision-raw` | Vision の生の抽出結果（AI 整形前テキスト） |

どの経路でも、Vision による客観情報（`ImageFacts`）は常に取得できるので、`--raw` は macOS 11 から使えます。

### 各 OS の「最高精度」の選び方

Vision の各リクエストは OS ごとに複数の revision を持ちます。本パッケージは `supportedRevisions.last` を実行時に選ぶので、**新しい OS では自動的に高精度なモデル**が使われます。

| リクエスト | 最新 revision が使える OS |
| --- | --- |
| 画像分類 `VNClassifyImageRequest` | macOS 14+ (rev2) |
| 文字認識 `VNRecognizeTextRequest` | macOS 13+ (rev3) |
| 顔検出 `VNDetectFaceRectanglesRequest` | macOS 12+ (rev3) |
| 人物検出 `VNDetectHumanRectanglesRequest` | macOS 12+ (rev2) |
| 動物検出 `VNRecognizeAnimalsRequest` | macOS 12+ (rev2) |
| バーコード `VNDetectBarcodesRequest` | macOS 14+ (rev4) |

## 抽出できる客観情報

`--json` で次の情報が得られます。

- `pixel_width` / `pixel_height` — 画像サイズ
- `classifications` — 画像分類ラベルと信頼度（`document`, `screenshot` など）
- `recognized_texts` — OCR で読み取った文字
- `face_count` / `human_count` — 検出した顔・人物の数
- `animals` — 検出した動物と信頼度
- `barcodes` — バーコード / QR の種別と内容
- `average_color` — 平均色（`#RRGGBB`）
- `revisions` — 実際に使った Vision の revision

```json
[
  {
    "path": "photo.jpg",
    "route": "vision-raw",
    "mode": "raw",
    "facts": {
      "pixel_width": 1800,
      "pixel_height": 1040,
      "classifications": [
        { "identifier": "document", "confidence": 0.204 },
        { "identifier": "screenshot", "confidence": 0.202 }
      ],
      "recognized_texts": [
        "ヒバチ株式会社請求書",
        "御請求金額：128,000円",
        "発行日：2026-10-01",
        "Invoice No. HB-2026-1001"
      ],
      "face_count": 0,
      "human_count": 0,
      "animals": [],
      "barcodes": [],
      "average_color": "#CBD5DD",
      "revisions": {
        "classifyImage": 2,
        "recognizeText": 3,
        "detectFaceRectangles": 3,
        "detectHumanRectangles": 2,
        "recognizeAnimals": 2,
        "detectBarcodes": 4
      }
    }
  }
]
```

## ビルドについて（macOS 11 をデプロイ先にする場合）

`Package.swift` のデプロイ先は `.macOS(.v11)` です。ただし直近の Xcode ツールチェーンでは、macOS 11 を明示する `swift build` が自動的に 12.0 へ切り上げられ、macOS 27 SDK の API を含むビルドでは下限 12.0 が強制されます。

そのため、**真に macOS 11 をサポートするバイナリ**が必要な場合は、Command Line Tools（SDK 26）でビルドします。

```bash
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  /Library/Developer/CommandLineTools/usr/bin/swift build -c release
otool -l .build/release/readimage | grep -A3 LC_BUILD_VERSION   # minos 11.0
```

Xcode ツールチェーンでビルドした場合は `minos 12.0` になりますが、いずれの場合も Foundation Models は弱リンクされるため、対応していない古い OS では自動的に Vision の経路へフォールバックします。

## テスト

```bash
swift test
```

## ライセンス

MIT License — Copyright (c) 2026 Hibachi Inc.
