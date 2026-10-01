import Foundation
import Vision
import CoreImage
import CoreGraphics
import ImageIO

/// オンデバイスで画像を解析する際のエラー。
public enum ReadImageError: Error, CustomStringConvertible {
    case imageNotFound(String)
    case imageDecodeFailed(String)
    case modelUnavailable(String)

    public var description: String {
        switch self {
        case .imageNotFound(let p): return "画像が見つかりません: \(p)"
        case .imageDecodeFailed(let p): return "画像を読み込めません(未対応形式の可能性): \(p)"
        case .modelUnavailable(let r): return "Apple オンデバイスモデルが利用できません: \(r)"
        }
    }
}

/// Apple の Vision フレームワークだけで画像の客観情報を抽出する。
///
/// macOS 11 以降で動作し、各 OS で利用できる最新 revision（＝その OS の最高精度）を
/// 自動選択する。Foundation Models を一切使わないため、Apple Intelligence 非対応の
/// 古い Mac でも同じ API で動く。
public enum ReadImageAnalyzer {

    public struct Options: Sendable {
        /// OCR の認識言語（優先順）。
        public var languages: [String]
        /// 画像分類ラベルの最大件数。
        public var maxClassifications: Int
        /// 画像分類ラベルの最低信頼度。
        public var minClassificationConfidence: Double
        /// その OS で使える最新 revision を選ぶか（既定 true）。
        public var useLatestRevision: Bool
        /// 動物の検出を行うか。
        public var detectAnimals: Bool
        /// バーコード / QR の検出を行うか。
        public var detectBarcodes: Bool

        public init(
            languages: [String] = ["ja-JP", "en-US"],
            maxClassifications: Int = 10,
            minClassificationConfidence: Double = 0.05,
            useLatestRevision: Bool = true,
            detectAnimals: Bool = true,
            detectBarcodes: Bool = true
        ) {
            self.languages = languages
            self.maxClassifications = maxClassifications
            self.minClassificationConfidence = minClassificationConfidence
            self.useLatestRevision = useLatestRevision
            self.detectAnimals = detectAnimals
            self.detectBarcodes = detectBarcodes
        }
    }

    /// ファイルから CGImage を読み込む（HEIC / PNG / JPEG / TIFF など）。
    public static func loadCGImage(at path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadImageError.imageNotFound(url.path)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ReadImageError.imageDecodeFailed(url.path)
        }
        return cg
    }

    /// CGImage から客観情報を抽出する。
    public static func analyze(_ cgImage: CGImage, options: Options = Options()) -> ImageFacts {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var revisions: [String: Int] = [:]

        func applyRevision<R: VNRequest>(to request: R, name: String) {
            if options.useLatestRevision, let latest = R.supportedRevisions.last {
                request.revision = latest
            }
            revisions[name] = request.revision
        }

        // 1. 画像分類
        var classifications: [VisionLabel] = []
        let classify = VNClassifyImageRequest()
        applyRevision(to: classify, name: "classifyImage")
        if (try? handler.perform([classify])) != nil, let results = classify.results {
            classifications = results
                .filter { $0.confidence > Float(options.minClassificationConfidence) }
                .sorted { $0.confidence > $1.confidence }
                .prefix(options.maxClassifications)
                .map { VisionLabel(identifier: $0.identifier, confidence: Double($0.confidence)) }
        }

        // 2. 文字認識 (OCR)
        var texts: [String] = []
        let ocr = VNRecognizeTextRequest()
        ocr.recognitionLanguages = options.languages
        ocr.recognitionLevel = .accurate
        ocr.usesLanguageCorrection = true
        applyRevision(to: ocr, name: "recognizeText")
        if (try? handler.perform([ocr])) != nil, let results = ocr.results {
            texts = results.compactMap { $0.topCandidates(1).first?.string }
        }

        // 3. 顔検出
        var faces: [DetectedBox] = []
        let face = VNDetectFaceRectanglesRequest()
        applyRevision(to: face, name: "detectFaceRectangles")
        if (try? handler.perform([face])) != nil, let results = face.results {
            faces = results.map {
                DetectedBox(
                    label: "face",
                    confidence: Double($0.confidence),
                    x: Double($0.boundingBox.origin.x),
                    y: Double($0.boundingBox.origin.y),
                    width: Double($0.boundingBox.width),
                    height: Double($0.boundingBox.height)
                )
            }
        }

        // 4. 人物検出（macOS 11 以降）
        var humans: [DetectedBox] = []
        if #available(macOS 11.0, *) {
            let human = VNDetectHumanRectanglesRequest()
            if #available(macOS 12.0, iOS 15.0, *) {
                human.upperBodyOnly = false
            }
            applyRevision(to: human, name: "detectHumanRectangles")
            if (try? handler.perform([human])) != nil, let results = human.results {
                humans = results.map {
                    DetectedBox(
                        label: "human",
                        confidence: Double($0.confidence),
                        x: Double($0.boundingBox.origin.x),
                        y: Double($0.boundingBox.origin.y),
                        width: Double($0.boundingBox.width),
                        height: Double($0.boundingBox.height)
                    )
                }
            }
        }

        // 5. 動物検出
        var animals: [DetectedBox] = []
        if options.detectAnimals {
            let animal = VNRecognizeAnimalsRequest()
            applyRevision(to: animal, name: "recognizeAnimals")
            if (try? handler.perform([animal])) != nil, let results = animal.results {
                animals = results.flatMap { obs -> [DetectedBox] in
                    (obs.labels).map { label in
                        DetectedBox(
                            label: label.identifier,
                            confidence: Double(label.confidence * obs.confidence),
                            x: Double(obs.boundingBox.origin.x),
                            y: Double(obs.boundingBox.origin.y),
                            width: Double(obs.boundingBox.width),
                            height: Double(obs.boundingBox.height)
                        )
                    }
                }
            }
        }

        // 6. バーコード / QR
        var barcodes: [Barcode] = []
        if options.detectBarcodes {
            let code = VNDetectBarcodesRequest()
            applyRevision(to: code, name: "detectBarcodes")
            if (try? handler.perform([code])) != nil, let results = code.results {
                barcodes = results.map {
                    Barcode(symbology: $0.symbology.rawValue, payload: $0.payloadStringValue)
                }
            }
        }

        // 7. 平均色
        let color = averageColor(of: cgImage)

        return ImageFacts(
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            classifications: classifications,
            recognizedTexts: texts,
            faces: faces,
            humans: humans,
            animals: animals,
            barcodes: barcodes,
            averageColor: color,
            revisions: revisions
        )
    }

    /// ファイルパスから直接解析する。
    public static func analyzeFile(at path: String, options: Options = Options()) throws -> ImageFacts {
        try analyze(loadCGImage(at: path), options: options)
    }

    private static func averageColor(of cg: CGImage) -> RGBColor {
        let ci = CIImage(cgImage: cg)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ])
        guard let output = filter?.outputImage else { return RGBColor(r: 0, g: 0, b: 0) }
        var px = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output,
            toBitmap: &px,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return RGBColor(r: px[0], g: px[1], b: px[2])
    }
}
