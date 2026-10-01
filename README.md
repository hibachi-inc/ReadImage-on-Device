# ReadImage on Device

## これはなに

**iPhone / iPad / Mac で動く、完全オンデバイスの画像認識 API です。**

画像を渡すと「何が写っているか」を日本語の文章で返します。処理はすべて Apple のオンデバイスフレームワーク（Vision / Foundation Models）で行われるため、**画像がネットワークに送られることはありません**。API キーも不要で、サーバーもクラウドも使いません。

同じ API のまま、**動いている OS ごとに「その OS が出せる最高精度」**を自動で使います。新しい OS ほど賢くなり、古い OS でも動きます。

Swift パッケージ（ライブラリ）と、macOS 用のコマンドラインツール（`readimage`）が入っています。

## 特徴

- **macOS 11 以降 / iOS 13 以降**で動作（ライブラリ）。CLI は macOS 用
- **完全オフライン・オンデバイス**（通信なし・API キー不要）
- **OS に応じて自動で最高精度を選択**（Vision の revision を自動で最新に）
- **日本語の解説文を返す**（Apple Intelligence 対応 OS）。非対応 OS でも OCR などの生テキストを返す
- **共通規格風のかんたん API**（stdin/stdout の JSON、Swift からも数行）

```bash
$ readimage photo.jpg

この画像は、白い紙に印刷された日本語の請求書のスクリーンショットです。
請求金額は128,000円、発行日は2026年10月1日と記載されています。
```

## ユースケース

**画像を外に出せない場面で、そのまま使えます。** 処理が端末内で完結するので、機密書類や個人の写真でも、クラウドに預けずに文字起こしやタグ付けができます。

- **テキスト専用の LLM に画像を理解させる** — vision 非対応の LLM でも、先にこのパッケージで画像を文章化してから渡せば、内容を踏まえた回答が得られます。画像は端末内で説明文・文字起こしに変換し、LLM にはテキストだけを流せます。
- **レシート・請求書の読み取り** — OCR で金額・日付・番号を文字起こし。経理データを外部サービスに送らずに済む。
- **写真ライブラリの整理・検索** — 分類ラベル（`document`, `screenshot` など）と OCR 結果で、写真にローカルでタグを付けて検索に使う。
- **スクリーンショットの内容把握** — 画面を撮って「何が写っているか」を日本語の文章で得る。読み上げや内容の要約の下地に。
- **オフライン・閉域環境の画像メモ** — ネットが無い現場でも、撮った写真の説明と読み取り文字をその場で得る。
- **アプリのアクセシビリティ補助** — 画像の内容を文章化し、VoiceOver などの説明として使う。

vision 非対応の LLM と組み合わせる場合は、画像を文章に変えてからテキストとして渡します。

```bash
# 画像を説明文にしてから、テキスト専用の LLM に渡す
readimage receipt.jpg | your-llm "この内容を勘定科目に仕訳して"

# 文字起こしだけが欲しいとき（全 OS 対応）
readimage --raw receipt.jpg | your-llm "この請求書の支払期日を教えて"
```

CLI なら、フォルダ内の画像をまとめて処理できます。

```bash
# ディレクトリ内の画像をまとめて解説文にする
readimage ./scans/*.png

# 文字起こしだけをまとめてファイルにする（全 OS 対応）
readimage --raw ./scans/*.png > texts.txt

# 加工しやすいように JSON で受け取る
readimage --json form.png > facts.json
```

Swift アプリに組み込む場合も、渡すのは `CGImage` 1 枚だけです。

```swift
let result = try await ReadImage.read(cgImage: cgImage, path: "receipt.jpg")
saveToLocalDatabase(result.text)   // 端末内で完結、外部送信なし
```

## 使い方

### インストール

Swift Package Manager で使えます。macOS アプリでも iOS アプリでも同じ API です。

```swift
dependencies: [
    .package(url: "https://github.com/hibachi-inc/ReadImage-on-Device", from: "0.1.0")
]
```

iOS アプリで使う場合は、`UIImage` から `CGImage` を取り出して渡します。

