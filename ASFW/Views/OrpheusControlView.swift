import SwiftUI

struct OrpheusControlView: View {
    @StateObject private var viewModel: OrpheusControlViewModel
    @AppStorage("orpheus.classicSkin") private var classicSkin = false

    private let analogColumns = Array(repeating: GridItem(.flexible(minimum: 180), spacing: 12, alignment: .top), count: 4)
    private let meterColumns = Array(repeating: GridItem(.flexible(minimum: 160), spacing: 16), count: 3)

    init(connector: ASFWDriverConnector) {
        _viewModel = StateObject(wrappedValue: OrpheusControlViewModel(connector: connector))
    }

    var body: some View {
        Group {
            if classicSkin {
                VStack(spacing: 0) {
                    classicToolbar
                    ZStack {
                        OrpheusClassicView(viewModel: viewModel)
                        if !viewModel.isConnected || viewModel.device == nil {
                            classicUnavailableOverlay
                        }
                    }
                }
            } else {
                modernBody
            }
        }
        .navigationTitle("Orpheus")
        .onAppear {
            viewModel.writesEnabled = true
            viewModel.metersLive = true
            viewModel.refresh()
        }
        .onDisappear { viewModel.metersLive = false }
        .alert(phantomAlertTitle, isPresented: phantomAlertPresented) {
            Button("Enable 48 V", role: .destructive) { viewModel.confirmPendingPhantom() }
            Button("Cancel", role: .cancel) { viewModel.pendingPhantomChannel = nil }
        } message: {
            Text("Never apply phantom power to ribbon microphones or to sources that are not designed for it.")
        }
    }

