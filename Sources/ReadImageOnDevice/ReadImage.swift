import Foundation
import CoreGraphics
import Dispatch
#if canImport(FoundationModels)
import FoundationModels
#endif

/// ReadImage on Device の共通エントリポイント。
///
/// 同じ API で、実行中の macOS に応じて「その OS で出せる最高精度」の結果を返します。
///
/// - macOS 27 以降 + Apple Intelligence: 画像を Foundation Models に直接渡して解説文を生成
/// - macOS 26 + Apple Intelligence: Vision で客観情報を抽出 → Foundation Models で言語化
/// - macOS 11〜25 / Apple Intelligence 無効: Vision の生の抽出結果（AI 整形前テキスト）
///
/// 出力は常にオンデバイスで完結し、画像や結果がネットワークに出ることはありません。
public enum ReadImage {

    /// 結果の種類。
    public enum Mode: Sendable {
        /// AI 整形をせず、Vision の抽出結果だけを返す（全 macOS 対応）。
        case raw
        /// その OS で使える最善の方法で日本語の解説文を生成する。
        case explain
    }

    /// 1 枚の画像に対する読み取り結果。
    public struct Result: Sendable {
        public let path: String
        /// 採用した処理経路（例: "vision+fm(macOS26)"）。
        public let route: String
        /// 最終的な出力テキスト。
        public let text: String
        /// Vision の客観情報（常に含まれる）。
        public let facts: ImageFacts

        public init(path: String, route: String, text: String, facts: ImageFacts) {
            self.path = path
            self.route = route
            self.text = text
            self.facts = facts
        }
    }

