import SwiftUI

struct OrpheusClassicView: View {
    @ObservedObject var viewModel: OrpheusControlViewModel
    @State private var page = OrpheusClassicPage.input

    private var meterFeed: OrpheusMeterFeed { viewModel.meterFeed }

    var body: some View {
        ZStack(alignment: .topLeading) {
            OrpheusClassicChrome()
                .frame(width: OrpheusClassicLayout.window.width,
                       height: OrpheusClassicLayout.window.height)
                .allowsHitTesting(false)
            mainPanel
                .frame(width: OrpheusClassicLayout.main.width,
                       height: OrpheusClassicLayout.main.height)
                .classicOrigin(x: 30, y: 146)
        }
        .frame(width: OrpheusClassicLayout.window.width,
               height: OrpheusClassicLayout.window.height,
               alignment: .topLeading)
        .frame(minWidth: OrpheusClassicLayout.window.width,
               minHeight: OrpheusClassicLayout.window.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainPanel: some View {
        ZStack(alignment: .topLeading) {
            ClassicPlaced(OrpheusClassicBox(0, 359, 640, 121), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusSprite(name: "backgroundTop")
            }
            .allowsHitTesting(false)
            topStrip
            pageBody
                .frame(width: OrpheusClassicLayout.pageSize.width,
                       height: OrpheusClassicLayout.pageSize.height)
                .classicOrigin(x: 0, y: OrpheusClassicLayout.main.height - OrpheusClassicLayout.pageSize.height)
            tabStrip
        }
        .clipped()
    }

    private var topStrip: some View {
        ZStack(alignment: .topLeading) {
            ClassicPlaced(OrpheusClassicBox(8, 448, 270, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicCombo(image: "deviceCombo",
                                    choices: [(true, viewModel.device.map { String($0.guidHex.suffix(8)) } ?? "")],
                                    selection: true,
                                    onSelect: { _ in })
            }
            ClassicPlaced(OrpheusClassicBox(368, 448, 60, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicCombo(image: "combo60",
                                    choices: OrpheusChoices.digitalSampleRate,
                                    selection: viewModel.digital.sampleRate,
                                    onSelect: viewModel.setDigitalSampleRate)
            }
            ClassicPlaced(OrpheusClassicBox(79, 430, 80, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicCombo(image: "combo80",
                                    choices: OrpheusSyncSource.selectable(current: viewModel.syncSource,
                                                                          hasAdatInput: viewModel.hasAdatInput)
                                        .map { ($0, $0.classicLabel) },
                                    selection: viewModel.syncSource ?? .local,
                                    onSelect: viewModel.setSyncSource)
            }
            ClassicPlaced(OrpheusClassicBox(69, 412, 90, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicCombo(image: "combo90",
                                    choices: OrpheusChoices.frontPanelMeter,
                                    selection: viewModel.unit.frontPanelMeterMode,
                                    onSelect: viewModel.setFrontPanelMeterMode)
            }
            ClassicPlaced(OrpheusClassicBox(69, 394, 90, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicCombo(image: "combo90",
                                    choices: OrpheusChoices.clockOutput,
                                    selection: viewModel.unit.clockOutput,
                                    onSelect: viewModel.setClockOutput)
            }
            ClassicPlaced(OrpheusClassicBox(208, 430, 70, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicButton(title: "Identify",
                                     image: "id",
                                     checked: viewModel.unit.identify) { viewModel.setIdentify(!viewModel.unit.identify) }
            }
            ClassicPlaced(OrpheusClassicBox(208, 412, 70, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicCombo(image: "combo70",
                                    choices: OrpheusChoices.sampleRateConverter,
                                    selection: viewModel.unit.sampleRateConverter,
                                    onSelect: viewModel.setSampleRateConverter)
            }
            ClassicPlaced(OrpheusClassicBox(208, 394, 70, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicCombo(image: "combo70",
                                    choices: OrpheusChoices.adatModes(firmware: viewModel.firmware),
                                    selection: viewModel.unit.adatMode,
                                    onSelect: viewModel.setAdatMode)
            }
            ClassicPlaced(OrpheusClassicBox(368, 430, 60, 16), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicCombo(image: "combo60",
                                    choices: [
                                        OrpheusChoice(value: 15, label: "Max"),
                                        OrpheusChoice(value: 8, label: "High"),
                                        OrpheusChoice(value: 4, label: "Low"),
                                        OrpheusChoice(value: 1, label: "Min"),
                                    ],
                                    selection: brightnessSelection,
                                    onSelect: viewModel.setMeterBrightness)
            }
            ClassicPlaced(OrpheusClassicBox(590, 444, 36, 36), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicButton(image: "help", frames: 1, action: {})
            }
            ClassicPlaced(OrpheusClassicBox(544, 444, 36, 36), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicButton(image: "open", frames: 1, action: {})
            }
            ClassicPlaced(OrpheusClassicBox(544, 404, 36, 36), parentHeight: OrpheusClassicLayout.main.height) {
                OrpheusClassicButton(image: "save", frames: 1, action: {})
            }
        }
    }

    private var brightnessSelection: UInt8 {
        switch viewModel.unit.meterBrightness {
        case 9...: return 15
        case 5...8: return 8
        case 2...4: return 4
        default: return 1
        }
    }

    private var tabStrip: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(OrpheusClassicLayout.tabs.enumerated()), id: \.offset) { index, tab in
                ClassicPlaced(tab.box, parentHeight: OrpheusClassicLayout.main.height) {
                    OrpheusClassicButton(title: tab.title,
                                         image: tab.image,
                                         checked: page.rawValue == index,
                                         hidesIdleArtwork: true) {
                        page = OrpheusClassicPage(rawValue: index) ?? .input
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case .input: inputPage
        case .output: outputPage
        case .mixA12, .mixA34, .mixA56, .mixA78, .mixD12, .mixHP:
            mixPage(bus: page.mixBus ?? 0)
        case .adat: adatPage
        case .diagram: diagramPage
        }
    }

    private var inputPage: some View {
        ZStack(alignment: .topLeading) {
            OrpheusClassicPageBackdrop(kind: .input)
            ForEach(0..<8, id: \.self) { channel in
                analogStrip(channel)
            }
            ForEach(0..<2, id: \.self) { pair in
                ClassicPlaced(OrpheusClassicBox(OrpheusClassicLayout.columnX(pair * 2), 8, 86, 16)) {
                    OrpheusClassicButton(title: "M-S",
                                         image: "midSide",
                                         checked: viewModel.analog[pair].midSide,
                                         enabled: OrpheusMidSide.isAvailable(pair: pair, inputTypes: viewModel.analogInputTypes)) {
                        viewModel.setMidSide(pair: pair, enabled: !viewModel.analog[pair].midSide)
                    }
                }
            }
            ClassicPlaced(OrpheusClassicBox(391, 325, 56, 16)) {
                OrpheusClassicCombo(image: "diCombo",
                                    choices: OrpheusChoices.digitalInputType,
                                    selection: viewModel.digital.inputType,
                                    onSelect: viewModel.setDigitalInputType)
            }
            ClassicPlaced(OrpheusClassicBox(399, 305, 40, 16)) {
                OrpheusClassicButton(title: "Unlock", image: "buttonUnlocked", checked: viewModel.digital.unlocked, enabled: false) {}
            }
            ClassicPlaced(OrpheusClassicBox(399, 287, 40, 16)) {
                OrpheusClassicButton(title: "Async", image: "buttonAsync", checked: viewModel.digital.asynchronous, enabled: false) {}
            }
            meterColumn(indices: Array(0..<10), xs: (0..<8).map { OrpheusClassicLayout.analogMeterX($0) } + [399, 422])
        }
    }

    private func analogStrip(_ channel: Int) -> some View {
        let state = viewModel.analog[channel]
        let x = OrpheusClassicLayout.columnX(channel)
        let type = OrpheusAnalogInputType(rawValue: state.inputType) ?? .line
        return ZStack(alignment: .topLeading) {
            ClassicPlaced(OrpheusClassicBox(x, 325, 40, 16)) {
                OrpheusSprite(name: type == .mic ? "indPink" : (type == .instrument ? "indBlue" : "indGreen"))
            }
            ClassicPlaced(OrpheusClassicBox(x, 305, 40, 16)) {
                OrpheusClassicButton(title: "OVK", image: "overkiller", checked: state.overkiller) {
                    viewModel.setOverkiller(channel: channel, enabled: !state.overkiller)
                }
            }
            if type == .line {
                ClassicPlaced(OrpheusClassicBox(x, 148, 20, 16)) {
                    OrpheusClassicButton(title: "+4", image: "linePlus4", checked: state.lineInputLevel == 1) {
                        viewModel.setLineInputLevel(channel: channel, value: 1)
                    }
                }
                ClassicPlaced(OrpheusClassicBox(x, 132, 20, 16)) {
                    OrpheusClassicButton(title: "-10", image: "lineMinus10", checked: state.lineInputLevel == 0) {
                        viewModel.setLineInputLevel(channel: channel, value: 0)
                    }
                }
            }
            if type == .mic, channel < 4 {
                ClassicPlaced(OrpheusClassicBox(x, 287, 40, 16)) {
                    OrpheusClassicButton(title: "48V", image: "phantom", checked: state.phantom) {
                        viewModel.requestPhantom(channel: channel, enabled: !state.phantom)
                    }
                }
                preamp(channel: channel, x: x, gain: state.micGain, thumb: "thumbPink") {
                    viewModel.setMicGain(channel: channel, gain: $0)
                }
            }
            if type == .instrument, channel < 2 {
                preamp(channel: channel, x: x, gain: state.instrumentGain, thumb: "thumbBlue") {
                    viewModel.setInstrumentGain(channel: channel, gain: $0)
                }
            }
            if type != .line, channel < 4 {
                ClassicPlaced(OrpheusClassicBox(x, 269, 40, 16)) {
                    OrpheusClassicCombo(image: state.filter == 2 ? "filterRiaa" : (state.filter == 1 ? "filterHp" : "filter"),
                                        choices: OrpheusChoices.filters(channel: channel),
                                        selection: state.filter,
                                        showsTitle: false,
                                        onSelect: { viewModel.setFilter(channel: channel, filter: $0) })
                }
                ClassicPlaced(OrpheusClassicBox(x, 251, 40, 16)) {
                    OrpheusClassicButton(title: "Ø", image: "phase", checked: state.phase) {
                        viewModel.setPhase(channel: channel, inverted: !state.phase)
                    }
                }
            }
        }
    }

    private func preamp(channel: Int, x: CGFloat, gain: UInt8, thumb: String, onChange: @escaping (UInt8) -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            ClassicPlaced(OrpheusClassicBox(x, 49, 20, 199)) {
                OrpheusClassicFader(value: Double(gain), range: 10...65, thumbImage: thumb) {
                    onChange(UInt8(clamping: Int($0.rounded())))
                }
            }
            ClassicPlaced(OrpheusClassicBox(x, 28, 40, 16)) {
                OrpheusClassicNumber(text: OrpheusClassicCaption.analogGain(gain))
            }
        }
    }

    private var outputPage: some View {
        ZStack(alignment: .topLeading) {
            OrpheusClassicPageBackdrop(kind: .output)
            ForEach(0..<8, id: \.self) { channel in
                let x = OrpheusClassicLayout.columnX(channel)
                ClassicPlaced(OrpheusClassicBox(x, 325, 40, 16)) {
                    OrpheusClassicButton(title: "Vol",
                                         image: "volSelect",
                                         checked: viewModel.unit.volumeSelectMask & (1 << channel) != 0) {
                        viewModel.setVolumeSelect(bit: channel,
                                                  enabled: viewModel.unit.volumeSelectMask & (1 << channel) == 0)
                    }
                }
                ClassicPlaced(OrpheusClassicBox(x, 148, 20, 16)) {
                    OrpheusClassicButton(title: "+4",
                                         image: "linePlus4",
                                         checked: viewModel.analog[channel].lineOutputLevel == 1) {
                        viewModel.setLineOutputLevel(channel: channel, value: 1)
                    }
                }
                ClassicPlaced(OrpheusClassicBox(x, 132, 20, 16)) {
                    OrpheusClassicButton(title: "-10",
                                         image: "lineMinus10",
                                         checked: viewModel.analog[channel].lineOutputLevel == 0) {
                        viewModel.setLineOutputLevel(channel: channel, value: 0)
                    }
                }
            }
            ClassicPlaced(OrpheusClassicBox(399, 325, 40, 16)) {
                OrpheusClassicButton(title: "HP",
                                     image: "volSelect",
                                     checked: viewModel.unit.volumeSelectMask & (1 << OrpheusVolumeSelect.headphoneBit) != 0) {
                    viewModel.setVolumeSelect(bit: OrpheusVolumeSelect.headphoneBit,
                                              enabled: viewModel.unit.volumeSelectMask & (1 << OrpheusVolumeSelect.headphoneBit) == 0)
                }
            }
            ClassicPlaced(OrpheusClassicBox(518, 325, 40, 16)) {
                OrpheusClassicButton(title: "Lock", image: "lockMasterVol", checked: viewModel.unit.masterLock) {
                    viewModel.setMasterLock(!viewModel.unit.masterLock)
                }
            }
            ClassicPlaced(OrpheusClassicBox(520, 206, 104, 104)) {
                OrpheusClassicKnob(raw: viewModel.unit.masterVolume, onChange: viewModel.setMasterVolume)
            }
            ClassicPlaced(OrpheusClassicBox(551, 186, 40, 16)) {
                OrpheusClassicNumber(text: OrpheusClassicCaption.masterVolume(viewModel.unit.masterVolume),
                                     image: "masterMuteDisplay")
            }
            ClassicPlaced(OrpheusClassicBox(551, 168, 40, 16)) {
                OrpheusClassicButton(title: "Mute", image: "mute", checked: viewModel.unit.masterMute) {
                    viewModel.setMasterMute(!viewModel.unit.masterMute)
                }
            }
            ForEach(0..<5, id: \.self) { bus in
                ClassicPlaced(OrpheusClassicBox(31 + CGFloat(bus) * 92, 36, 40, 16)) {
                    OrpheusClassicButton(title: ["A12", "A34", "A56", "A78", "D12"][bus],
                                         image: "buttonHeadphones",
                                         checked: viewModel.headphoneRouting == .mirror(bus: bus)) {
                        viewModel.setHeadphoneRouting(.mirror(bus: bus))
                    }
                }
                ClassicPlaced(OrpheusClassicBox(23 + CGFloat(bus) * 92, 8, 56, 16)) {
                    busSourceCombo(bus)
                }
            }
            ClassicPlaced(OrpheusClassicBox(460, 8, 56, 16)) {
                headphoneSourceCombo
            }
            ClassicPlaced(OrpheusClassicBox(391, 305, 56, 16)) {
                OrpheusClassicCombo(image: "combo56",
                                    choices: OrpheusChoices.digitalBitDepth,
                                    selection: viewModel.digital.bitDepth,
                                    onSelect: viewModel.setDigitalBitDepth)
            }
            ClassicPlaced(OrpheusClassicBox(391, 287, 56, 16)) {
                OrpheusClassicCombo(image: "combo56",
                                    choices: OrpheusChoices.digitalChannelStatus,
                                    selection: viewModel.digital.channelStatus,
                                    onSelect: viewModel.setDigitalChannelStatus)
            }
            ClassicPlaced(OrpheusClassicBox(391, 269, 56, 16)) {
                OrpheusClassicCombo(image: "combo56",
                                    choices: OrpheusChoices.digitalSampleRate,
                                    selection: viewModel.digital.sampleRate,
                                    onSelect: viewModel.setDigitalSampleRate)
            }
            ClassicPlaced(OrpheusClassicBox(391, 251, 56, 16)) {
                OrpheusClassicCombo(image: "combo56",
                                    choices: OrpheusChoices.digitalSync,
                                    selection: viewModel.digital.syncSource,
                                    onSelect: viewModel.setDigitalSync)
            }
            meterColumn(indices: Array(10..<22),
                        xs: (0..<8).map { OrpheusClassicLayout.analogMeterX($0) } + [399, 422, 468, 491])
        }
    }

    private func mixPage(bus: Int) -> some View {
        let state = viewModel.mixBuses[bus]
        return ZStack(alignment: .topLeading) {
            OrpheusClassicPageBackdrop(kind: .mix)
            ForEach(0..<12, id: \.self) { input in
                mixStrip(bus: bus, input: input, state: state)
            }
            ForEach(0..<5, id: \.self) { pair in
                let linked = viewModel.isLinked(bus: bus, input: pair * 2)
                ClassicPlaced(OrpheusClassicBox(OrpheusClassicLayout.columnX(pair * 2), 8, 86, 16)) {
                    OrpheusClassicButton(title: "Link", image: "mixStereo", checked: linked) {
                        viewModel.setLink(bus: bus, pair: pair * 2, linked: !linked)
                    }
                }
            }
            ClassicPlaced(OrpheusClassicBox(611, 49, 20, 199)) {
                mixFader(raw: state.gain) { viewModel.setBusGain(bus: bus, gain: $0) }
            }
            ClassicPlaced(OrpheusClassicBox(575, 28, 40, 16)) {
                OrpheusClassicNumber(text: OrpheusClassicCaption.mixGain(state.gain))
            }
            ClassicPlaced(OrpheusClassicBox(575, 251, 40, 16)) {
                OrpheusClassicButton(title: "Mute", image: "mute", checked: state.mute) {
                    viewModel.setBusMute(bus: bus, muted: !state.mute)
                }
            }
            ClassicPlaced(OrpheusClassicBox(567, 287, 56, 16)) {
                mixDefeatControl(bus: bus)
            }
            ClassicPlaced(OrpheusClassicBox(580, 343, 40, 15)) {
                OrpheusSprite(name: OrpheusClassicLayout.mixLabelImages[bus])
            }
            mixMeters(bus: bus)
        }
    }

    private func mixStrip(bus: Int, input: Int, state: OrpheusMixBusState) -> some View {
        let linked = viewModel.isLinked(bus: bus, input: input)
        let hidden = linked && input & 1 == 1
        let channel = state.inputs[input]
        return ZStack(alignment: .topLeading) {
            ClassicPlaced(OrpheusClassicLayout.mixControlBox(input: input, linked: linked, y: 303, height: 40)) {
                OrpheusClassicPot(value: Double(channel.position), range: -20...20) {
                    viewModel.setInputPosition(bus: bus, input: input, position: Int8(clamping: Int($0.rounded())))
                }
            }
            ClassicPlaced(OrpheusClassicLayout.mixControlBox(input: input, linked: linked, y: 287)) {
                OrpheusClassicNumber(text: OrpheusClassicCaption.pan(channel.position), editable: true) { text in
                    if let position = OrpheusClassicCaption.parsePan(text) {
                        viewModel.setInputPosition(bus: bus, input: input, position: position)
                    }
                }
            }
            ClassicPlaced(OrpheusClassicLayout.mixControlBox(input: input, linked: linked, y: 269)) {
                OrpheusClassicButton(title: "Solo",
                                     image: "solo",
                                     checked: state.soloedInput == input || (linked && state.soloedInput == input & ~1)) {
                    viewModel.setSolo(bus: bus, input: input, enabled: state.soloedInput != input)
                }
            }
            ClassicPlaced(OrpheusClassicLayout.mixControlBox(input: input, linked: linked, y: 251)) {
                OrpheusClassicButton(title: "Mute", image: "mute", checked: channel.mute) {
                    viewModel.setInputMute(bus: bus, input: input, muted: !channel.mute)
                }
            }
            ClassicPlaced(OrpheusClassicLayout.mixGainBox(input: input, linked: linked)) {
                mixFader(raw: channel.gain) { viewModel.setInputGain(bus: bus, input: input, gain: $0) }
            }
            ClassicPlaced(OrpheusClassicLayout.mixControlBox(input: input, linked: linked, y: 28)) {
                OrpheusClassicNumber(text: OrpheusClassicCaption.mixGain(channel.gain))
            }
        }
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
    }

    private func mixFader(raw: Int16, onChange: @escaping (Int16) -> Void) -> some View {
        let scale = OrpheusSteppedScale.mixGain
        return OrpheusClassicFader(value: Double(scale.position(for: raw)),
                                   range: 0...Double(scale.maxPosition)) {
            onChange(scale.raw(at: Int($0.rounded())))
        }
    }

    private func mixMeters(bus: Int) -> some View {
        let outputs: [Int] = {
            switch bus {
            case 4: return [18, 19]
            case 5: return [20, 21]
            default: return [10 + bus * 2, 11 + bus * 2]
            }
        }()
        return ZStack(alignment: .topLeading) {
            ForEach(0..<12, id: \.self) { input in
                let linked = viewModel.isLinked(bus: bus, input: input)
                let box = OrpheusClassicLayout.mixMeterBox(input: input, linked: linked)
                ClassicPlaced(box) {
                    meter(at: OrpheusMix.meterIndex(bus: bus, input: input))
                }
                if input < 8 {
                    ClassicPlaced(OrpheusClassicBox(box.x, 48, 17, 17)) {
                        OrpheusClassicButton(image: "overkillerLed",
                                             checked: viewModel.analog[input].overkiller,
                                             enabled: false,
                                             action: {})
                    }
                }
            }
            ForEach(0..<2, id: \.self) { index in
                ClassicPlaced(OrpheusClassicLayout.meterBox(x: 565 + CGFloat(index) * 20)) {
                    meter(at: outputs[index])
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var adatPage: some View {
        let send = viewModel.unit.adatMode == 1 || viewModel.unit.adatMode == 3
        return ZStack(alignment: .topLeading) {
            OrpheusClassicPageBackdrop(kind: .adat)
            ClassicPlaced(OrpheusClassicBox(134, 319, 52, 16)) {
                OrpheusClassicButton(title: "Send", image: "adatSend", checked: send) {
                    viewModel.setAdatMode(send ? 0 : 1)
                }
            }
            ClassicPlaced(OrpheusClassicBox(192, 319, 52, 16)) {
                OrpheusClassicButton(title: "Return", image: "adatReturn", checked: !send && viewModel.hasAdatInput) {
                    viewModel.setAdatMode(2)
                }
            }
            meterColumn(indices: Array((send ? 40 : 32)..<(send ? 48 : 40)),
                        xs: (0..<8).map { OrpheusClassicLayout.analogMeterX($0) })
        }
    }

    private var diagramPage: some View {
        OrpheusClassicPageBackdrop(kind: .diagram)
    }

    @ViewBuilder
    private func mixDefeatControl(bus: Int) -> some View {
        if bus == OrpheusHeadphones.headphoneBus {
            headphoneSourceCombo
        } else {
            busSourceCombo(bus)
        }
    }

    private func busSourceCombo(_ bus: Int) -> some View {
        OrpheusClassicCombo(image: viewModel.mixBuses[bus].defeated ? "combo56Alarm" : "combo56Pale",
                            choices: [(false, "Mixer"), (true, "DAW")],
                            selection: viewModel.mixBuses[bus].defeated,
                            onSelect: { viewModel.setBusDefeat(bus: bus, defeated: $0) })
    }

    private var headphoneSourceCombo: some View {
        OrpheusClassicCombo(image: "combo56Pale",
                            choices: OrpheusHeadphones.routings.map { routing in
                                switch routing {
                                case .mixer: return (routing, "Mixer")
                                case .daw: return (routing, "DAW")
                                case .mirror(let bus): return (routing, OrpheusMix.busNames[bus])
                                }
                            },
                            selection: viewModel.headphoneRouting,
                            onSelect: viewModel.setHeadphoneRouting)
    }

    private func meterColumn(indices: [Int], xs: [CGFloat]) -> some View {
        OrpheusClassicMeterBank(feed: meterFeed, items: zip(indices, xs).map { (index: $0.0, x: $0.1) })
    }

    private func meter(at index: Int) -> some View {
        OrpheusClassicMeterWell(feed: meterFeed, index: index)
    }
}

private struct OrpheusClassicMeterBank: View {
    @ObservedObject var feed: OrpheusMeterFeed
    let items: [(index: Int, x: CGFloat)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.index) { item in
                ClassicPlaced(OrpheusClassicLayout.meterBox(x: item.x)) {
                    OrpheusClassicMeterWell(feed: feed, index: item.index)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct OrpheusClassicMeterWell: View {
    @ObservedObject var feed: OrpheusMeterFeed
    let index: Int

    var body: some View {
        let levels = feed.displayedLevels.isEmpty ? feed.snapshot?.levels : feed.displayedLevels
        let level = (levels?.indices.contains(index) ?? false) ? levels![index] : 0
        let fullScale = feed.snapshot?.fullScale(at: index) ?? OrpheusMeterScale.unsignedFullScale
        let clip = feed.displayedClips.indices.contains(index)
            ? feed.displayedClips[index]
            : OrpheusMeterScale.isClipping(level, fullScale: fullScale)
        OrpheusClassicMeter(level: level,
                            fullScale: fullScale,
                            clip: clip)
    }
}

private struct ClassicPlaced<Content: View>: View {
    let box: OrpheusClassicBox
    var parentHeight: CGFloat = OrpheusClassicLayout.pageSize.height
    let content: Content

    init(_ box: OrpheusClassicBox,
         parentHeight: CGFloat = OrpheusClassicLayout.pageSize.height,
         @ViewBuilder content: () -> Content) {
        self.box = box
        self.parentHeight = parentHeight
        self.content = content()
    }

    var body: some View {
        content.classicBox(box, parentHeight: parentHeight)
    }
}
