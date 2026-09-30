import Foundation
import CoreGraphics

// Attachment / ImageAttachment（画像入力）は macOS 27 SDK で追加された API。
// macOS 27 SDK を同梱する Swift 6.4 以降でのみコンパイルし、それ以前の SDK
// （Xcode 26 / Command Line Tools 26 など）では画像入力経路を丸ごと除外する。
// これにより、macOS 11 をデプロイ先にしたまま、SDK 27 では最高精度、
// それ以前の SDK でも Vision + Foundation Models でビルドできる。
#if canImport(FoundationModels) && compiler(>=6.4)
import FoundationModels

/// macOS 27 以降の Foundation Models ネイティブ画像入力（マルチモーダル）経路。
@available(macOS 27.0, *)
enum NativeMultimodal {
    static func explain(
        cgImage: CGImage,
        prompt: String?,
        instructions: String
    ) async throws -> String {
        let attachment = Attachment(cgImage).label("image")
        let session = LanguageModelSession(instructions: instructions)
        let request = prompt ?? ReadImage.defaultPrompt
        let response = try await session.respond {
            request
            attachment
        }
        return response.content
    }
}
#endif