    /// Foundation Models がコンパイル時に取り込める SDK か。
    public static var hasFoundationModelsFramework: Bool {
        #if canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }

    /// 実行中の OS で Apple オンデバイス言語モデルが使えるか。
    public static var supportsLanguageModel: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
            return false
        }
        #endif
        return false
    }

    /// 画像を読み取り、指定モードで結果を返す。
    public static func read(
        path: String,
        mode: Mode = .explain,
        options: ReadImageAnalyzer.Options = .init(),
        instructions: String? = nil,
        prompt: String? = nil
    ) async throws -> Result {
        let cgImage = try ReadImageAnalyzer.loadCGImage(at: path)
        let facts = ReadImageAnalyzer.analyze(cgImage, options: options)

        switch mode {
        case .raw:
            return Result(path: path, route: "vision-raw", text: facts.plainText, facts: facts)
        case .explain:
            return await explain(path: path, cgImage: cgImage, facts: facts, instructions: instructions, prompt: prompt)
        }
    }

    /// すでに読み込んだ CGImage から読み取る。
    public static func read(
        cgImage: CGImage,
        mode: Mode = .explain,
        options: ReadImageAnalyzer.Options = .init(),
        instructions: String? = nil,
        prompt: String? = nil,
        path: String = "<memory>"
    ) async -> Result {
        let facts = ReadImageAnalyzer.analyze(cgImage, options: options)
        switch mode {
        case .raw:
            return Result(path: path, route: "vision-raw", text: facts.plainText, facts: facts)
        case .explain:
            return await explain(path: path, cgImage: cgImage, facts: facts, instructions: instructions, prompt: prompt)
        }
    }

    /// AI 整形前のテキスト（＝Vision の抽出結果）を返す。全 macOS で動作する。
    public static func rawText(at path: String, options: ReadImageAnalyzer.Options = .init()) throws -> String {
        try ReadImageAnalyzer.analyzeFile(at: path, options: options).plainText
    }

    /// 同期版。コマンドラインツールや既存の同期コードから呼ぶときに使う。
    ///
    /// macOS 11〜25 では Vision の生テキストを返し、Swift 並行ランタイムに
    /// 依存しないため、Apple Intelligence 非対応の古い Mac でもそのまま起動する。
    public static func readSync(
        path: String,
        mode: Mode = .explain,
        options: ReadImageAnalyzer.Options = .init(),
        instructions: String? = nil,
        prompt: String? = nil
    ) throws -> Result {
        let cgImage = try ReadImageAnalyzer.loadCGImage(at: path)
        let facts = ReadImageAnalyzer.analyze(cgImage, options: options)
        switch mode {
        case .raw:
            return Result(path: path, route: "vision-raw", text: facts.plainText, facts: facts)
        case .explain:
            return explainSync(path: path, cgImage: cgImage, facts: facts, instructions: instructions, prompt: prompt)
        }
    }

    private static func explainSync(
        path: String,
        cgImage: CGImage,
        facts: ImageFacts,
        instructions: String?,
        prompt: String?
    ) -> Result {
        let instr = instructions ?? defaultInstructions
        #if canImport(FoundationModels)
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            if let text = blockingValue({
                try await NativeMultimodal.explain(cgImage: cgImage, prompt: prompt, instructions: instr)
            }) {
                return Result(path: path, route: "native-multimodal(macOS27)", text: text, facts: facts)
            }
        }
        #endif
        if #available(macOS 26.0, *) {
            if let text = blockingValue({
                try await FoundationModelWriter.explain(
                    facts: facts,
                    instructions: instr,
                    promptPrefix: prompt ?? defaultPromptPrefix
                )
            }) {
                return Result(path: path, route: "vision+fm(macOS26)", text: text, facts: facts)
            }
        }
        #endif
        return Result(path: path, route: "vision-raw", text: facts.plainText, facts: facts)
    }

    #if canImport(FoundationModels)
    /// 非同期処理を同期的に待つ。macOS 26 以降でのみ到達する。
    @available(macOS 26.0, *)
    private static func blockingValue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) -> T? {
        let box = AsyncResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do { box.value = Swift.Result<T, Error>.success(try await operation()) }
            catch { box.value = Swift.Result<T, Error>.failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try? box.value?.get()
    }
    #endif

    // MARK: - 内部

    private static func explain(
        path: String,
        cgImage: CGImage,
        facts: ImageFacts,
        instructions: String?,
        prompt: String?
    ) async -> Result {
        let instr = instructions ?? defaultInstructions
        #if canImport(FoundationModels)
        #if compiler(>=6.4)
        // macOS 27+: 画像そのものをモデルに渡す（最高精度）。
        if #available(macOS 27.0, *) {
            do {
                let text = try await NativeMultimodal.explain(cgImage: cgImage, prompt: prompt, instructions: instr)
                return Result(path: path, route: "native-multimodal(macOS27)", text: text, facts: facts)
            } catch {
                // 失敗時は Vision + FM 経路へフォールバック。
            }
        }
        #endif
        // macOS 26: Vision の客観情報を Foundation Models で言語化。
        if #available(macOS 26.0, *) {
            do {
                let text = try await FoundationModelWriter.explain(
                    facts: facts,
                    instructions: instr,
                    promptPrefix: prompt ?? defaultPromptPrefix
                )
                return Result(path: path, route: "vision+fm(macOS26)", text: text, facts: facts)
            } catch {
                // モデル無効・失敗時は生テキストへフォールバック。
            }
        }
        #endif
        // macOS 11〜25、または Apple Intelligence が使えない場合。
        return Result(path: path, route: "vision-raw", text: facts.plainText, facts: facts)
    }

    // MARK: - 文言

    public static let defaultInstructions = """
    あなたは画像の内容を日本語で説明するアシスタントです。
    与えられた解析情報だけを根拠に、その画像が何の画像かを2〜4文で説明してください。
    解析情報に無い数値・固有名詞・出来事を創作しないでください。
    箇条書きは使わず、自然な文章で書いてください。
    """

    public static let defaultPromptPrefix = "次の解析結果をもとに、この画像の解説文を書いてください。"

    public static let defaultPrompt = "この画像に写っているものを日本語で説明してください。"
}
