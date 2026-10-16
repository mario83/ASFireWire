import SwiftUI

struct OrpheusControlView: View {
    @StateObject private var viewModel: OrpheusControlViewModel

    private let analogColumns = Array(repeating: GridItem(.flexible(minimum: 180), spacing: 12, alignment: .top), count: 4)
    private let meterColumns = Array(repeating: GridItem(.flexible(minimum: 160), spacing: 16), count: 3)

    init(connector: ASFWDriverConnector) {
        _viewModel = StateObject(wrappedValue: OrpheusControlViewModel(connector: connector))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection

                if !viewModel.isConnected {
                    stateCard(title: "Driver Not Connected",
                              message: "Connect to ASFWDriver to control the Orpheus.")
                } else if viewModel.device == nil {
                    stateCard(title: "No Prism Sound Orpheus Found",
                              message: "Connect and power the Orpheus, then refresh this page.")
                } else {
                    if let error = viewModel.errorMessage {
                        errorLabel(error)
                    }

                    Group {
                        unitSection
                        frontPanelSection
                        clockSection
                        analogInputSection
                        analogOutputSection
                        headphoneSection
                        digitalSection
                        OrpheusMixerSection(viewModel: viewModel)
                    }
                    .disabled(!viewModel.writesEnabled)

                    meterSection
                    writeLogSection
                }

                if viewModel.device == nil, let error = viewModel.errorMessage {
                    errorLabel(error)
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Orpheus")
        .onAppear {
            viewModel.refresh()
        }
        .onDisappear {
            viewModel.metersLive = false
        }
        .alert(phantomAlertTitle, isPresented: phantomAlertPresented) {
            Button("Enable 48 V", role: .destructive) { viewModel.confirmPendingPhantom() }
            Button("Cancel", role: .cancel) { viewModel.pendingPhantomChannel = nil }
        } message: {
            Text("Never apply phantom power to ribbon microphones or to sources that are not designed for it.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let device = viewModel.device {
                            Text("GUID \(device.guidHex)")
                                .font(.system(.subheadline, design: .monospaced))
                            HStack(spacing: 16) {
                                if let node = device.nodeID {
                                    caption(String(format: "Node 0x%02X", node))
                                }
                                if let firmware = viewModel.firmware {
                                    caption("Firmware \(firmware.description)")
                                }
                            }
                        } else {
                            Text("No Orpheus selected")
                                .foregroundStyle(.secondary)
                        }

                        if let refreshed = viewModel.lastRefreshTime {
                            Text("Updated \(refreshed.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }

                if viewModel.device != nil {
                    Divider()
                    HStack(spacing: 20) {
                        Toggle("Enable writes", isOn: $viewModel.writesEnabled)
                            .toggleStyle(.switch)
                        Toggle("Identify", isOn: Binding(get: { viewModel.unit.identify },
                                                         set: { viewModel.setIdentify($0) }))
                            .disabled(!viewModel.writesEnabled)
                        Spacer()
                    }
                    Text("The control protocol was reconstructed from the Prism Sound app and is not yet verified on hardware. Settings are read-only until writes are enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Prism Sound Orpheus", systemImage: "dial.medium")
                .font(.headline)
        }
    }

    // MARK: - Unit

    private var unitSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                OrpheusSteppedSlider(title: "Master volume",
                                     raw: viewModel.unit.masterVolume,
                                     scale: .masterVolume) { viewModel.setMasterVolume($0) }

                HStack(spacing: 20) {
                    Toggle("Mute", isOn: Binding(get: { viewModel.unit.masterMute },
                                                 set: { viewModel.setMasterMute($0) }))
                    Toggle("Lock front panel", isOn: Binding(get: { viewModel.unit.masterLock },
                                                             set: { viewModel.setMasterLock($0) }))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Outputs controlled by the volume knob")
                        .font(.subheadline)
                    HStack(spacing: 12) {
                        ForEach(Array(OrpheusVolumeSelect.outputNames.enumerated()), id: \.offset) { bit, name in
                            volumeSelectToggle(name, bit: bit)
                        }
                        volumeSelectToggle("Phones", bit: OrpheusVolumeSelect.headphoneBit)
                    }
                    caption(String(format: "Mask 0x%04X", viewModel.unit.volumeSelectMask))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Monitor", systemImage: "speaker.wave.2")
                .font(.headline)
        }
    }

    private func volumeSelectToggle(_ title: String, bit: Int) -> some View {
        Toggle(title, isOn: Binding(get: { viewModel.unit.volumeSelectMask & (UInt16(1) << bit) != 0 },
                                    set: { viewModel.setVolumeSelect(bit: bit, enabled: $0) }))
            .toggleStyle(.checkbox)
    }

    // MARK: - Front Panel

    private var frontPanelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                OrpheusChoicePicker(title: "Meters show",
                                    choices: OrpheusChoices.frontPanelMeter,
                                    selection: viewModel.unit.frontPanelMeterMode) { viewModel.setFrontPanelMeterMode($0) }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                HStack(spacing: 10) {
                    Text("Brightness")
                        .frame(width: 110, alignment: .leading)
                    Slider(value: Binding(get: { Double(viewModel.unit.meterBrightness) },
                                          set: { viewModel.setMeterBrightness(UInt8($0.rounded())) }),
                           in: 1...15,
                           step: 1)
                        .frame(maxWidth: 240)
                    Text("\(OrpheusChoices.brightnessLabel(viewModel.unit.meterBrightness)) (\(viewModel.unit.meterBrightness))")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Front Panel", systemImage: "light.max")
                .font(.headline)
        }
    }

    // MARK: - Clock

    private var clockSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Sync source", selection: Binding(get: { viewModel.syncSource },
                                                         set: { if let source = $0 { viewModel.setSyncSource(source) } })) {
                    if viewModel.syncSource == nil {
                        Text("Unknown").tag(OrpheusSyncSource?.none)
                    }
                    ForEach(OrpheusSyncSource.selectable(current: viewModel.syncSource,
                                                         hasAdatInput: viewModel.hasAdatInput)) { source in
                        Text(source.label).tag(Optional(source))
                    }
                }
                .frame(maxWidth: 360)