    private var classicToolbar: some View {
        HStack(spacing: 16) {
            Toggle("Classic panel", isOn: $classicSkin)
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(classicStatusText)
                .font(.caption)
                .foregroundStyle(viewModel.device == nil ? .orange : .secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var classicStatusText: String {
        if !viewModel.isConnected { return "Driver not connected" }
        if let device = viewModel.device { return "GUID \(device.guidHex)" }
        return viewModel.isLoading ? "Searching for Orpheus…" : (viewModel.errorMessage ?? "No Orpheus selected")
    }

    private var classicUnavailableOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                Text(!viewModel.isConnected ? "Driver Not Connected" : "No Prism Sound Orpheus Found")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(!viewModel.isConnected
                     ? "Connect to ASFWDriver to control the Orpheus."
                     : "The audio device is visible, but this panel has not selected it yet. The panel retries automatically after the bus settles.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(24)
        }
        .allowsHitTesting(true)
    }

    private var modernBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection

                if !viewModel.isConnected {
                    stateCard(title: "Driver Not Connected",
                              message: "Connect to ASFWDriver to control the Orpheus.")
                } else if viewModel.device == nil {
                    stateCard(title: "No Prism Sound Orpheus Found",
                              message: "Connect and power the Orpheus. The panel retries automatically.")
                } else {
                    if let error = viewModel.errorMessage {
                        errorLabel(error)
                    }

                    unitSection
                    pairedCards {
                        frontPanelSection
                    } right: {
                        headphoneSection
                    }
                    pairedCards {
                        clockSection
                    } right: {
                        digitalSection
                    }
                    analogInputSection
                    analogOutputSection
                    OrpheusMixerSection(viewModel: viewModel)

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
                }

                if viewModel.device != nil {
                    Divider()
                    HStack(spacing: 20) {
                        Toggle("Identify", isOn: Binding(get: { viewModel.unit.identify },
                                                         set: { viewModel.setIdentify($0) }))
                        Toggle("Classic panel", isOn: $classicSkin)
                        Spacer()
                    }
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
                Text("Meters show")
                OrpheusChoicePicker(title: "Meters show",
                                    choices: OrpheusChoices.frontPanelMeter,
                                    selection: viewModel.unit.frontPanelMeterMode) { viewModel.setFrontPanelMeterMode($0) }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                labeledRow("Brightness") {
                    Slider(value: Binding(get: { Double(viewModel.unit.meterBrightness) },
                                          set: { viewModel.setMeterBrightness(UInt8($0.rounded())) }),
                           in: 1...15)
                        .labelsHidden()
                    Text("\(OrpheusChoices.brightnessLabel(viewModel.unit.meterBrightness)) (\(viewModel.unit.meterBrightness))")
                        .font(.system(.caption, design: .monospaced))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } label: {
            Label("Front Panel", systemImage: "light.max")
                .font(.headline)
        }
    }

    // MARK: - Clock

    private var clockSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                labeledRow("Sync source") {
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
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                labeledChoice("ADAT",
                              choices: OrpheusChoices.adatModes(firmware: viewModel.firmware),
                              selection: viewModel.unit.adatMode,
                              onSelect: viewModel.setAdatMode)

                labeledChoice("Sample rate converter",
                              choices: OrpheusChoices.sampleRateConverter,
                              selection: viewModel.unit.sampleRateConverter,
                              onSelect: viewModel.setSampleRateConverter)

                labeledChoice("Word clock output",
                              choices: OrpheusChoices.clockOutput,
                              selection: viewModel.unit.clockOutput,
                              onSelect: viewModel.setClockOutput)

                Text("ASFW streams with the Orpheus as clock master or slave; changing the sync source while audio is running can cause dropouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                   in: Double(OrpheusAnalogChannelState.gainRange.lowerBound)...Double(OrpheusAnalogChannelState.gainRange.upperBound))
                .labelsHidden()
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
            VStack(alignment: .leading, spacing: 12) {
                labeledRow("Headphone source") {
                    Picker("Headphone source", selection: Binding(get: { viewModel.headphoneRouting },
                                                                  set: { viewModel.setHeadphoneRouting($0) })) {
                        ForEach(OrpheusHeadphones.routings, id: \.self) { routing in
                            Text(routing.label).tag(routing)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                caption("Headphone mixer and DAW use the dedicated headphone bus; mirror copies another output pair.")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    Spacer(minLength: 0)
                }

                labeledChoice("Input connector",
                              choices: OrpheusChoices.digitalInputType,
                              selection: viewModel.digital.inputType,
                              onSelect: viewModel.setDigitalInputType)

                labeledChoice("Channel status",
                              choices: OrpheusChoices.digitalChannelStatus,
                              selection: viewModel.digital.channelStatus,
                              onSelect: viewModel.setDigitalChannelStatus)

                labeledChoice("Output word length",
                              choices: OrpheusChoices.digitalBitDepth,
                              selection: viewModel.digital.bitDepth,
                              onSelect: viewModel.setDigitalBitDepth)

                Group {
                    labeledChoice("Output sample rate",
                                  choices: OrpheusChoices.digitalSampleRate,
                                  selection: viewModel.digital.sampleRate,
                                  onSelect: viewModel.setDigitalSampleRate)

                    labeledChoice("Output sync",
                                  choices: OrpheusChoices.digitalSync,
                                  selection: viewModel.digital.syncSource,
                                  onSelect: viewModel.setDigitalSync)
                }
                .disabled(!viewModel.unit.digitalOutputClockIsIndependent)

                caption("Output sample rate and sync are independent only when the sample rate converter is on the digital output.")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } label: {
            Label("Digital I/O", systemImage: "cable.connector")
                .font(.headline)
        }
    }

    // MARK: - Meters

    private var meterSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
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

    private func pairedCards<Left: View, Right: View>(
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            left()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            right()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .frame(width: 148, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledChoice(_ title: String,
                               choices: [OrpheusChoice],
                               selection: UInt8,
                               onSelect: @escaping (UInt8) -> Void) -> some View {
        labeledRow(title) {
            OrpheusChoicePicker(title: title, choices: choices, selection: selection, onSelect: onSelect)
                .pickerStyle(.menu)
                .labelsHidden()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            let levels = feed.displayedLevels.isEmpty ? meters.levels : feed.displayedLevels
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    OrpheusMeterBar(label: OrpheusMeterSnapshot.label(for: index),
                                    level: level,
                                    fullScale: meters.fullScale(at: index),
                                    clip: feed.displayedClips.indices.contains(index) ? feed.displayedClips[index] : nil)
                }
            }
        } else {
            Text("Meters are read with a block read from the unit; enable live meters to start polling.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
