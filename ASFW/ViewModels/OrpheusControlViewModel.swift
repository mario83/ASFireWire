import Combine
import Foundation
import SwiftUI

final class OrpheusMeterFeed: ObservableObject {
    @Published fileprivate(set) var snapshot: OrpheusMeterSnapshot?
    @Published fileprivate(set) var displayedLevels: [UInt16] = []
    @Published fileprivate(set) var displayedClips: [Bool] = []
    @Published fileprivate(set) var error: String?

    private var ballistics = OrpheusMeterBallistics()

    func apply(snapshot: OrpheusMeterSnapshot?) {
        guard let snapshot else { return }
        self.snapshot = snapshot
        let next = ballistics.tick(levels: snapshot.levels, legacyDecay: snapshot.legacyDecay)
        if displayedLevels != next.levels { displayedLevels = next.levels }
        if displayedClips != next.clips { displayedClips = next.clips }
    }
}

struct OrpheusDeviceInfo: Equatable {
    let guid: UInt64
    var guidHex: String { String(format: "0x%016llX", guid) }
}

/// Classic Orpheus chrome bound to Device Controls: reads `ControlSnapshot`,
/// writes through `DeviceControlsViewModel`. No app-side FCP.
@MainActor
final class OrpheusControlViewModel: ObservableObject {
    enum ParameterID {
        static let gain: UInt32 = 0x4F520010
        static let phantom: UInt32 = 0x4F520020
        static let polarity: UInt32 = 0x4F520030
        static let highPassFilter: UInt32 = 0x4F520040
        static let inputLevel: UInt32 = 0x4F520050
        static let overkiller: UInt32 = 0x4F520060
        static let midSide: UInt32 = 0x4F520070
        static let lineOutputLevel: UInt32 = 0x4F520080
        static let analogInputType: UInt32 = 0x4F520090
        static let outputVolume: UInt32 = 0x4F520100
        static let outputMute: UInt32 = 0x4F520101
        static let volumeSelectMask: UInt32 = 0x4F520102
        static let masterLock: UInt32 = 0x4F520103
        static let adatMode: UInt32 = 0x4F520300
        static let clockSource: UInt32 = 0x4F520301
        static let clockOutput: UInt32 = 0x4F520302
        static let sampleRateConverter: UInt32 = 0x4F520303
        static let frontPanelMeterMode: UInt32 = 0x4F520304
        static let meterBrightness: UInt32 = 0x4F520305
        static let identify: UInt32 = 0x4F520306
        static let headphoneSource: UInt32 = 0x4F520307
        static let digitalSampleRate: UInt32 = 0x4F520310
        static let digitalBitDepth: UInt32 = 0x4F520311
        static let digitalSync: UInt32 = 0x4F520312
        static let digitalInputType: UInt32 = 0x4F520313
        static let digitalChannelStatus: UInt32 = 0x4F520314
        static let digitalUnlocked: UInt32 = 0x4F520315
        static let digitalAsynchronous: UInt32 = 0x4F520316
        static let firmwareVersion: UInt32 = 0x4F520317
        static let mixer: UInt32 = 0x4F520400
        static let mixerPan: UInt32 = 0x4F520500
        static let mixerMute: UInt32 = 0x4F520600
        static let mixerSolo: UInt32 = 0x4F520700
        static let mixerBusGain: UInt32 = 0x4F520800
        static let mixerBusMute: UInt32 = 0x4F520900
        static let mixerDefeat: UInt32 = 0x4F520A00
        static let mixerLink: UInt32 = 0x4F520B00
    }

    @Published private(set) var device: OrpheusDeviceInfo?
    @Published private(set) var firmware: OrpheusFirmwareVersion?
    @Published var unit = OrpheusUnitState()
    @Published var analog = Array(repeating: OrpheusAnalogChannelState(), count: OrpheusWire.analogChannelCount)
    @Published var digital = OrpheusDigitalState()
    @Published var mixBuses = Array(repeating: OrpheusMixBusState(), count: OrpheusWire.mixBusCount)
    @Published var syncSource: OrpheusSyncSource?
    @Published var pendingPhantomChannel: Int?
    let meterFeed = OrpheusMeterFeed()

