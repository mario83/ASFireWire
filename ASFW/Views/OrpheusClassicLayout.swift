import SwiftUI

/// AppKit-style rectangle (origin at the bottom left) taken from Orpheus.app 1.10.
nonisolated struct OrpheusClassicBox: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    func swiftRect(parentHeight: CGFloat) -> CGRect {
        CGRect(x: x, y: parentHeight - y - height, width: width, height: height)
    }
}

nonisolated enum OrpheusClassicLayout {
    static let window = CGSize(width: 703, height: 678)
    static let main = CGSize(width: 640, height: 479)
    static let mainOrigin = CGPoint(x: 30, y: 53)
    static let pageSize = CGSize(width: 640, height: 358)
    static let column: CGFloat = 46
    static let firstColumn: CGFloat = 8

    static func columnX(_ index: Int) -> CGFloat { firstColumn + CGFloat(index) * column }

    static func analogMeterX(_ index: Int) -> CGFloat { 31 + CGFloat(index) * column }

    static let meterWell = CGSize(width: 17, height: 159)
    static let meterOverloadHeight: CGFloat = 19
    static let meterBottom: CGFloat = 69
    static var meterStackHeight: CGFloat { meterWell.height + meterOverloadHeight }

    static func meterBox(x: CGFloat) -> OrpheusClassicBox {
        OrpheusClassicBox(x, meterBottom, meterWell.width, meterStackHeight)
    }

    static func mixGainBox(input: Int, linked: Bool) -> OrpheusClassicBox {
        let x = linked ? columnX(input & ~1) + 13 : columnX(input)
        return OrpheusClassicBox(x, 49, 20, 199)
    }

    static func mixControlBox(input: Int, linked: Bool, y: CGFloat, height: CGFloat = 16) -> OrpheusClassicBox {
        let x = linked ? columnX(input & ~1) + 23 : columnX(input)
        return OrpheusClassicBox(x, y, 40, height)
    }

    static func mixMeterBox(input: Int, linked: Bool) -> OrpheusClassicBox {
        let pair = input & ~1
        let x: CGFloat
        if linked {
            x = analogMeterX(pair) + 10 + CGFloat(input & 1) * 20
        } else {
            x = analogMeterX(input)
        }
        return meterBox(x: x)
    }

    static let tabs: [(title: String, box: OrpheusClassicBox, image: String)] = [
        ("Input", OrpheusClassicBox(1, 359, 79, 16), "tabInput"),
        ("Output", OrpheusClassicBox(83, 359, 93, 16), "tabOutput"),
        ("A1/2", OrpheusClassicBox(223, 359, 46, 16), "tabA12"),
        ("A3/4", OrpheusClassicBox(269, 359, 46, 16), "tabA34"),
        ("A5/6", OrpheusClassicBox(315, 359, 46, 16), "tabA56"),
        ("A7/8", OrpheusClassicBox(364, 359, 46, 16), "tabA78"),
        ("D1/2", OrpheusClassicBox(410, 359, 46, 16), "tabD12"),
        ("Phones", OrpheusClassicBox(457, 359, 46, 16), "tabHeadphones"),
        ("ADAT", OrpheusClassicBox(504, 359, 65, 16), "tabAdat"),
        ("Diagram", OrpheusClassicBox(572, 359, 68, 16), "tabDiagram"),
    ]

    static let mixLabelImages = ["mixAO12", "mixAO34", "mixAO56", "mixAO78", "mixDO12", "mixHP"]
}

nonisolated enum OrpheusClassicPalette {
    static let beige = Color(red: 0.835, green: 0.808, blue: 0.757)
    static let taupe = Color(red: 0.545, green: 0.518, blue: 0.494)
    static let well = Color(red: 0.780, green: 0.757, blue: 0.722)
    static let chrome = Color(red: 0.72, green: 0.76, blue: 0.82)
    static let chromeDark = Color(red: 0.45, green: 0.49, blue: 0.55)
    static let header = Color(red: 0.16, green: 0.17, blue: 0.22)
    static let headerSilver = Color(red: 0.78, green: 0.82, blue: 0.87)
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let caption = Color(red: 0.42, green: 0.44, blue: 0.45)
    static let ledOn = Color(red: 0.85, green: 1.0, blue: 0.35)
    static let ledOff = Color(red: 0.35, green: 0.38, blue: 0.32)
    static let clip = Color(red: 0.95, green: 0.22, blue: 0.18)
    static let overkiller = Color(red: 0.2, green: 0.85, blue: 0.35)
    static let thumb = Color(red: 0.82, green: 0.84, blue: 0.86)
    static let thumbPink = Color(red: 0.92, green: 0.55, blue: 0.72)
    static let thumbBlue = Color(red: 0.45, green: 0.72, blue: 0.92)
    static let comboFill = Color(red: 0.22, green: 0.24, blue: 0.26)
    static let comboPale = Color(red: 0.38, green: 0.40, blue: 0.42)
}

/// Captions copied from the vendor's number formatters, not from its bitmaps.
nonisolated enum OrpheusClassicCaption {
    static func mixGain(_ raw: Int16) -> String {
        guard raw != OrpheusLevel.silent else { return "-INF" }
        var integer = Int(Int8(truncatingIfNeeded: raw >> 8))
        let fraction: Int
        switch Int8(truncatingIfNeeded: raw) {
        case 0: fraction = 0
        case -65:
            integer += 1
            fraction = 25
        case 127:
            integer += 1
            fraction = 50
        case 63:
            integer += 1
            fraction = 75
        default:
            fraction = 0
        }
        var text = String(format: "%d.%02d", integer, fraction)
        if integer == 0 && fraction != 0 { text = "-" + text }
        return text
    }

    static func masterVolume(_ raw: Int16) -> String {
        guard raw != OrpheusLevel.silent else { return "-INF" }
        return String(Int(Int8(truncatingIfNeeded: raw >> 8)))
    }

    static func pan(_ value: Int8) -> String {
        if value == 0 { return ">0<" }
        return value < 0 ? "<\(-value)" : "\(value)>"
    }

    static func analogGain(_ value: UInt8) -> String {
        String(format: "%d.00", value)
    }

    /// Parses the vendor pan caption (`>0<`, `<12`, `7>`) or a typed integer.
    static func parsePan(_ text: String) -> Int8? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard !trimmed.isEmpty else { return nil }

        let value: Int
        if trimmed == ">0<" || trimmed == ">0" || trimmed == "0<" || trimmed == "0" {
            value = 0
        } else if trimmed.hasPrefix("<"), let parsed = Int(trimmed.dropFirst().filter(\.isNumber)) {
            value = -parsed
        } else if trimmed.hasSuffix(">"), let parsed = Int(trimmed.dropLast()) {
            value = parsed
        } else if let parsed = Int(trimmed) {
            value = parsed
        } else {
            return nil
        }
        return Int8(clamping: min(max(value, -20), 20))
    }
}

enum OrpheusClassicPage: Int, CaseIterable, Identifiable {
    case input, output, mixA12, mixA34, mixA56, mixA78, mixD12, mixHP, adat, diagram

    var id: Int { rawValue }
    var mixBus: Int? { (2...7).contains(rawValue) ? rawValue - 2 : nil }
}