```swift
import ReadImageOnDevice

guard let cgImage = uiImage.cgImage else { return }
let result = await ReadImage.read(cgImage: cgImage, mode: .explain, path: "photo.jpg")
print(result.text)   // iPhone でも日本語の解説文が返る
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
| `--raw` | AI を使わず、Vision の生の抽出結果（AI 整形前テキスト）だけを返す。全 OS 対応 |
| `--explain` | その OS で使える最善の方法で解説文を生成する（既定） |
| `-p, --prompt <text>` | 解説の依頼文を差し替える |
| `-i, --instructions <text>` | 生成時の system 指示を差し替える |
| `--languages <a,b>` | OCR 言語（既定: `ja-JP,en-US`） |
| `--json` | Vision の客観情報を JSON で出力する |
| `--no-animals` | 動物検出を行わない |
| `--no-barcodes` | バーコード / QR 検出を行わない |

終了コード:

| コード | 意味 |
| --- | --- |
| `0` | すべての画像を処理できた |
| `1` | 1 枚以上の画像で失敗した（存在しないパス、未対応形式など）。パイプやシェル連鎖で失敗を検知できる |
| `2` | 引数エラー（画像パス未指定、未知のオプション、空の標準入力など） |

複数の画像を渡した場合、1 枚でも失敗すると `1` で終了します。`--json` では成否にかかわらず各画像の結果が配列で出るので、失敗は `error` フィールドで判別できます。

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

同じ `ReadImage.read(...)` が、実行中の OS に応じて経路を選びます（macOS と iOS で同じ表）。

| 実行環境 | 採用する経路 | 返すもの |
| --- | --- | --- |
| **macOS 27 / iOS 27 以降** + Apple Intelligence | `native-multimodal(macOS27)` | 画像を Foundation Models に直接渡して解説文を生成 |
| **macOS 26 / iOS 26** + Apple Intelligence | `vision+fm(macOS26)` | Vision で客観情報を抽出 → Foundation Models で日本語化 |
| **macOS 11〜25 / iOS 13〜25**（Apple Intelligence 無効を含む） | `vision-raw` | Vision の生の抽出結果（AI 整形前テキスト） |

どの経路でも、Vision による客観情報（`ImageFacts`）は常に取得できるので、生テキストは macOS 11 / iOS 13 から使えます。

> **iOS で Apple Intelligence を使うには**: 言語モデル（Foundation Models）は Apple Intelligence 対応端末（A17 Pro / M シリーズ以降）でのみ利用できます。非対応端末では自動的に `vision-raw` 経路になります。

### 各 OS の「最高精度」の選び方

Vision の各リクエストは OS ごとに複数の revision を持ちます。本パッケージは `supportedRevisions.last` を実行時に選ぶので、**新しい OS では自動的に高精度なモデル**が使われます。revision は macOS / iOS で共通です。

| リクエスト | 最新 revision が使える OS |
| --- | --- |
| 画像分類 `VNClassifyImageRequest` | macOS 14+ / iOS 17+ (rev2) |
| 文字認識 `VNRecognizeTextRequest` | macOS 13+ / iOS 16+ (rev3) |
| 顔検出 `VNDetectFaceRectanglesRequest` | macOS 12+ / iOS 15+ (rev3) |
| 人物検出 `VNDetectHumanRectanglesRequest` | macOS 12+ / iOS 15+ (rev2) |
| 動物検出 `VNRecognizeAnimalsRequest` | macOS 12+ / iOS 15+ (rev2) |
| バーコード `VNDetectBarcodesRequest` | macOS 14+ / iOS 17+ (rev4) |

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

## デプロイ先について（macOS 11 / iOS 13 を下限にする場合）

`Package.swift` は `platforms: [.macOS(.v11), .iOS(.v13)]` を宣言しています。ソースコード自体は macOS 11 / iOS 13 の API だけで型チェックが通ります。

ただし直近の Xcode ツールチェーン（Xcode 27）は、サポートする下限を**macOS 12.0 / iOS 15.0** に引き上げています。そのため Xcode 27 でビルドすると、宣言した下限は自動的に切り上げられます（macOS 11 を明示した `swift build` は 12.0、iOS 13 は 15.0 になります）。

そのため、**真に macOS 11 をサポートするバイナリ**が必要な場合は、Command Line Tools（SDK 26）でビルドします。

```bash
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  /Library/Developer/CommandLineTools/usr/bin/swift build -c release
otool -l .build/release/readimage | grep -A3 LC_BUILD_VERSION   # minos 11.0
```

Xcode ツールチェーンでビルドした場合は `minos 12.0` になりますが、いずれの場合も Foundation Models は弱リンクされるため、対応していない古い OS では自動的に Vision の経路へフォールバックします。

iOS 13〜14 を真に下限にするには、当時の iOS SDK を含む Xcode 26 以前のツールチェーンでビルドしてください。Xcode 27 では iOS 15 以上が下限になります。

## テスト

```bash
swift test
```

## ライセンス

MIT License — Copyright (c) 2026 Hibachi Inc.
