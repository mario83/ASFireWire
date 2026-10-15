import Foundation
import Combine

struct OrpheusWriteLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let label: String
    let succeeded: Bool
}

final class OrpheusControlViewModel: ObservableObject {
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published private(set) var device: OrpheusDeviceInfo?
    @Published private(set) var firmware: OrpheusFirmwareVersion?
    @Published private(set) var hasState = false
    @Published private(set) var failedReads: [String] = []
    @Published private(set) var lastRefreshTime: Date?

    @Published var unit = OrpheusUnitState()
    @Published var analog = Array(repeating: OrpheusAnalogChannelState(), count: OrpheusWire.analogChannelCount)
    @Published var digital = OrpheusDigitalState()
    @Published var mixBuses = Array(repeating: OrpheusMixBusState(), count: OrpheusWire.mixBusCount)
    @Published var mixDefeats = Array(repeating: false, count: OrpheusWire.mixBusCount)
    @Published var syncSource: OrpheusSyncSource?

    /// Writes stay off until the user opts in, so a first session on new
    /// hardware is read-only.
    @Published var writesEnabled = false
    @Published var selectedBus = 0
    @Published var pendingPhantomChannel: Int?
    @Published private(set) var writeLog: [OrpheusWriteLogEntry] = []

    @Published private(set) var meters: OrpheusMeterSnapshot?
    @Published private(set) var meterError: String?
    @Published var metersLive = false {
        didSet { updateMeterPolling() }
    }

    private let connector: ASFWDriverConnector
    private var cancellables = Set<AnyCancellable>()
    private var meterTimer: AnyCancellable?
    private var refreshRequestID = UUID()
    private var debouncedWrites: [String: DispatchWorkItem] = [:]
    private var debounceTokens: [String: UUID] = [:]
    private var meterReadInFlight = false
    private var meterFailures = 0
    private let writeQueue = DispatchQueue(label: "net.asfw.app.Orpheus.write", qos: .userInitiated)
    private let meterQueue = DispatchQueue(label: "net.asfw.app.Orpheus.meters", qos: .utility)

    private static let debounceInterval: TimeInterval = 0.08
    private static let meterInterval: TimeInterval = 0.15
    private static let writeLogLimit = 40

    init(connector: ASFWDriverConnector) {
        self.connector = connector

        connector.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                self.isConnected = connected
                if connected {
                    self.refresh()
                } else {
                    self.refreshRequestID = UUID()
                    self.isLoading = false
                    self.hasState = false
                    self.device = nil
                    self.metersLive = false
                    self.cancelPendingWrites()
                    self.errorMessage = "Driver not connected"
                }
            }
            .store(in: &cancellables)

