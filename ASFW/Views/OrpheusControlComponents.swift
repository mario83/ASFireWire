import SwiftUI

struct OrpheusChoicePicker: View {
    let title: String
    let choices: [OrpheusChoice]
    let selection: UInt8
    let onSelect: (UInt8) -> Void

    var body: some View {
        Picker(title, selection: Binding(get: { selection }, set: onSelect)) {
            ForEach(OrpheusChoices.including(selection, in: choices)) { choice in
                Text(choice.label).tag(choice.value)
            }
        }
    }
}

/// Maps a signed Q8.8 dB value onto a slider whose leftmost position is -inf.
nonisolated struct OrpheusDecibelMapping {
    var floorDecibels: Double = -96
    var ceilingDecibels: Double = 0

    var range: ClosedRange<Double> { floorDecibels...ceilingDecibels }

    func sliderValue(_ raw: Int16) -> Double {
        guard let decibels = OrpheusLevel.decibels(raw) else { return floorDecibels }
        return min(max(decibels, floorDecibels), ceilingDecibels)
    }

    func raw(_ sliderValue: Double) -> Int16 {
        sliderValue <= floorDecibels ? OrpheusLevel.silent : OrpheusLevel.raw(decibels: sliderValue)
    }
}

struct OrpheusGainSlider: View {
    let title: String
    let raw: Int16
    var mapping = OrpheusDecibelMapping()
    var step: Double = 0.5
    let onChange: (Int16) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 110, alignment: .leading)
            Slider(value: Binding(get: { mapping.sliderValue(raw) },
                                  set: { onChange(mapping.raw($0)) }),
                   in: mapping.range,
                   step: step)
            Text(OrpheusLevel.format(raw, fractionDigits: 1))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 72, alignment: .trailing)
        }
    }
}

struct OrpheusVerticalFader: View {
    let raw: Int16
    var mapping = OrpheusDecibelMapping()
    let onChange: (Int16) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(OrpheusLevel.format(raw, fractionDigits: 1).replacingOccurrences(of: " dB", with: ""))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { mapping.sliderValue(raw) },
                                  set: { onChange(mapping.raw($0)) }),
                   in: mapping.range,
                   step: 0.25)
                .frame(width: 130, height: 22)
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 130)
        }
    }
}

struct OrpheusInputTypeBadge: View {
    let rawType: UInt8

    var body: some View {
        let type = OrpheusAnalogInputType(rawValue: rawType)
        Text(type?.label ?? "Type \(rawType)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color(for: type).opacity(0.25), in: Capsule())
            .foregroundStyle(color(for: type))
    }

    private func color(for type: OrpheusAnalogInputType?) -> Color {
        switch type {
        case .line: return .green
        case .mic: return .pink
        case .instrument: return .blue
        case nil: return .secondary
        }
    }
}

struct OrpheusMeterBar: View {
    let label: String
    let level: UInt16

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 36, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(fraction > 0.9 ? Color.red : (fraction > 0.6 ? Color.yellow : Color.green))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text(String(format: "%04X", level))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var fraction: CGFloat { CGFloat(level) / CGFloat(UInt16.max) }
}

struct OrpheusStatusBadge: View {
    let title: String
    let active: Bool
    var activeColor: Color = .orange

    var body: some View {
        Label(title, systemImage: active ? "exclamationmark.circle.fill" : "checkmark.circle")
            .font(.caption)
            .foregroundStyle(active ? activeColor : .secondary)
    }
}
