import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// macOS 26 以降の Foundation Models で、Vision の抽出結果を日本語の解説文に整える経路。
@available(macOS 26.0, *)
enum FoundationModelWriter {
    /// Vision の客観情報（facts）を根拠に解説文を生成する。
    static func explain(
        facts: ImageFacts,
        instructions: String,
        promptPrefix: String
    ) async throws -> String {
        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability {
            throw ReadImageError.modelUnavailable(String(describing: reason))
        }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        \(promptPrefix)

        \(facts.plainText)
        """
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif
