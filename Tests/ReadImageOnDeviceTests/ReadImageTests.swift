import XCTest
import CoreGraphics
import ImageIO
import Vision
@testable import ReadImageOnDevice

final class ReadImageTests: XCTestCase {

    /// テスト用の単色画像を生成する。
    private func makeImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func testAnalyzeReturnsDimensions() {
        let cg = makeImage(width: 40, height: 20, red: 255, green: 0, blue: 0)
        let facts = ReadImageAnalyzer.analyze(cg)
        XCTAssertEqual(facts.pixelWidth, 40)
        XCTAssertEqual(facts.pixelHeight, 20)
    }

    func testAnalyzeReportsRevisions() {
        let cg = makeImage(width: 32, height: 32, red: 0, green: 128, blue: 255)
        let facts = ReadImageAnalyzer.analyze(cg)
        // OS でサポートされる revision が記録される。
        XCTAssertNotNil(facts.revisions["classifyImage"])
        XCTAssertNotNil(facts.revisions["recognizeText"])
        XCTAssertFalse(facts.revisions.isEmpty)
    }

    func testAverageColorIsApproximatelyCorrect() {
        let cg = makeImage(width: 64, height: 64, red: 255, green: 0, blue: 0)
        let facts = ReadImageAnalyzer.analyze(cg)
        XCTAssertEqual(facts.averageColor.r, 255, accuracy: 2)
        XCTAssertEqual(facts.averageColor.g, 0, accuracy: 2)
        XCTAssertEqual(facts.averageColor.b, 0, accuracy: 2)
    }

    func testPlainTextContainsSize() {
        let cg = makeImage(width: 10, height: 30, red: 0, green: 0, blue: 0)
        let facts = ReadImageAnalyzer.analyze(cg)
        XCTAssertTrue(facts.plainText.contains("10x30"))
    }

    func testRawModeNeverUsesModel() async throws {
        let cg = makeImage(width: 16, height: 16, red: 10, green: 20, blue: 30)
        let result = await ReadImage.read(cgImage: cg, mode: .raw)
        XCTAssertEqual(result.route, "vision-raw")
        XCTAssertEqual(result.text, result.facts.plainText)
    }

    func testLoadCGImageFailsForMissingFile() {
        XCTAssertThrowsError(try ReadImageAnalyzer.loadCGImage(at: "/nonexistent/xyz.png")) { error in
            guard case ReadImageError.imageNotFound = error else {
                return XCTFail("expected imageNotFound, got \(error)")
            }
        }
    }

    func testAnalyzeFileRoundTrip() throws {
        let cg = makeImage(width: 24, height: 24, red: 50, green: 60, blue: 70)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("readimage-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return XCTFail("could not create destination")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let facts = try ReadImageAnalyzer.analyzeFile(at: url.path)
        XCTAssertEqual(facts.pixelWidth, 24)
    }

    /// 同期 API は Swift 並行ランタイムに依存せず、macOS 11〜25 でも動く経路。
    func testReadSyncRawReturnsPlainText() throws {
        let cg = makeImage(width: 12, height: 34, red: 200, green: 100, blue: 0)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("readimage-sync-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return XCTFail("could not create destination")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let result = try ReadImage.readSync(path: url.path, mode: .raw)
        XCTAssertEqual(result.route, "vision-raw")
        XCTAssertTrue(result.text.contains("12x34"))
    }

    /// useLatestRevision が false のときは OS 既定の revision が使われる。
    func testRevisionOverride() {
        let cg = makeImage(width: 8, height: 8, red: 1, green: 2, blue: 3)
        let facts = ReadImageAnalyzer.analyze(cg, options: .init(useLatestRevision: false))
        XCTAssertEqual(facts.revisions["recognizeText"], VNRecognizeTextRequest.defaultRevision)
    }

    /// useLatestRevision（既定）では各 OS の最新 revision が選ばれる。
    func testLatestRevisionSelection() {
        let cg = makeImage(width: 8, height: 8, red: 1, green: 2, blue: 3)
        let facts = ReadImageAnalyzer.analyze(cg)
        XCTAssertEqual(facts.revisions["recognizeText"], VNRecognizeTextRequest.supportedRevisions.last)
        XCTAssertEqual(facts.revisions["classifyImage"], VNClassifyImageRequest.supportedRevisions.last)
    }
}

private func XCTAssertEqual(_ a: UInt8, _ b: UInt8, accuracy: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), accuracy, file: file, line: line)
}
