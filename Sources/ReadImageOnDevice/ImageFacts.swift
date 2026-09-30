import Foundation

/// 画像分類ラベル（Vision の VNClassificationObservation 相当）。
public struct VisionLabel: Sendable, Codable, Equatable {
    public let identifier: String
    public let confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

/// 検出された矩形。座標は Vision 標準の正規化値（原点は左下、0.0〜1.0）。
public struct DetectedBox: Sendable, Codable, Equatable {
    public let label: String
    public let confidence: Double
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(label: String, confidence: Double, x: Double, y: Double, width: Double, height: Double) {
        self.label = label
        self.confidence = confidence
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// 検出されたバーコード / QR コード。
public struct Barcode: Sendable, Codable, Equatable {
    public let symbology: String
    public let payload: String?

    public init(symbology: String, payload: String?) {
        self.symbology = symbology
        self.payload = payload
    }
}

/// RGB 色。
public struct RGBColor: Sendable, Codable, Equatable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// 1 枚の画像からオンデバイスで抽出した客観情報。
///
/// plainText は AI による言い換えを一切していない、Vision の生の抽出結果
/// （＝ macOS 26 未満でも返せるテキスト）です。
public struct ImageFacts: Sendable, Codable, Equatable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let classifications: [VisionLabel]
    public let recognizedTexts: [String]
    public let faces: [DetectedBox]
    public let humans: [DetectedBox]
    public let animals: [DetectedBox]
    public let barcodes: [Barcode]
    public let averageColor: RGBColor
    /// 実際に使用した Vision リクエストの revision（リクエスト名 → revision）。
    public let revisions: [String: Int]

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        classifications: [VisionLabel],
        recognizedTexts: [String],
        faces: [DetectedBox],
        humans: [DetectedBox],
        animals: [DetectedBox],
        barcodes: [Barcode],
        averageColor: RGBColor,
        revisions: [String: Int]
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.classifications = classifications
        self.recognizedTexts = recognizedTexts
        self.faces = faces
        self.humans = humans
        self.animals = animals
        self.barcodes = barcodes
        self.averageColor = averageColor
        self.revisions = revisions
    }

    /// AI 整形前のテキスト。macOS 11 以降どこでもそのまま出力できる。
    public var plainText: String {
        var lines: [String] = []
        lines.append("- 画像サイズ: \(pixelWidth)x\(pixelHeight)")
        if !classifications.isEmpty {
            let s = classifications.prefix(8)
                .map { "\($0.identifier)(\(Int($0.confidence * 100))%)" }
                .joined(separator: ", ")
            lines.append("- 画像分類ラベル: \(s)")
        }
        if !recognizedTexts.isEmpty {
            lines.append("- 写っている文字(OCR): " + recognizedTexts.prefix(40).joined(separator: " / "))
        }
        if !faces.isEmpty { lines.append("- 顔の数: \(faces.count)") }
        if !humans.isEmpty { lines.append("- 人物の数: \(humans.count)") }
        if !animals.isEmpty {
            let s = animals.map { "\($0.label)(\(Int($0.confidence * 100))%)" }.joined(separator: ", ")
            lines.append("- 動物: \(s)")
        }
        if !barcodes.isEmpty {
            let s = barcodes.map { "\($0.symbology): \($0.payload ?? "(解読不可)")" }.joined(separator: " / ")
            lines.append("- コード: \(s)")
        }
        lines.append("- 平均色: \(averageColor.hex)")
        return lines.joined(separator: "\n")
    }
}