                OrpheusChoicePicker(title: "ADAT",
                                    choices: OrpheusChoices.adatModes(firmware: viewModel.firmware),
                                    selection: viewModel.unit.adatMode) { viewModel.setAdatMode($0) }
                    .frame(maxWidth: 360)

                OrpheusChoicePicker(title: "Sample rate converter",
                                    choices: OrpheusChoices.sampleRateConverter,
                                    selection: viewModel.unit.sampleRateConverter) { viewModel.setSampleRateConverter($0) }
                    .frame(maxWidth: 360)

                OrpheusChoicePicker(title: "Word clock output",
                                    choices: OrpheusChoices.clockOutput,
                                    selection: viewModel.unit.clockOutput) { viewModel.setClockOutput($0) }
                    .frame(maxWidth: 360)

                Text("ASFW streams with the Orpheus as clock master or slave; changing the sync source while audio is running can cause dropouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Clock & Sync", systemImage: "metronome")
                .font(.headline)
        }
    }

    // MARK: - Analog Inputs

    private var analogInputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: analogColumns, alignment: .leading, spacing: 12) {
                    ForEach(0..<OrpheusWire.analogChannelCount, id: \.self) { channel in
                        analogInputStrip(channel)
                    }
                }

                Divider()

                HStack(spacing: 24) {
                    ForEach(0..<OrpheusMidSide.pairCount, id: \.self) { pair in
                        Toggle("Mid-side \(OrpheusMidSide.pairLabel(pair))",
                               isOn: Binding(get: { viewModel.analog[pair].midSide },
                                             set: { viewModel.setMidSide(pair: pair, enabled: $0) }))
                            .disabled(!OrpheusMidSide.isAvailable(pair: pair, inputTypes: viewModel.analogInputTypes))
                    }
                }
                caption("Input type (Line, Mic, Inst) is detected by the Orpheus from the connector in use.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Analog Inputs", systemImage: "mic")
                .font(.headline)
        }
    }

    private func analogInputStrip(_ channel: Int) -> some View {
        let state = viewModel.analog[channel]
        let type = state.type
        let hasPreamp = OrpheusAnalogChannelState.hasPreamp(channel: channel)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI \(channel + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                OrpheusInputTypeBadge(rawType: state.inputType)
            }

            OrpheusChoicePicker(title: "Level",
                                choices: OrpheusChoices.lineLevel,
                                selection: state.lineInputLevel) { viewModel.setLineInputLevel(channel: channel, value: $0) }
                .disabled(hasPreamp && type != .line)

            if hasPreamp {
                gainStepper("Mic", value: state.micGain) { viewModel.setMicGain(channel: channel, gain: $0) }
                    .disabled(type != .mic)
            }

            if OrpheusAnalogChannelState.hasInstrumentInput(channel: channel) {
                gainStepper("Inst", value: state.instrumentGain) { viewModel.setInstrumentGain(channel: channel, gain: $0) }
                    .disabled(type != .instrument)
            }

            if hasPreamp {
                Toggle("48 V phantom", isOn: Binding(get: { state.phantom },
                                                     set: { viewModel.requestPhantom(channel: channel, enabled: $0) }))
                    .disabled(type != .mic)

                OrpheusChoicePicker(title: "Filter",
                                    choices: OrpheusChoices.filters(channel: channel),
                                    selection: state.filter) { viewModel.setFilter(channel: channel, filter: $0) }

                Toggle("Phase invert", isOn: Binding(get: { state.phase },
                                                     set: { viewModel.setPhase(channel: channel, inverted: $0) }))
            }

            Toggle("Overkiller", isOn: Binding(get: { state.overkiller },
                                               set: { viewModel.setOverkiller(channel: channel, enabled: $0) }))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func gainStepper(_ title: String, value: UInt8, onChange: @escaping (UInt8) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) dB")
                    .font(.system(.caption, design: .monospaced))
            }
            Slider(value: Binding(get: { Double(value) },
                                  set: { onChange(UInt8($0.rounded())) }),
                   in: Double(OrpheusAnalogChannelState.gainRange.lowerBound)...Double(OrpheusAnalogChannelState.gainRange.upperBound),
                   step: 1)
        }
    }

    // MARK: - Analog Outputs

    private var analogOutputSection: some View {
        GroupBox {
            LazyVGrid(columns: analogColumns, alignment: .leading, spacing: 10) {
                ForEach(0..<OrpheusWire.analogChannelCount, id: \.self) { channel in
                    OrpheusChoicePicker(title: "AO \(channel + 1)",
                                        choices: OrpheusChoices.lineLevel,
                                        selection: viewModel.analog[channel].lineOutputLevel) {
                        viewModel.setLineOutputLevel(channel: channel, value: $0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Analog Outputs", systemImage: "speaker.wave.3")
                .font(.headline)
        }
    }

    // MARK: - Headphones

    private var headphoneSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Headphone source", selection: Binding(get: { viewModel.headphoneRouting },
                                                              set: { viewModel.setHeadphoneRouting($0) })) {
                    ForEach(OrpheusHeadphones.routings, id: \.self) { routing in
                        Text(routing.label).tag(routing)
                    }
                }
                .frame(maxWidth: 360)
                caption("Headphone mixer and DAW use the dedicated headphone bus; mirror copies another output pair.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Headphones", systemImage: "headphones")
                .font(.headline)
        }
    }

    // MARK: - Digital

    private var digitalSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    OrpheusStatusBadge(title: viewModel.digital.unlocked ? "Input unlocked" : "Input locked",
                                       active: viewModel.digital.unlocked)
                    OrpheusStatusBadge(title: viewModel.digital.asynchronous ? "Input asynchronous" : "Input synchronous",
                                       active: viewModel.digital.asynchronous)
                }

                OrpheusChoicePicker(title: "Input connector",
                                    choices: OrpheusChoices.digitalInputType,
                                    selection: viewModel.digital.inputType) { viewModel.setDigitalInputType($0) }
                    .frame(maxWidth: 360)

                OrpheusChoicePicker(title: "Channel status",
                                    choices: OrpheusChoices.digitalChannelStatus,
                                    selection: viewModel.digital.channelStatus) { viewModel.setDigitalChannelStatus($0) }
                    .frame(maxWidth: 360)

                OrpheusChoicePicker(title: "Output word length",
                                    choices: OrpheusChoices.digitalBitDepth,
                                    selection: viewModel.digital.bitDepth) { viewModel.setDigitalBitDepth($0) }
                    .frame(maxWidth: 360)

                Group {
                    OrpheusChoicePicker(title: "Output sample rate",
                                        choices: OrpheusChoices.digitalSampleRate,
                                        selection: viewModel.digital.sampleRate) { viewModel.setDigitalSampleRate($0) }
                        .frame(maxWidth: 360)

                    OrpheusChoicePicker(title: "Output sync",
                                        choices: OrpheusChoices.digitalSync,
                                        selection: viewModel.digital.syncSource) { viewModel.setDigitalSync($0) }
                        .frame(maxWidth: 360)
                }
                .disabled(!viewModel.unit.digitalOutputClockIsIndependent)

                caption("Output sample rate and sync are independent only when the sample rate converter is on the digital output.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Digital I/O", systemImage: "cable.connector")
                .font(.headline)
        }
    }

    // MARK: - Meters

    private var meterSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Live meters", isOn: $viewModel.metersLive)
                    .toggleStyle(.switch)
                OrpheusMeterGrid(feed: viewModel.meterFeed, columns: meterColumns)
                caption("Peak levels in dBFS over the vendor's 48 dB range. DI, DAW 11/12 and HP positions are confirmed on hardware; the rest follow the vendor layout.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Meters", systemImage: "chart.bar.xaxis")
                .font(.headline)
        }
    }

    // MARK: - Write Log

    private var writeLogSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.writeLog.isEmpty {
                    caption("No writes sent yet.")
                } else {
                    ForEach(viewModel.writeLog) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(entry.succeeded ? .green : .red)
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.label)
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Write Log", systemImage: "list.bullet.rectangle")
                .font(.headline)
        }
    }

    // MARK: - Helpers

    private var phantomAlertTitle: String {
        guard let channel = viewModel.pendingPhantomChannel else { return "Enable phantom power?" }
        return "Enable 48 V phantom power on AI \(channel + 1)?"
    }

    private var phantomAlertPresented: Binding<Bool> {
        Binding(get: { viewModel.pendingPhantomChannel != nil },
                set: { if !$0 { viewModel.pendingPhantomChannel = nil } })
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.callout)
    }

    private func stateCard(title: String, message: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OrpheusMeterGrid: View {
    @ObservedObject var feed: OrpheusMeterFeed
    let columns: [GridItem]

    var body: some View {
        if let error = feed.error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let meters = feed.snapshot {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(Array(meters.levels.enumerated()), id: \.offset) { index, level in
                    OrpheusMeterBar(label: OrpheusMeterSnapshot.label(for: index),
                                    level: level,
                                    fullScale: meters.fullScale(at: index))
                }
            }
        } else {
            Text("Meters are read with a block read from the unit; enable live meters to start polling.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