        isConnected = connector.isConnected
    }

    deinit {
        meterTimer?.cancel()
        debouncedWrites.values.forEach { $0.cancel() }
    }

    // MARK: - Refresh

    func refresh() {
        guard connector.isConnected else {
            errorMessage = "Driver not connected"
            return
        }
        guard !isLoading else { return }

        let requestID = UUID()
        refreshRequestID = requestID
        isLoading = true
        errorMessage = nil

        let connector = self.connector
        writeQueue.async { [weak self] in
            let device = connector.findOrpheusDevice()
            let snapshot = device.map { connector.refreshOrpheusState(guid: $0.guid) }
            DispatchQueue.main.async {
                guard let self, self.refreshRequestID == requestID else { return }
                self.isLoading = false
                self.apply(device: device, snapshot: snapshot)
            }
        }
    }

    func apply(device: OrpheusDeviceInfo?, snapshot: OrpheusStateSnapshot?) {
        self.device = device
        guard device != nil, let snapshot else {
            hasState = false
            failedReads = []
            errorMessage = "No Prism Sound Orpheus found on the bus"
            return
        }

        firmware = snapshot.firmware ?? firmware
        if let unit = snapshot.unit { self.unit = unit }
        for (channel, state) in snapshot.analog.enumerated() {
            if let state { analog[channel] = state }
        }
        if let digital = snapshot.digital { self.digital = digital }
        for (bus, state) in snapshot.mixBuses.enumerated() {
            if let state { mixBuses[bus] = state }
        }
        if let defeats = snapshot.mixDefeats { mixDefeats = defeats }
        syncSource = snapshot.syncSource
        hasState = snapshot.hasAnyState
        failedReads = snapshot.failedReads
        lastRefreshTime = snapshot.updatedAt

        if !hasState {
            errorMessage = "Orpheus detected, but no STATUS command was answered"
        } else if !failedReads.isEmpty {
            errorMessage = "Some reads failed: \(failedReads.joined(separator: ", "))"
        }
    }

    // MARK: - Derived State

    var hasAdatInput: Bool { unit.hasAdatInput }

    var headphoneRouting: OrpheusHeadphoneRouting {
        OrpheusHeadphones.routing(source: unit.headphoneSource,
                                  headphoneBusDefeated: mixDefeats[OrpheusHeadphones.headphoneBus])
    }

    var analogInputTypes: [UInt8] { analog.map(\.inputType) }

    func isLinked(bus: Int, input: Int) -> Bool {
        guard OrpheusMix.isLinkable(input: input) else { return false }
        let inputs = mixBuses[bus].inputs
        return inputs[input & ~1].linked || inputs[input | 1].linked
    }

    // MARK: - Unit

    func setMasterVolume(_ raw: Int16) {
        unit.masterVolume = raw
        send("Master volume \(OrpheusLevel.format(raw, fractionDigits: 1))",
             debounceKey: "master-volume",
             frame: OrpheusControl.masterVolume(raw))
    }

    func setVolumeSelect(bit: Int, enabled: Bool) {
        let mask = OrpheusVolumeSelect.setting(unit.volumeSelectMask, bit: bit, enabled: enabled)
        unit.volumeSelectMask = mask
        send(String(format: "Volume select mask 0x%04X", mask), frame: OrpheusControl.volumeSelect(mask: mask))
    }

    func setMasterMute(_ muted: Bool) {
        unit.masterMute = muted
        send("Master mute \(onOff(muted))", frame: OrpheusControl.flag(.masterMute, muted))
    }

    func setMasterLock(_ locked: Bool) {
        unit.masterLock = locked
        send("Master lock \(onOff(locked))", frame: OrpheusControl.flag(.masterLock, locked))
    }

    func setIdentify(_ enabled: Bool) {
        unit.identify = enabled
        send("Identify \(onOff(enabled))", frame: OrpheusControl.flag(.identify, enabled))
    }

    func setFrontPanelMeterMode(_ mode: UInt8) {
        unit.frontPanelMeterMode = mode
        send("Front panel meters \(mode)", frame: OrpheusControl.value(.frontPanelMeterMode, mode))
    }

    func setMeterBrightness(_ value: UInt8) {
        unit.meterBrightness = value
        send("Meter brightness \(value)", debounceKey: "brightness", frame: OrpheusControl.value(.meterBrightness, value))
    }

    func setSampleRateConverter(_ mode: UInt8) {
        unit.sampleRateConverter = mode
        send("SRC \(mode)", frame: OrpheusControl.value(.sampleRateConverter, mode))
    }

    func setClockOutput(_ mode: UInt8) {
        unit.clockOutput = mode
        send("Clock output \(mode)", frame: OrpheusControl.value(.clockOutput, mode))
    }

    func setAdatMode(_ mode: UInt8) {
        let previousSync = syncSource
        unit.adatMode = mode
        send("ADAT mode \(mode)", frame: OrpheusControl.value(.adatMode, mode))

        let hasInput = OrpheusUnitState.adatModeHasInput(mode)
        if previousSync == .adat && !hasInput {
            setSyncSource(.local)
        } else {
            rereadSyncSource(hasAdatInput: hasInput)
        }
    }

    func setSyncSource(_ source: OrpheusSyncSource) {
        syncSource = source
        let hasAdatInput = self.hasAdatInput
        perform("Sync source \(source.label)") { connector, guid in
            connector.setOrpheusSyncSource(guid: guid, source: source, hasAdatInput: hasAdatInput)
        }
        rereadSyncSource(hasAdatInput: hasAdatInput)
    }

    // MARK: - Analog

    func setLineInputLevel(channel: Int, value: UInt8) {
        analog[channel].lineInputLevel = value
        send("AI\(channel + 1) line level \(value)", frame: OrpheusControl.analog(.lineInputLevel, channel: channel, value: value))
    }

    func setLineOutputLevel(channel: Int, value: UInt8) {
        analog[channel].lineOutputLevel = value
        send("AO\(channel + 1) line level \(value)", frame: OrpheusControl.analog(.lineOutputLevel, channel: channel, value: value))
    }

    func setMicGain(channel: Int, gain: UInt8) {
        let gain = clampGain(gain)
        analog[channel].micGain = gain
        send("AI\(channel + 1) mic gain \(gain) dB",
             debounceKey: "mic-gain-\(channel)",
             frame: OrpheusControl.analog(.micGain, channel: channel, value: gain))
    }

    func setInstrumentGain(channel: Int, gain: UInt8) {
        let gain = clampGain(gain)
        analog[channel].instrumentGain = gain
        send("AI\(channel + 1) instrument gain \(gain) dB",
             debounceKey: "inst-gain-\(channel)",
             frame: OrpheusControl.analog(.instrumentGain, channel: channel, value: gain))
    }

    func setOverkiller(channel: Int, enabled: Bool) {
        analog[channel].overkiller = enabled
        send("AI\(channel + 1) Overkiller \(onOff(enabled))",
             frame: OrpheusControl.analog(.overkiller, channel: channel, value: enabled ? 1 : 0))
    }

    /// Enabling phantom power needs an explicit confirmation from the view.
    func requestPhantom(channel: Int, enabled: Bool) {
        if enabled {
            pendingPhantomChannel = channel
        } else {
            applyPhantom(channel: channel, enabled: false)
        }
    }

    func confirmPendingPhantom() {
        guard let channel = pendingPhantomChannel else { return }
        pendingPhantomChannel = nil
        applyPhantom(channel: channel, enabled: true)
    }

    private func applyPhantom(channel: Int, enabled: Bool) {
        analog[channel].phantom = enabled
        send("AI\(channel + 1) phantom \(onOff(enabled))",
             frame: OrpheusControl.analog(.phantom, channel: channel, value: enabled ? 1 : 0))
    }

    func setFilter(channel: Int, filter: UInt8) {
        analog[channel].filter = filter
        send("AI\(channel + 1) filter \(filter)", frame: OrpheusControl.analog(.filter, channel: channel, value: filter))
    }

    func setPhase(channel: Int, inverted: Bool) {
        analog[channel].phase = inverted
        send("AI\(channel + 1) phase \(onOff(inverted))",
             frame: OrpheusControl.analog(.phase, channel: channel, value: inverted ? 1 : 0))
    }

    func setMidSide(pair: Int, enabled: Bool) {
        analog[pair].midSide = enabled
        send("\(OrpheusMidSide.pairLabel(pair)) mid-side \(onOff(enabled))",
             frame: OrpheusControl.analog(.midSide, channel: pair, value: enabled ? 1 : 0))
    }

    // MARK: - Headphones

    func setHeadphoneRouting(_ routing: OrpheusHeadphoneRouting) {
        let settings = OrpheusHeadphones.settings(for: routing)
        let bus = OrpheusHeadphones.headphoneBus
        unit.headphoneSource = settings.source

        var frames: [Data?] = []
        if let defeat = settings.defeat {
            mixDefeats[bus] = defeat
            mixBuses[bus].defeated = defeat
            frames.append(OrpheusControl.mixBusDefeat(bus: bus, defeated: defeat))
        }
        frames.append(OrpheusControl.value(.headphoneSource, settings.source))
        send("Headphones \(routing.label)", frames: frames)
    }

    // MARK: - Digital

    func setDigitalSampleRate(_ value: UInt8) {
        digital.sampleRate = value
        send("Digital sample rate \(value)", frame: OrpheusControl.value(.digitalSampleRate, value))
    }

    func setDigitalBitDepth(_ value: UInt8) {
        digital.bitDepth = value
        send("Digital bit depth \(value)", frame: OrpheusControl.value(.digitalBitDepth, value))
    }

    func setDigitalSync(_ value: UInt8) {
        digital.syncSource = value
        send("Digital sync \(value)", frame: OrpheusControl.value(.digitalSync, value))
    }

    func setDigitalInputType(_ value: UInt8) {
        digital.inputType = value
        send("Digital input type \(value)", frame: OrpheusControl.value(.digitalInputType, value))
    }

    func setDigitalChannelStatus(_ value: UInt8) {
        digital.channelStatus = value
        send("Digital channel status \(value)", frame: OrpheusControl.value(.digitalChannelStatus, value))
    }

    // MARK: - Mixer

    func setBusGain(bus: Int, gain: Int16) {
        mixBuses[bus].gain = gain
        send("\(OrpheusMix.busNames[bus]) gain \(OrpheusLevel.format(gain))",
             debounceKey: "bus-gain-\(bus)",
             frame: OrpheusControl.mixBusGain(bus: bus, gain: gain))
    }

    func setBusMute(bus: Int, muted: Bool) {
        mixBuses[bus].mute = muted
        send("\(OrpheusMix.busNames[bus]) mute \(onOff(muted))", frame: OrpheusControl.mixBusMute(bus: bus, muted: muted))
    }

    /// "DAW" (defeated) bypasses the hardware mixer for the bus.
    func setBusDefeat(bus: Int, defeated: Bool) {
        mixBuses[bus].defeated = defeated
        mixDefeats[bus] = defeated
        send("\(OrpheusMix.busNames[bus]) \(defeated ? "DAW" : "mixer")",
             frame: OrpheusControl.mixBusDefeat(bus: bus, defeated: defeated))
    }

    func setInputGain(bus: Int, input: Int, gain: Int16) {
        let targets = linkedTargets(bus: bus, input: input)
        for target in targets { mixBuses[bus].inputs[target].gain = gain }
        send("\(OrpheusMix.busNames[bus]) \(OrpheusMix.inputNames[input]) gain \(OrpheusLevel.format(gain))",
             debounceKey: "input-gain-\(bus)-\(input)",
             frames: targets.map { OrpheusControl.mixInputGain(bus: bus, input: $0, gain: gain) })
    }

    func setInputMute(bus: Int, input: Int, muted: Bool) {
        let targets = linkedTargets(bus: bus, input: input)
        for target in targets { mixBuses[bus].inputs[target].mute = muted }
        send("\(OrpheusMix.busNames[bus]) \(OrpheusMix.inputNames[input]) mute \(onOff(muted))",
             frames: targets.map { OrpheusControl.mixInputMute(bus: bus, input: $0, muted: muted) })
    }

    /// Pan for mono inputs; balance on the even input when the pair is linked.
    func setInputPosition(bus: Int, input: Int, position: Int8) {
        let linked = isLinked(bus: bus, input: input)
        let target = linked ? input & ~1 : input
        mixBuses[bus].inputs[target].position = position
        if linked { mixBuses[bus].inputs[target | 1].position = position }
        send("\(OrpheusMix.busNames[bus]) \(OrpheusMix.inputNames[target]) \(linked ? "balance" : "pan") \(position)",
             debounceKey: "input-position-\(bus)-\(target)",
             frame: OrpheusControl.mixInputPosition(bus: bus, input: target, position: position, balance: linked))
    }

    func setSolo(bus: Int, input: Int, enabled: Bool) {
        let mask = OrpheusMix.soloMask(input: enabled ? input : nil, linked: isLinked(bus: bus, input: input))
        mixBuses[bus].soloMask = mask
        send(String(format: "%@ solo mask 0x%04X", OrpheusMix.busNames[bus], mask),
             frame: OrpheusControl.mixBusSolo(bus: bus, mask: mask))
    }

    func setLink(bus: Int, pair: Int, linked: Bool) {
        guard OrpheusMix.linkablePairs.contains(pair) else { return }
        let left = pair
        let right = pair + 1
        var inputs = mixBuses[bus].inputs
        var frames: [Data?] = []

        if linked {
            let balance = OrpheusMix.balanceWhenLinking(leftPan: inputs[left].position, rightPan: inputs[right].position)
            inputs[left].linked = true
            inputs[right].linked = true
            inputs[left].position = balance
            inputs[right].position = balance
            inputs[right].gain = inputs[left].gain
            inputs[right].mute = inputs[left].mute
            frames.append(OrpheusControl.mixInputPosition(bus: bus, input: left, position: balance, balance: true))
            frames.append(OrpheusControl.mixInputGain(bus: bus, input: right, gain: inputs[left].gain))
            frames.append(OrpheusControl.mixInputMute(bus: bus, input: right, muted: inputs[left].mute))
        } else {
            let pans = OrpheusMix.pansWhenUnlinking(balance: inputs[left].position)
            inputs[left].linked = false
            inputs[right].linked = false
            inputs[left].position = pans.left
            inputs[right].position = pans.right
            frames.append(OrpheusControl.mixInputPosition(bus: bus, input: left, position: pans.left, balance: false))
            frames.append(OrpheusControl.mixInputPosition(bus: bus, input: right, position: pans.right, balance: false))
        }

        mixBuses[bus].inputs = inputs
        if let soloed = mixBuses[bus].soloedInput, soloed & ~1 == pair {
            let mask = OrpheusMix.soloMask(input: soloed, linked: linked)
            mixBuses[bus].soloMask = mask
            frames.append(OrpheusControl.mixBusSolo(bus: bus, mask: mask))
        }
        send("\(OrpheusMix.busNames[bus]) \(OrpheusMix.inputNames[left])/\(OrpheusMix.inputNames[right]) link \(onOff(linked))",
             frames: frames)
    }

    func refreshMixBus(_ bus: Int) {
        guard let guid = device?.guid else { return }
        let connector = self.connector
        writeQueue.async { [weak self] in
            let state = connector.getOrpheusMixBus(guid: guid, bus: bus)
            DispatchQueue.main.async {
                guard let self, let state else { return }
                self.mixBuses[bus] = state
                self.mixDefeats[bus] = state.defeated
            }
        }
    }

    // MARK: - Meters

    private func updateMeterPolling() {
        meterTimer?.cancel()
        meterTimer = nil
        meterFailures = 0
        guard metersLive else { return }
        meterTimer = Timer.publish(every: Self.meterInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollMeters() }
    }

    private func pollMeters() {
        guard !meterReadInFlight, let device else { return }
        meterReadInFlight = true
        let connector = self.connector
        let firmware = self.firmware
        let needsRediscovery = meterFailures >= 5

        meterQueue.async { [weak self] in
            let target = needsRediscovery ? (connector.findOrpheusDevice() ?? device) : device
            let snapshot = connector.readOrpheusMeters(device: target, firmware: firmware)
            DispatchQueue.main.async {
                guard let self else { return }
                self.meterReadInFlight = false
                if needsRediscovery {
                    self.device = target
                    self.meterFailures = 0
                }
                guard let snapshot else {
                    self.meterFailures += 1
                    self.meterError = target.nodeID == nil ? "Node ID unknown" : "Meter read failed"
                    return
                }
                self.meterFailures = 0
                self.meterError = nil
                self.applyMeters(snapshot)
            }
        }
    }

    private func applyMeters(_ snapshot: OrpheusMeterSnapshot) {
        meters = snapshot
        if let types = snapshot.analogInputTypes {
            for (channel, type) in types.enumerated() where analog[channel].inputType != type {
                analog[channel].inputType = type
            }
        }
        if let volume = snapshot.masterVolume,
           debouncedWrites["master-volume"] == nil,
           unit.masterVolume != volume {
            unit.masterVolume = volume
        }
        if let async = snapshot.digitalAsynchronous, digital.asynchronous != async { digital.asynchronous = async }
        if let unlocked = snapshot.digitalUnlocked, digital.unlocked != unlocked { digital.unlocked = unlocked }
    }

    // MARK: - Write Pipeline

    private func send(_ label: String, debounceKey: String? = nil, frame: Data?) {
        send(label, debounceKey: debounceKey, frames: [frame])
    }

    private func send(_ label: String, debounceKey: String? = nil, frames: [Data?]) {
        perform(label, debounceKey: debounceKey) { connector, guid in
            frames.allSatisfy { connector.sendOrpheusControl(guid: guid, frame: $0) }
        }
    }

    private func perform(_ label: String,
                         debounceKey: String? = nil,
                         _ operation: @escaping (ASFWDriverConnector, UInt64) -> Bool) {
        guard writesEnabled, let guid = device?.guid else {
            errorMessage = writesEnabled
                ? "No Prism Sound Orpheus found on the bus"
                : "Writes are disabled. Enable them to change settings."
            refresh()
            return
        }

        let connector = self.connector
        let token = UUID()
        let work = DispatchWorkItem { [weak self] in
            let ok = operation(connector, guid)
            DispatchQueue.main.async {
                guard let self else { return }
                if let debounceKey, self.debounceTokens[debounceKey] == token {
                    self.debouncedWrites[debounceKey] = nil
                    self.debounceTokens[debounceKey] = nil
                }
                self.recordWrite(label, succeeded: ok)
            }
        }

        if let debounceKey {
            debouncedWrites[debounceKey]?.cancel()
            debouncedWrites[debounceKey] = work
            debounceTokens[debounceKey] = token
            writeQueue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
        } else {
            writeQueue.async(execute: work)
        }
    }

    private func recordWrite(_ label: String, succeeded: Bool) {
        writeLog.insert(OrpheusWriteLogEntry(timestamp: Date(), label: label, succeeded: succeeded), at: 0)
        if writeLog.count > Self.writeLogLimit {
            writeLog.removeLast(writeLog.count - Self.writeLogLimit)
        }
        errorMessage = succeeded ? nil : "\(label): not accepted by the device. Refresh to resync."
    }

    private func rereadSyncSource(hasAdatInput: Bool) {
        guard let guid = device?.guid else { return }
        let connector = self.connector
        writeQueue.async { [weak self] in
            let source = connector.getOrpheusSyncSource(guid: guid, hasAdatInput: hasAdatInput)
            DispatchQueue.main.async {
                guard let self, let source else { return }
                self.syncSource = source
            }
        }
    }

    private func cancelPendingWrites() {
        debouncedWrites.values.forEach { $0.cancel() }
        debouncedWrites.removeAll()
        debounceTokens.removeAll()
    }

    private func linkedTargets(bus: Int, input: Int) -> [Int] {
        isLinked(bus: bus, input: input) ? [input & ~1, input | 1] : [input]
    }

    private func clampGain(_ gain: UInt8) -> UInt8 {
        min(max(gain, OrpheusAnalogChannelState.gainRange.lowerBound), OrpheusAnalogChannelState.gainRange.upperBound)
    }

    private func onOff(_ value: Bool) -> String { value ? "on" : "off" }
}
