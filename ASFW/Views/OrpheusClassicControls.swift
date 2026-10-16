import AppKit
import SwiftUI

extension View {
    func classicBox(_ box: OrpheusClassicBox, parentHeight: CGFloat = OrpheusClassicLayout.main.height) -> some View {
        let rect = box.swiftRect(parentHeight: parentHeight)
        return frame(width: rect.width, height: rect.height)
            .clipped()
            .contentShape(Rectangle())
            .position(x: rect.midX, y: rect.midY)
    }

    /// Positions a view by its top-left origin. Unlike `offset`, hit testing
    /// follows the drawn location and the spacer does not steal clicks.
    func classicOrigin(x: CGFloat, y: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if x > 0 {
                Color.clear.frame(width: x).allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 0) {
                if y > 0 {
                    Color.clear.frame(height: y).allowsHitTesting(false)
                }
                self
            }
        }
    }
}

struct OrpheusClassicChrome: View {
    var body: some View {
        ZStack {
            OrpheusClassicPalette.chromeDark
            if let image = OrpheusVendorArt.chromeBackground() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                drawnChrome
            }
        }
        .clipped()
    }

    private var drawnChrome: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(OrpheusClassicPalette.chromeDark)
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [OrpheusClassicPalette.chrome, OrpheusClassicPalette.chromeDark],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(8)
            RoundedRectangle(cornerRadius: 8)
                .fill(OrpheusClassicPalette.beige)
                .padding(.horizontal, 18)
                .padding(.top, 108)
                .padding(.bottom, 40)
            Rectangle()
                .fill(LinearGradient(colors: [OrpheusClassicPalette.header, Color(red: 0.55, green: 0.60, blue: 0.68)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 92)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            Rectangle()
                .fill(Color.black)
                .frame(height: 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .overlay(alignment: .topLeading) {
            Text("orpheus")
                .font(.system(size: 22, weight: .light, design: .serif))
                .italic()
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.leading, 36)
                .padding(.top, 48)
        }
        .overlay(alignment: .bottomLeading) {
            Text("firewire controller")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.yellow.opacity(0.85))
                .padding(.leading, 28)
                .padding(.bottom, 10)
        }
    }
}

