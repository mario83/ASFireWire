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

/// A horizontal slider over the vendor's stepped positions.
struct OrpheusSteppedSlider: View {
    let title: String
    let raw: Int16
    let scale: OrpheusSteppedScale
    let onChange: (Int16) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 110, alignment: .leading)
            Slider(value: Binding(get: { Double(scale.position(for: raw)) },
                                  set: { position in
                                      let value = scale.raw(at: Int(position.rounded()))
                                      if value != raw { onChange(value) }
                                  }),
                   in: 0...Double(scale.maxPosition),
                   step: 1)
            Text(OrpheusLevel.format(raw, fractionDigits: 1))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 72, alignment: .trailing)
        }
    }
}

/// A drawn vertical fader. The drag is tracked relative to where it started and
/// owns the displayed position until release, so device read-backs arriving
/// mid-drag cannot move the thumb.
struct OrpheusVerticalFader: View {
    let raw: Int16
    var scale: OrpheusSteppedScale = .mixGain
    let onChange: (Int16) -> Void

    @State private var dragStartPosition: Int?
    @State private var dragPosition: Int?

    private let trackHeight: CGFloat = 130
    private let thumbHeight: CGFloat = 12

    var body: some View {
        let position = dragPosition ?? scale.position(for: raw)
        let displayed = dragPosition.map { scale.raw(at: $0) } ?? raw
        let travel = trackHeight - thumbHeight
        let fraction = CGFloat(position) / CGFloat(scale.maxPosition)

        VStack(spacing: 6) {
            Text(OrpheusLevel.format(displayed, fractionDigits: 1).replacingOccurrences(of: " dB", with: ""))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 4, height: trackHeight)
                RoundedRectangle(cornerRadius: 3)
                    .fill(dragPosition == nil ? Color.accentColor : Color.accentColor.opacity(0.8))
                    .frame(width: 26, height: thumbHeight)
                    .offset(y: -fraction * travel)
            }
            .frame(width: 30, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStartPosition ?? scale.position(for: raw)
                        if dragStartPosition == nil { dragStartPosition = start }
                        let delta = Int((-value.translation.height / travel * CGFloat(scale.maxPosition)).rounded())
                        let next = min(max(start + delta, 0), scale.maxPosition)
                        guard next != position else { return }
                        dragPosition = next
                        onChange(scale.raw(at: next))
                    }
                    .onEnded { _ in
                        dragStartPosition = nil
                        dragPosition = nil
                    }
            )
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
    var fullScale: UInt16 = OrpheusMeterScale.unsignedFullScale

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 44, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(clipping ? Color.red : (fraction > 0.875 ? Color.yellow : Color.green))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text(OrpheusMeterScale.format(level, fullScale: fullScale))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(clipping ? Color.red : Color.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var fraction: CGFloat { CGFloat(OrpheusMeterScale.fraction(level, fullScale: fullScale)) }
    private var clipping: Bool { OrpheusMeterScale.isClipping(level, fullScale: fullScale) }
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