    private weak var controls: DeviceControlsViewModel?
    private var meterTimer: AnyCancellable?
    private var meterReadInFlight = false
    private var meterFailures = 0
    private let meterQueue = DispatchQueue(label: "net.asfw.app.Orpheus.meters", qos: .utility)

    func attach(_ model: DeviceControlsViewModel) {
        let restarted = controls !== model || meterTimer == nil
        controls = model
        if restarted { startMeters() }
    }

    func startMeters() {
        meterTimer?.cancel()
        meterFailures = 0
        meterTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollMeters() }
    }

    func stopMeters() {
        meterTimer?.cancel()
        meterTimer = nil
    }

    func apply(_ snapshot: ControlSnapshot) {
        if let guid = Self.parseGUID(snapshot.guid) {
            device = OrpheusDeviceInfo(guid: guid)
        }
        if let packed = uint16(snapshot, ParameterID.firmwareVersion) {
            firmware = OrpheusFirmwareVersion(major: UInt8(packed >> 8), minor: UInt8(packed & 0xFF))
        }
        for channel in 0..<OrpheusWire.analogChannelCount {
            if !writing(ParameterID.overkiller + UInt32(channel)) {
                analog[channel].overkiller = bool(snapshot, ParameterID.overkiller + UInt32(channel)) ?? analog[channel].overkiller
            }
            if !writing(ParameterID.inputLevel + UInt32(channel)) {
                analog[channel].lineInputLevel = uint8(snapshot, ParameterID.inputLevel + UInt32(channel)) ?? analog[channel].lineInputLevel
            }
            if !writing(ParameterID.lineOutputLevel + UInt32(channel)) {
                analog[channel].lineOutputLevel = uint8(snapshot, ParameterID.lineOutputLevel + UInt32(channel)) ?? analog[channel].lineOutputLevel
            }
            if channel < 4 {
                if !writing(ParameterID.phantom + UInt32(channel)) {
                    analog[channel].phantom = bool(snapshot, ParameterID.phantom + UInt32(channel)) ?? analog[channel].phantom
                }
                if !writing(ParameterID.polarity + UInt32(channel)) {
                    analog[channel].phase = bool(snapshot, ParameterID.polarity + UInt32(channel)) ?? analog[channel].phase
                }
                if !writing(ParameterID.highPassFilter + UInt32(channel)) {
                    analog[channel].filter = uint8(snapshot, ParameterID.highPassFilter + UInt32(channel)) ?? analog[channel].filter
                }
                if !writing(ParameterID.gain + UInt32(channel)),
                   let gain = snapshot.parameter(ParameterID.gain + UInt32(channel))?.value?.doubleValue {
                    let stepped = UInt8(clamping: Int(gain.rounded()))
                    analog[channel].micGain = stepped
                    analog[channel].instrumentGain = stepped
                }
            }
            if let type = uint8(snapshot, ParameterID.analogInputType + UInt32(channel)) {
                analog[channel].inputType = type
            }
        }
        for pair in 0..<OrpheusMidSide.pairCount where !writing(ParameterID.midSide + UInt32(pair)) {
            analog[pair].midSide = bool(snapshot, ParameterID.midSide + UInt32(pair)) ?? analog[pair].midSide
        }
        if !writing(ParameterID.outputVolume), let db = snapshot.parameter(ParameterID.outputVolume)?.value?.doubleValue {
            unit.masterVolume = OrpheusLevel.raw(decibels: db)
        }
        if !writing(ParameterID.outputMute) { unit.masterMute = bool(snapshot, ParameterID.outputMute) ?? unit.masterMute }
        if !writing(ParameterID.masterLock) { unit.masterLock = bool(snapshot, ParameterID.masterLock) ?? unit.masterLock }
        if !writing(ParameterID.volumeSelectMask), let mask = uint16(snapshot, ParameterID.volumeSelectMask) {
            unit.volumeSelectMask = mask
        }
        if !writing(ParameterID.identify) { unit.identify = bool(snapshot, ParameterID.identify) ?? unit.identify }
        if !writing(ParameterID.frontPanelMeterMode) {
            unit.frontPanelMeterMode = uint8(snapshot, ParameterID.frontPanelMeterMode) ?? unit.frontPanelMeterMode
        }
        if !writing(ParameterID.sampleRateConverter) {
            unit.sampleRateConverter = uint8(snapshot, ParameterID.sampleRateConverter) ?? unit.sampleRateConverter
        }
        if !writing(ParameterID.clockOutput) {
            unit.clockOutput = uint8(snapshot, ParameterID.clockOutput) ?? unit.clockOutput
        }
        if !writing(ParameterID.adatMode) { unit.adatMode = uint8(snapshot, ParameterID.adatMode) ?? unit.adatMode }
        if !writing(ParameterID.meterBrightness) {
            unit.meterBrightness = uint8(snapshot, ParameterID.meterBrightness) ?? unit.meterBrightness
        }
        if !writing(ParameterID.headphoneSource) {
            unit.headphoneSource = uint8(snapshot, ParameterID.headphoneSource) ?? unit.headphoneSource
        }
        if !writing(ParameterID.clockSource),
           let value = snapshot.parameter(ParameterID.clockSource)?.value?.intValue {
            syncSource = OrpheusSyncSource(rawValue: UInt8(clamping: value))
        }
        if !writing(ParameterID.digitalSampleRate) {
            digital.sampleRate = uint8(snapshot, ParameterID.digitalSampleRate) ?? digital.sampleRate
        }
        if !writing(ParameterID.digitalBitDepth) {
            digital.bitDepth = uint8(snapshot, ParameterID.digitalBitDepth) ?? digital.bitDepth
        }
        if !writing(ParameterID.digitalSync) {
            digital.syncSource = uint8(snapshot, ParameterID.digitalSync) ?? digital.syncSource
        }
        if !writing(ParameterID.digitalInputType) {
            digital.inputType = uint8(snapshot, ParameterID.digitalInputType) ?? digital.inputType
        }
        if !writing(ParameterID.digitalChannelStatus) {
            digital.channelStatus = uint8(snapshot, ParameterID.digitalChannelStatus) ?? digital.channelStatus
        }
        digital.unlocked = bool(snapshot, ParameterID.digitalUnlocked) ?? digital.unlocked
        digital.asynchronous = bool(snapshot, ParameterID.digitalAsynchronous) ?? digital.asynchronous
        for bus in 0..<OrpheusWire.mixBusCount {
            if !writing(ParameterID.mixerBusGain + UInt32(bus)),
               let db = snapshot.parameter(ParameterID.mixerBusGain + UInt32(bus))?.value?.doubleValue {
                mixBuses[bus].gain = OrpheusLevel.raw(decibels: db)
            }
            if !writing(ParameterID.mixerBusMute + UInt32(bus)) {
                mixBuses[bus].mute = bool(snapshot, ParameterID.mixerBusMute + UInt32(bus)) ?? mixBuses[bus].mute
            }
            if !writing(ParameterID.mixerDefeat + UInt32(bus)) {
                mixBuses[bus].defeated = bool(snapshot, ParameterID.mixerDefeat + UInt32(bus)) ?? mixBuses[bus].defeated
            }
            if !writing(ParameterID.mixerSolo + UInt32(bus)),
               let mask = uint16(snapshot, ParameterID.mixerSolo + UInt32(bus)) {
                mixBuses[bus].soloMask = mask
            }
            for input in 0..<OrpheusWire.mixInputCount {
                let index = UInt32(bus * 12 + input)
                if !writing(ParameterID.mixer + index),
                   let db = snapshot.parameter(ParameterID.mixer + index)?.value?.doubleValue {
                    mixBuses[bus].inputs[input].gain = OrpheusLevel.raw(decibels: db)
                }
                if !writing(ParameterID.mixerMute + index) {
                    mixBuses[bus].inputs[input].mute = bool(snapshot, ParameterID.mixerMute + index) ?? mixBuses[bus].inputs[input].mute
                }
                if !writing(ParameterID.mixerPan + index),
                   !writing(ParameterID.mixerLink + UInt32(bus * 12 + (input & ~1))),
                   let pan = snapshot.parameter(ParameterID.mixerPan + index)?.value?.doubleValue {
                    mixBuses[bus].inputs[input].position = Int8(clamping: Int(pan.rounded()))
                }
                if input % 2 == 0,
                   !writing(ParameterID.mixerLink + index),
                   !writing(ParameterID.mixerPan + index),
                   !writing(ParameterID.mixerPan + index + 1) {
                    let linked = bool(snapshot, ParameterID.mixerLink + index) ?? mixBuses[bus].inputs[input].linked
                    mixBuses[bus].inputs[input].linked = linked
                    mixBuses[bus].inputs[input | 1].linked = linked
                }
            }
        }
    }

    var hasAdatInput: Bool { unit.hasAdatInput }
    var analogInputTypes: [UInt8] { analog.map(\.inputType) }

    var headphoneRouting: OrpheusHeadphoneRouting {
        OrpheusHeadphones.routing(source: unit.headphoneSource, headphoneBusDefeated: mixBuses[OrpheusHeadphones.headphoneBus].defeated)
    }

    func isLinked(bus: Int, input: Int) -> Bool {
        guard OrpheusMix.isLinkable(input: input) else { return false }
        return mixBuses[bus].inputs[input & ~1].linked
    }

    func setMasterVolume(_ raw: Int16) {
        unit.masterVolume = raw
        write(ParameterID.outputVolume, .double(Double(raw) / 256.0))
    }

    func setVolumeSelect(bit: Int, enabled: Bool) {
        let mask = OrpheusVolumeSelect.setting(unit.volumeSelectMask, bit: bit, enabled: enabled)
        unit.volumeSelectMask = mask
        write(ParameterID.volumeSelectMask, .double(Double(mask)))
    }

    func setMasterMute(_ muted: Bool) {
        unit.masterMute = muted
        write(ParameterID.outputMute, .bool(muted))
    }

    func setMasterLock(_ locked: Bool) {
        unit.masterLock = locked
        write(ParameterID.masterLock, .bool(locked))
    }

    func setIdentify(_ enabled: Bool) {
        unit.identify = enabled
        write(ParameterID.identify, .bool(enabled))
    }

    func setFrontPanelMeterMode(_ mode: UInt8) {
        unit.frontPanelMeterMode = mode
        write(ParameterID.frontPanelMeterMode, .int(Int64(mode)))
    }

    func setMeterBrightness(_ value: UInt8) {
        unit.meterBrightness = value
        write(ParameterID.meterBrightness, .double(Double(value)))
    }

    func setSampleRateConverter(_ mode: UInt8) {
        unit.sampleRateConverter = mode
        write(ParameterID.sampleRateConverter, .int(Int64(mode)))
    }

    func setClockOutput(_ mode: UInt8) {
        unit.clockOutput = mode
        write(ParameterID.clockOutput, .int(Int64(mode)))
    }

    func setAdatMode(_ mode: UInt8) {
        let previousSync = syncSource
        unit.adatMode = mode
        write(ParameterID.adatMode, .int(Int64(mode)))
        if previousSync == .adat && !OrpheusUnitState.adatModeHasInput(mode) {
            setSyncSource(.local)
        }
    }

    func setSyncSource(_ source: OrpheusSyncSource) {
        syncSource = source
        write(ParameterID.clockSource, .int(Int64(source.rawValue)))
    }

    func setLineInputLevel(channel: Int, value: UInt8) {
        analog[channel].lineInputLevel = value
        write(ParameterID.inputLevel + UInt32(channel), .int(Int64(value)))
    }

    func setLineOutputLevel(channel: Int, value: UInt8) {
        analog[channel].lineOutputLevel = value
        write(ParameterID.lineOutputLevel + UInt32(channel), .int(Int64(value)))
    }

    func setMicGain(channel: Int, gain: UInt8) {
        analog[channel].micGain = gain
        write(ParameterID.gain + UInt32(channel), .double(Double(gain)))
    }

    func setInstrumentGain(channel: Int, gain: UInt8) {
        analog[channel].instrumentGain = gain
        write(ParameterID.gain + UInt32(channel), .double(Double(gain)))
    }

    func setOverkiller(channel: Int, enabled: Bool) {
        analog[channel].overkiller = enabled
        write(ParameterID.overkiller + UInt32(channel), .bool(enabled))
    }

    func requestPhantom(channel: Int, enabled: Bool) {
        if enabled { pendingPhantomChannel = channel }
        else { applyPhantom(channel: channel, enabled: false) }
    }

    func confirmPendingPhantom() {
        guard let channel = pendingPhantomChannel else { return }
        pendingPhantomChannel = nil
        applyPhantom(channel: channel, enabled: true)
    }

    func setFilter(channel: Int, filter: UInt8) {
        analog[channel].filter = filter
        write(ParameterID.highPassFilter + UInt32(channel), .int(Int64(filter)))
    }

    func setPhase(channel: Int, inverted: Bool) {
        analog[channel].phase = inverted
        write(ParameterID.polarity + UInt32(channel), .bool(inverted))
    }

    func setMidSide(pair: Int, enabled: Bool) {
        analog[pair].midSide = enabled
        write(ParameterID.midSide + UInt32(pair), .bool(enabled))
    }

    func setHeadphoneRouting(_ routing: OrpheusHeadphoneRouting) {
        let settings = OrpheusHeadphones.settings(for: routing)
        unit.headphoneSource = settings.source
        let defeat = settings.defeat
        Task {
            await writeNow(ParameterID.headphoneSource, .int(Int64(settings.source)))
            if let defeat {
                mixBuses[OrpheusHeadphones.headphoneBus].defeated = defeat
                await writeNow(ParameterID.mixerDefeat + UInt32(OrpheusHeadphones.headphoneBus), .bool(defeat))
            }
        }
    }

    func setDigitalSampleRate(_ value: UInt8) {
        digital.sampleRate = value
        write(ParameterID.digitalSampleRate, .int(Int64(value)))
    }
    func setDigitalBitDepth(_ value: UInt8) {
        digital.bitDepth = value
        write(ParameterID.digitalBitDepth, .int(Int64(value)))
    }
    func setDigitalSync(_ value: UInt8) {
        digital.syncSource = value
        write(ParameterID.digitalSync, .int(Int64(value)))
    }
    func setDigitalInputType(_ value: UInt8) {
        digital.inputType = value
        write(ParameterID.digitalInputType, .int(Int64(value)))
    }
    func setDigitalChannelStatus(_ value: UInt8) {
        digital.channelStatus = value
        write(ParameterID.digitalChannelStatus, .int(Int64(value)))
    }

    func setBusGain(bus: Int, gain: Int16) {
        mixBuses[bus].gain = gain
        write(ParameterID.mixerBusGain + UInt32(bus), .double(Double(gain) / 256.0))
    }

    func setBusMute(bus: Int, muted: Bool) {
        mixBuses[bus].mute = muted
        write(ParameterID.mixerBusMute + UInt32(bus), .bool(muted))
    }

    func setBusDefeat(bus: Int, defeated: Bool) {
        mixBuses[bus].defeated = defeated
        write(ParameterID.mixerDefeat + UInt32(bus), .bool(defeated))
    }

    func setInputGain(bus: Int, input: Int, gain: Int16) {
        for target in linkedTargets(bus: bus, input: input) {
            mixBuses[bus].inputs[target].gain = gain
            write(ParameterID.mixer + UInt32(bus * 12 + target), .double(Double(gain) / 256.0))
        }
    }

    func setInputMute(bus: Int, input: Int, muted: Bool) {
        for target in linkedTargets(bus: bus, input: input) {
            mixBuses[bus].inputs[target].mute = muted
            write(ParameterID.mixerMute + UInt32(bus * 12 + target), .bool(muted))
        }
    }

    func setInputPosition(bus: Int, input: Int, position: Int8) {
        let linked = isLinked(bus: bus, input: input)
        let target = linked ? input & ~1 : input
        mixBuses[bus].inputs[target].position = position
        if linked { mixBuses[bus].inputs[target | 1].position = position }
        write(ParameterID.mixerPan + UInt32(bus * 12 + target), .double(Double(position)))
    }

    func setSolo(bus: Int, input: Int, enabled: Bool) {
        let mask = OrpheusMix.soloMask(input: enabled ? input : nil, linked: isLinked(bus: bus, input: input))
        mixBuses[bus].soloMask = mask
        write(ParameterID.mixerSolo + UInt32(bus), .double(Double(mask)))
    }

    func setLink(bus: Int, pair: Int, linked: Bool) {
        // Original SetMix type 5 skips the DAW pair (inputs 10/11): hardware
        // keeps that pair in balance mode and rejects MixInputPan.
        guard OrpheusMix.hardwareLinkablePairs.contains(pair) else { return }
        var inputs = mixBuses[bus].inputs
        if linked {
            let balance = OrpheusMix.balanceWhenLinking(leftPan: inputs[pair].position, rightPan: inputs[pair + 1].position)
            inputs[pair].linked = true
            inputs[pair + 1].linked = true
            inputs[pair].position = balance
            inputs[pair + 1].position = balance
            inputs[pair + 1].gain = inputs[pair].gain
            inputs[pair + 1].mute = inputs[pair].mute
        } else {
            let pans = OrpheusMix.pansWhenUnlinking(balance: inputs[pair].position)
            inputs[pair].linked = false
            inputs[pair + 1].linked = false
            inputs[pair].position = pans.left
            inputs[pair + 1].position = pans.right
        }
        mixBuses[bus].inputs = inputs
        var soloMask: UInt16?
        if let soloed = mixBuses[bus].soloedInput, soloed & ~1 == pair {
            let mask = OrpheusMix.soloMask(input: soloed, linked: linked)
            mixBuses[bus].soloMask = mask
            soloMask = mask
        }
        Task {
            // MixerLink already sends MixInputPan / MixInputBalance for the pair.
            await writeNow(ParameterID.mixerLink + UInt32(bus * 12 + pair), .bool(linked))
            if let soloMask {
                await writeNow(ParameterID.mixerSolo + UInt32(bus), .double(Double(soloMask)))
            }
        }
    }

    private func pollMeters() {
        guard !meterReadInFlight, let guid = device?.guid, let connector = controls?.orpheusMeterConnector else { return }
        meterReadInFlight = true
        let hasStatusQuadlet = firmware?.hasMeterStatusQuadlet ?? true
        let rediscover = meterFailures >= 5
        meterQueue.async { [weak self] in
            let snapshot = connector.readOrpheusMeters(guid: guid, hasStatusQuadlet: hasStatusQuadlet)
            DispatchQueue.main.async {
                guard let self else { return }
                self.meterReadInFlight = false
                if rediscover { self.meterFailures = 0 }
                guard let snapshot else {
                    self.meterFailures += 1
                    if self.meterFeed.error != "Meter read failed" {
                        self.meterFeed.error = "Meter read failed"
                    }
                    return
                }
                self.meterFailures = 0
                if self.meterFeed.error != nil { self.meterFeed.error = nil }
                self.meterFeed.apply(snapshot: snapshot)
                if let types = snapshot.analogInputTypes {
                    for (channel, type) in types.enumerated() where self.analog[channel].inputType != type {
                        self.analog[channel].inputType = type
                    }
                }
                if let async = snapshot.digitalAsynchronous { self.digital.asynchronous = async }
                if let unlocked = snapshot.digitalUnlocked { self.digital.unlocked = unlocked }
            }
        }
    }

    // MARK: - Snapshot helpers

    private func applyPhantom(channel: Int, enabled: Bool) {
        analog[channel].phantom = enabled
        write(ParameterID.phantom + UInt32(channel), .bool(enabled))
    }

    private func linkedTargets(bus: Int, input: Int) -> [Int] {
        isLinked(bus: bus, input: input) ? [input & ~1, input | 1] : [input]
    }

    private func write(_ id: UInt32, _ value: ControlValue) {
        Task { await writeNow(id, value) }
    }

    private func writeNow(_ id: UInt32, _ value: ControlValue) async {
        await controls?.write(id, value)
    }

    private func writing(_ id: UInt32) -> Bool { controls?.writeState(id).isWriting ?? false }

    private func bool(_ snapshot: ControlSnapshot, _ id: UInt32) -> Bool? {
        snapshot.parameter(id)?.value?.boolValue
    }

    private func uint8(_ snapshot: ControlSnapshot, _ id: UInt32) -> UInt8? {
        uint16(snapshot, id).map { UInt8(clamping: Int($0)) }
    }

    private func uint16(_ snapshot: ControlSnapshot, _ id: UInt32) -> UInt16? {
        if let value = snapshot.parameter(id)?.value?.intValue { return UInt16(clamping: value) }
        if let value = snapshot.parameter(id)?.value?.doubleValue { return UInt16(clamping: Int(value.rounded())) }
        return nil
    }

    private static func parseGUID(_ text: String) -> UInt64? {
        let hex = text.hasPrefix("0x") || text.hasPrefix("0X") ? String(text.dropFirst(2)) : text
        return UInt64(hex, radix: 16)
    }
}