struct OrpheusClassicButton: View {
    var title: String = ""
    var image: String?
    var frames = 2
    var checked = false
    var enabled = true
    /// Tab artwork already lives in `backgroundTop`; only the selected frame is drawn.
    var hidesIdleArtwork = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let image, OrpheusVendorArt.image(named: image) != nil {
                    if hidesIdleArtwork && !checked {
                        Color.clear
                    } else {
                        OrpheusSprite(name: image, frameIndex: checked ? 1 : 0, frameCount: max(frames, 1))
                    }
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(checked ? Color.black.opacity(0.55) : Color.black.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(checked ? Color.white : Color.white.opacity(enabled ? 0.85 : 0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}

struct OrpheusClassicCombo<Value: Hashable>: View {
    var image: String = "combo56"
    var showsTitle = true
    let choices: [(Value, String)]
    let selection: Value
    let onSelect: (Value) -> Void

    private var displayedTitle: String {
        choices.first { $0.0 == selection }?.1 ?? ""
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if OrpheusVendorArt.image(named: image) != nil {
                OrpheusSprite(name: image)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(OrpheusClassicPalette.comboFill)
            }
            if showsTitle {
                Text(displayedTitle)
                    .font(.custom("Helvetica", size: 11))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.leading, 6)
                    .padding(.trailing, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
            OrpheusClassicPopUp(choices: choices, selection: selection, onSelect: onSelect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// Transparent AppKit popup so the skinned combo face stays visible while clicks
/// still open a native menu. SwiftUI `Menu` swallows the custom label on macOS.
private struct OrpheusClassicPopUp<Value: Hashable>: NSViewRepresentable {
    var choices: [(Value, String)]
    var selection: Value
    var onSelect: (Value) -> Void

    final class Coordinator: NSObject {
        var choices: [(Value, String)] = []
        var onSelect: ((Value) -> Void)?
        var ignore = false

        @objc func changed(_ sender: NSPopUpButton) {
            guard !ignore else { return }
            let index = sender.indexOfSelectedItem
            guard choices.indices.contains(index) else { return }
            onSelect?(choices[index].0)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> OrpheusTransparentPopUp {
        let button = OrpheusTransparentPopUp()
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        return button
    }

    func updateNSView(_ button: OrpheusTransparentPopUp, context: Context) {
        context.coordinator.choices = choices
        context.coordinator.onSelect = onSelect
        context.coordinator.ignore = true
        let titles = choices.map(\.1)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        if let index = choices.firstIndex(where: { $0.0 == selection }) {
            button.selectItem(at: index)
        }
        context.coordinator.ignore = false
    }
}

private final class OrpheusTransparentPopUp: NSPopUpButton {
    init() {
        super.init(frame: .zero, pullsDown: false)
        isBordered = false
        isTransparent = true
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        if let cell = cell as? NSPopUpButtonCell {
            cell.arrowPosition = .noArrow
            cell.bezelStyle = .shadowlessSquare
            cell.isBordered = false
            cell.isTransparent = true
        }
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {}
    override func drawCell(_ cell: NSCell) {}
}

extension OrpheusClassicCombo where Value == UInt8 {
    init(image: String = "combo56",
         choices: [OrpheusChoice],
         selection: UInt8,
         showsTitle: Bool = true,
         onSelect: @escaping (UInt8) -> Void) {
        let items = OrpheusChoices.including(selection, in: choices)
        self.init(image: image,
                  showsTitle: showsTitle,
                  choices: items.map { ($0.value, $0.shortLabel) },
                  selection: selection,
                  onSelect: onSelect)
    }
}

struct OrpheusClassicNumber: View {
    let text: String
    var image = "gainDisplay"
    var editable = false
    var onCommit: ((String) -> Void)?

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if OrpheusVendorArt.image(named: image) != nil {
                OrpheusSprite(name: image)
            } else {
                RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.7))
            }
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.custom("Helvetica", size: 10))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit(commitEdit)
                    .onExitCommand(perform: cancelEdit)
            } else {
                Text(text)
                    .font(.custom("Helvetica", size: 10))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard editable else { return }
            draft = text
            editing = true
            focused = true
        }
        .onChange(of: focused) { _, isFocused in
            if editing && !isFocused { commitEdit() }
        }
    }

    private func commitEdit() {
        let submitted = draft
        editing = false
        focused = false
        onCommit?(submitted)
    }

    private func cancelEdit() {
        editing = false
        focused = false
    }
}

struct OrpheusClassicMeter: View {
    let level: UInt16
    var fullScale: UInt16 = OrpheusMeterScale.unsignedFullScale
    var clip = false

    var body: some View {
        VStack(spacing: 0) {
            overloadLamp
                .frame(width: OrpheusClassicLayout.meterWell.width,
                       height: OrpheusClassicLayout.meterOverloadHeight)
            meterWell
        }
        .allowsHitTesting(false)
    }

    private var overloadLamp: some View {
        Group {
            if OrpheusVendorArt.image(named: "overload") != nil {
                OrpheusSprite(name: "overload", frameIndex: clip ? 1 : 0, frameCount: 2)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(clip ? OrpheusClassicPalette.clip : Color.black.opacity(0.35))
                    .overlay {
                        Text("OVL")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(clip ? Color.white : Color.white.opacity(0.45))
                    }
            }
        }
    }

    private var meterWell: some View {
        GeometryReader { geometry in
            let fillHeight = geometry.size.height * CGFloat(OrpheusMeterScale.fraction(level, fullScale: fullScale))
            ZStack(alignment: .bottom) {
                if let scale = OrpheusVendorArt.image(named: "meter") {
                    Image(nsImage: scale)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .bottom) {
                        if let background = OrpheusVendorArt.image(named: "meterBackground") {
                            Image(nsImage: background)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 5, height: geometry.size.height)
                        } else {
                            Rectangle()
                                .fill(Color.black.opacity(0.45))
                                .frame(width: 5)
                        }
                        if let foreground = OrpheusVendorArt.image(named: "meterForeground") {
                            Image(nsImage: foreground)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 5, height: geometry.size.height)
                                .mask(alignment: .bottom) {
                                    Rectangle().frame(height: max(fillHeight, 0))
                                }
                        } else {
                            Rectangle()
                                .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .bottom, endPoint: .top))
                                .frame(width: 5, height: max(fillHeight, level == 0 ? 0 : 1))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct OrpheusClassicFader: View {
    let value: Double
    let range: ClosedRange<Double>
    var thumbImage = "thumb"
    let onChange: (Double) -> Void

    @State private var dragStart: Double?
    @State private var dragValue: Double?

    var body: some View {
        let displayed = dragValue ?? value
        GeometryReader { geometry in
            let thumbHeight: CGFloat = 33
            let travel = max(geometry.size.height - thumbHeight, 1)
            let fraction = (displayed - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .bottom) {
                if OrpheusVendorArt.image(named: "slider") != nil {
                    OrpheusSprite(name: "slider")
                } else {
                    Capsule().fill(Color.black.opacity(0.45)).frame(width: 6)
                }
                Group {
                    if OrpheusVendorArt.image(named: thumbImage) != nil {
                        OrpheusSprite(name: thumbImage)
                            .frame(width: 14, height: thumbHeight)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(OrpheusClassicPalette.thumb)
                            .frame(width: geometry.size.width - 4, height: 18)
                    }
                }
                .offset(y: -CGFloat(fraction) * travel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = start }
                        let delta = Double(-gesture.translation.height / travel) * (range.upperBound - range.lowerBound)
                        let next = min(max(start + delta, range.lowerBound), range.upperBound)
                        dragValue = next
                        onChange(next)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        dragValue = nil
                    }
            )
        }
    }
}

struct OrpheusClassicPot: View {
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    @State private var dragStart: Double?
    @State private var dragValue: Double?

    var body: some View {
        let displayed = dragValue ?? value
        let fraction = (displayed - range.lowerBound) / (range.upperBound - range.lowerBound)
        GeometryReader { geometry in
            ZStack {
                if let image = OrpheusVendorArt.panFrame(value: displayed, range: range) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [OrpheusClassicPalette.chrome, OrpheusClassicPalette.chromeDark],
                                             startPoint: .top, endPoint: .bottom))
                    Capsule()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 2, height: 10)
                        .offset(y: -11)
                        .rotationEffect(.degrees(-135 + fraction * 270))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = start }
                        let span = range.upperBound - range.lowerBound
                        let travel = max(max(geometry.size.height, geometry.size.width), 1) * 2.4
                        let delta = Double((-gesture.translation.height + gesture.translation.width) / travel) * span
                        let next = min(max(start + delta, range.lowerBound), range.upperBound)
                        dragValue = next
                        onChange(next)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        dragValue = nil
                    }
            )
        }
    }
}

struct OrpheusClassicKnob: View {
    let raw: Int16
    let onChange: (Int16) -> Void

    @State private var lastAngle: Double?

    private var position: Int { OrpheusSteppedScale.masterVolume.position(for: raw) }

    var body: some View {
        ZStack {
            if let image = OrpheusVendorArt.knobFrame(index: position) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
            } else {
                let lit = Int((Double(position) / 29.0 * 12.0).rounded(.down))
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(index < lit ? OrpheusClassicPalette.ledOn : OrpheusClassicPalette.ledOff)
                        .frame(width: 6, height: 6)
                        .offset(y: -42)
                        .rotationEffect(.degrees(Double(index) / 12 * 300 - 150))
                }
            }
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let center = CGPoint(x: 52, y: 52)
                    let angle = atan2(gesture.location.x - center.x, center.y - gesture.location.y)
                    if let last = lastAngle {
                        var delta = angle - last
                        if delta > .pi { delta -= 2 * .pi }
                        if delta < -.pi { delta += 2 * .pi }
                        let next = min(max(position + Int((delta / 0.18).rounded()), 0), 29)
                        onChange(OrpheusSteppedScale.masterVolume.raw(at: next))
                    }
                    lastAngle = angle
                }
                .onEnded { _ in lastAngle = nil }
        )
    }
}

struct OrpheusClassicPageBackdrop: View {
    let kind: Kind

    enum Kind { case input, output, mix, adat, diagram }

    private var spriteName: String {
        switch kind {
        case .input: return "backgroundInput"
        case .output: return "backgroundOutput"
        case .mix: return "backgroundMix"
        case .adat: return "backgroundAdat"
        case .diagram: return "backgroundDiagram"
        }
    }

    var body: some View {
        Group {
            if OrpheusVendorArt.image(named: spriteName) != nil {
                OrpheusSprite(name: spriteName)
            } else {
                ZStack(alignment: .topLeading) {
                    OrpheusClassicPalette.beige
                    RoundedRectangle(cornerRadius: 4)
                        .fill(kind == .diagram
                              ? Color(red: 0.93, green: 0.91, blue: 0.84)
                              : OrpheusClassicPalette.taupe)
                        .frame(width: kind == .adat ? 488 : 568, height: 188)
                        .offset(x: kind == .adat ? 44 : 4, y: 96)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
