import Foundation
import CoreGraphics
import ReadImageOnDevice

// MARK: - 引数

struct Options {
    var inputs: [String] = []
    var mode: ReadImage.Mode = .explain
    var explicitMode = false
    var prompt: String? = nil
    var instructions: String? = nil
    var languages: [String] = ["ja-JP", "en-US"]
    var json = false
    var noAnimals = false
    var noBarcodes = false
    var help = false
}

let version = "0.1.0"

func printUsage() {
    print("""
    readimage — Apple オンデバイスで画像を読む（ReadImage on Device）

    使い方:
      readimage <画像> [<画像> ...] [options]
      cat image.png | readimage -            # 標準入力から読む

    モード:
      --raw             AI を使わず、Vision の生の抽出結果だけを返す（全 macOS 対応）
      --explain         その OS で使える最善の方法で解説文を生成する（既定）

    オプション:
      -p, --prompt <text>        解説の依頼文を差し替える（--explain 時）
      -i, --instructions <text>  生成時の system 指示を差し替える（--explain 時）
          --languages <a,b>      OCR 言語（既定: ja-JP,en-US）
          --json                 Vision の客観情報を JSON で出力する
          --no-animals           動物検出を行わない
          --no-barcodes          バーコード/QR 検出を行わない
      -h, --help                 このヘルプ
          --version              バージョン表示

    出力の経路（route）:
      vision-raw              Vision の生の抽出結果（AI 整形なし）
      vision+fm(macOS26)      Vision → Foundation Models で言語化
      native-multimodal(macOS27)  Foundation Models に画像を直接入力
    """)
}

func parseArgs(_ args: [String]) -> Options {
    var o = Options()
    var i = 0
    func value(_ name: String) -> String? {
        i += 1
        guard i < args.count else {
            FileHandle.standardError.write(Data("\(name) には値が必要です\n".utf8))
            return nil
        }
        return args[i]
    }
    while i < args.count {
        let a = args[i]
        switch a {
        case "-h", "--help": o.help = true
        case "--version": print("readimage \(version)"); exit(0)
        case "--raw": o.mode = .raw; o.explicitMode = true
        case "--explain": o.mode = .explain; o.explicitMode = true
        case "-p", "--prompt": if let v = value(a) { o.prompt = v }
        case "-i", "--instructions": if let v = value(a) { o.instructions = v }
        case "--languages": if let v = value(a) {
            o.languages = v.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        case "--json": o.json = true
        case "--no-animals": o.noAnimals = true
        case "--no-barcodes": o.noBarcodes = true
        default:
            if a.hasPrefix("-") && a != "-" {
                FileHandle.standardError.write(Data("未知のオプション: \(a)\n".utf8))
                exit(2)
            } else {
                o.inputs.append(a)
            }
        }
        i += 1
    }
    return o
}

// MARK: - 出力 DTO

struct ResultDTO: Encodable {
    let path: String
    let route: String
    let mode: String
    let text: String?
    let facts: FactsDTO?
    let error: String?
}

struct FactsDTO: Encodable {
    let pixelWidth: Int
    let pixelHeight: Int
    let classifications: [LabelDTO]
    let recognizedTexts: [String]
    let faceCount: Int
    let humanCount: Int
    let animals: [LabelDTO]
    let barcodes: [BarcodeDTO]
    let averageColor: String
    let revisions: [String: Int]
}

struct LabelDTO: Encodable {
    let identifier: String
    let confidence: Double
}

struct BarcodeDTO: Encodable {
    let symbology: String
    let payload: String?
}

func factsDTO(_ f: ImageFacts) -> FactsDTO {
    FactsDTO(
        pixelWidth: f.pixelWidth,
        pixelHeight: f.pixelHeight,
        classifications: f.classifications.map { LabelDTO(identifier: $0.identifier, confidence: $0.confidence) },
        recognizedTexts: f.recognizedTexts,
        faceCount: f.faces.count,
        humanCount: f.humans.count,
        animals: f.animals.map { LabelDTO(identifier: $0.label, confidence: $0.confidence) },
        barcodes: f.barcodes.map { BarcodeDTO(symbology: $0.symbology, payload: $0.payload) },
        averageColor: f.averageColor.hex,
        revisions: f.revisions
    )
}

// MARK: - 実行

let options = parseArgs(Array(CommandLine.arguments.dropFirst()))

if options.help {
    printUsage()
    exit(0)
}

var inputs = options.inputs
// 標準入力対応: "-" が指定されたら stdin から読み、一時ファイルに保存して解析する。
var stdinTemp: String? = nil
if inputs.contains("-") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if data.isEmpty {
        FileHandle.standardError.write(Data("標準入力が空です。\n".utf8))
        exit(2)
    }
    let tmp = NSTemporaryDirectory() + "readimage-stdin-\(UUID().uuidString).img"
    FileManager.default.createFile(atPath: tmp, contents: data)
    stdinTemp = tmp
    inputs = inputs.map { $0 == "-" ? tmp : $0 }
}
defer {
    if let t = stdinTemp { try? FileManager.default.removeItem(atPath: t) }
}

if inputs.isEmpty {
    FileHandle.standardError.write(Data("画像パスを1つ以上指定してください。(-h でヘルプ)\n".utf8))
    exit(2)
}

let analyzerOptions = ReadImageAnalyzer.Options(
    languages: options.languages,
    detectAnimals: !options.noAnimals,
    detectBarcodes: !options.noBarcodes
)

func describeMode() -> String {
    options.mode == .raw ? "raw" : "explain"
}

// 同期 API を使うことで、Swift 並行ランタイムの無い macOS 11〜12 でも起動できる。
let ordered: [ResultDTO] = inputs.map { input in
    do {
        let result = try ReadImage.readSync(
            path: input,
            mode: options.mode,
            options: analyzerOptions,
            instructions: options.instructions,
            prompt: options.prompt
        )
        return ResultDTO(
            path: input,
            route: result.route,
            mode: describeMode(),
            text: options.json ? nil : result.text,
            facts: options.json ? factsDTO(result.facts) : nil,
            error: nil
        )
    } catch {
        return ResultDTO(path: input, route: "none", mode: describeMode(), text: nil, facts: nil, error: "\(error)")
    }
}
let displayPath = { (p: String) -> String in p == stdinTemp ? "-" : p }

if options.json {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    enc.keyEncodingStrategy = .convertToSnakeCase
    let display = ordered.map { r in
        ResultDTO(path: displayPath(r.path), route: r.route, mode: r.mode, text: r.text, facts: r.facts, error: r.error)
    }
    print(String(data: try! enc.encode(display), encoding: .utf8)!)
} else {
    for r in ordered {
        print("=== \(displayPath(r.path))  [route: \(r.route)] ===")
        if let e = r.error { print("エラー: \(e)") }
        if let text = r.text { print(text) }
        print("")
    }
}
