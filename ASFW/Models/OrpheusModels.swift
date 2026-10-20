import Foundation

// MARK: - Prism Sound Orpheus UI model
//
// Channel counts, scales and labels for the classic chrome. Vendor FCP frames
// stay in the dext; Device Controls must not rebuild them here.

nonisolated enum OrpheusWire {
    static let analogChannelCount = 8
    static let mixBusCount = 6
    static let mixInputCount = 12

    static let meterAddressHigh: UInt16 = 0xFFC7
    static let meterAddressLow: UInt32 = 0x0060_0420
    static let meterCount = 50
    static let legacyMeterReadLength: UInt32 = 200
    static let meterReadLength: UInt32 = 204
}

// MARK: - Gain Helpers (signed Q8.8 dB, Int16.min = -inf)

nonisolated enum OrpheusLevel {
    static let silent: Int16 = .min
    static let unity: Int16 = 0

    static func decibels(_ raw: Int16) -> Double? {
        raw == silent ? nil : Double(raw) / 256.0
    }

    static func raw(decibels: Double?) -> Int16 {
        guard let decibels else { return silent }
        let scaled = (decibels * 256.0).rounded()
        return Int16(clamping: Int(max(Double(Int16.min + 1), min(Double(Int16.max), scaled))))
    }
}

/// The vendor app's control positions, lowest (-inf) first. Values between two
/// steps (set from the front panel or another client) snap to the nearest one.
nonisolated struct OrpheusSteppedScale {
    let steps: [Int16]

    var maxPosition: Int { steps.count - 1 }

    func position(for raw: Int16) -> Int {
        guard raw != OrpheusLevel.silent else { return 0 }
        let distance = { (index: Int) in abs(Int(steps[index]) - Int(raw)) }
        return steps.indices.dropFirst().min { distance($0) < distance($1) } ?? 0
    }

    func raw(at position: Int) -> Int16 {
        steps[min(max(position, 0), maxPosition)]
    }

    /// `HAPI_BIG_KNOB_VALUES`: the 30 positions of the master volume knob and its LED ring.
    static let masterVolume = OrpheusSteppedScale(steps: [
        .min, -15872, -13312, -11776, -10752, -10240, -9728, -9216, -8704, -8192,
        -7680, -7168, -6656, -6144, -5632, -5120, -4608, -4096, -3584, -3072,
        -2560, -2048, -1792, -1536, -1280, -1024, -768, -512, -256, 0,
    ])

    /// `_gainValues` of `HapiMixSlider`: 166 fader positions from -inf to 0 dB.
    static let mixGain = OrpheusSteppedScale(steps: [
        .min, -22528, -22016, -21504, -20992, -20480, -19968, -19456, -18944, -18432,
        -17920, -17408, -16896, -16384, -15872, -15360, -15104, -14848, -14592, -14336,
        -14080, -13824, -13568, -13312, -13056, -12800, -12673, -12544, -12417, -12288,
        -12161, -12032, -11905, -11776, -11649, -11520, -11393, -11264, -11137, -11008,
        -10881, -10752, -10625, -10496, -10369, -10240, -10113, -9984, -9857, -9728,
        -9601, -9472, -9345, -9216, -9089, -8960, -8833, -8704, -8577, -8448,
        -8321, -8192, -8065, -7936, -7809, -7680, -7553, -7424, -7297, -7168,
        -7041, -6912, -6785, -6656, -6529, -6400, -6273, -6144, -6017, -5888,
        -5761, -5632, -5505, -5376, -5249, -5120, -5057, -4993, -4929, -4864,
        -4801, -4737, -4673, -4608, -4545, -4481, -4417, -4352, -4289, -4225,
        -4161, -4096, -4033, -3969, -3905, -3840, -3777, -3713, -3649, -3584,
        -3521, -3457, -3393, -3328, -3265, -3201, -3137, -3072, -3009, -2945,
        -2881, -2816, -2753, -2689, -2625, -2560, -2497, -2433, -2369, -2304,
        -2241, -2177, -2113, -2048, -1985, -1921, -1857, -1792, -1729, -1665,
        -1601, -1536, -1473, -1409, -1345, -1280, -1217, -1153, -1089, -1024,
        -961, -897, -833, -768, -705, -641, -577, -512, -449, -385,
        -321, -256, -193, -129, -65, 0,
    ])
}

// MARK: - Choice Lists

nonisolated struct OrpheusChoice: Identifiable, Hashable {
    let value: UInt8
    let label: String
    let shortLabel: String
    var id: UInt8 { value }

    init(value: UInt8, label: String, shortLabel: String? = nil) {
        self.value = value
        self.label = label
        self.shortLabel = shortLabel ?? label
    }
}

nonisolated enum OrpheusChoices {
    static let frontPanelMeter = [
        OrpheusChoice(value: 0, label: "Input"),
        OrpheusChoice(value: 1, label: "Output"),
    ]

    static let sampleRateConverter = [
        OrpheusChoice(value: 0, label: "Off"),
        OrpheusChoice(value: 1, label: "Digital input", shortLabel: "DI"),
        OrpheusChoice(value: 2, label: "Digital output", shortLabel: "DO"),
    ]

    static let clockOutput = [
        OrpheusChoice(value: 0, label: "fs (word clock)", shortLabel: "fs"),
        OrpheusChoice(value: 1, label: "Base clock", shortLabel: "base"),
        OrpheusChoice(value: 2, label: "256× clock", shortLabel: "256x"),
    ]

    static func adatModes(firmware: OrpheusFirmwareVersion?) -> [OrpheusChoice] {
        var choices = [
            OrpheusChoice(value: 0, label: "None"),
            OrpheusChoice(value: 1, label: "Send"),
            OrpheusChoice(value: 2, label: "Return"),
            OrpheusChoice(value: 3, label: "Send/Return", shortLabel: "S/R"),
        ]
        if firmware?.supportsAdatDirect ?? true {
            choices.append(OrpheusChoice(value: 4, label: "Direct"))
        }
        return choices
    }

    static let lineLevel = [
        OrpheusChoice(value: 1, label: "+4 dBu"),
        OrpheusChoice(value: 0, label: "-10 dBV"),
    ]

    static func filters(channel: Int) -> [OrpheusChoice] {
        var choices = [
            OrpheusChoice(value: 0, label: "Flat"),
            OrpheusChoice(value: 1, label: "80 Hz", shortLabel: "80Hz"),
        ]
        if channel < 2 {
            choices.append(OrpheusChoice(value: 2, label: "RIAA"))
        }
        return choices
    }

    static let digitalSampleRate = [
        OrpheusChoice(value: 1, label: "44.1 kHz", shortLabel: "44.1k"),
        OrpheusChoice(value: 2, label: "48 kHz", shortLabel: "48k"),
        OrpheusChoice(value: 3, label: "88.2 kHz", shortLabel: "88.2k"),
        OrpheusChoice(value: 4, label: "96 kHz", shortLabel: "96k"),
        OrpheusChoice(value: 5, label: "176.4 kHz", shortLabel: "176k"),
        OrpheusChoice(value: 6, label: "192 kHz", shortLabel: "192k"),
    ]

    static let digitalBitDepth = [
        OrpheusChoice(value: 24, label: "24 bit", shortLabel: "24bit"),
        OrpheusChoice(value: 16, label: "16 bit", shortLabel: "16bit"),
        OrpheusChoice(value: 0, label: "16 bit SNS1", shortLabel: "SNS1"),
        OrpheusChoice(value: 1, label: "16 bit SNS2", shortLabel: "SNS2"),
        OrpheusChoice(value: 2, label: "16 bit SNS3", shortLabel: "SNS3"),
        OrpheusChoice(value: 3, label: "16 bit SNS4", shortLabel: "SNS4"),
    ]

    static let digitalSync = [
        OrpheusChoice(value: 0, label: "Local"),
        OrpheusChoice(value: 1, label: "Word clock", shortLabel: "WCK"),
        OrpheusChoice(value: 2, label: "Digital input", shortLabel: "DI"),
    ]

    static let digitalInputType = [
        OrpheusChoice(value: 0, label: "S/PDIF (coaxial)", shortLabel: "S/PDIF"),
        OrpheusChoice(value: 1, label: "TOSLINK (optical)", shortLabel: "TOS"),
    ]

    static let digitalChannelStatus = [
        OrpheusChoice(value: 0, label: "S/PDIF (consumer)", shortLabel: "SPDIF"),
        OrpheusChoice(value: 1, label: "AES3 (professional)", shortLabel: "AES3"),
    ]

    /// Ensures a picker can always display the value reported by the device.
    static func including(_ current: UInt8?, in choices: [OrpheusChoice]) -> [OrpheusChoice] {
        guard let current, !choices.contains(where: { $0.value == current }) else { return choices }
        return choices + [OrpheusChoice(value: current, label: "Unknown (\(current))")]
    }
}

// MARK: - Firmware

nonisolated struct OrpheusFirmwareVersion: Equatable, CustomStringConvertible {
    var major: UInt8
    var minor: UInt8

    init(major: UInt8, minor: UInt8) {
        self.major = major
        self.minor = minor
    }

    var supportsAdatDirect: Bool {
        major != 0 && (major != 1 || minor > 1)
    }

    var hasMeterStatusQuadlet: Bool {
        major >= 2 || (major == 1 && minor >= 3)
    }

    var description: String { "\(major).\(minor)" }
}

// MARK: - Unit State (0xBF)

nonisolated struct OrpheusUnitState: Equatable {
    var masterVolume: Int16 = OrpheusLevel.silent
    var volumeSelectMask: UInt16 = 0
    var masterMute = false
    var masterLock = false
    var identify = false
    var frontPanelMeterMode: UInt8 = 0
    var sampleRateConverter: UInt8 = 0
    var clockOutput: UInt8 = 0
    var adatMode: UInt8 = 0
    var headphoneSource: UInt8 = OrpheusHeadphones.dedicatedMixSource
    var meterBrightness: UInt8 = 15

    var hasAdatInput: Bool { OrpheusUnitState.adatModeHasInput(adatMode) }

    static func adatModeHasInput(_ mode: UInt8) -> Bool { (2...4).contains(mode) }
}

/// Bits of the master volume selection mask, one per output the front-panel
/// knob controls. Setting the headphone bit also sets its partner bit.
nonisolated enum OrpheusVolumeSelect {
    static let outputNames = ["AO 1", "AO 2", "AO 3", "AO 4", "AO 5", "AO 6", "AO 7", "AO 8"]
    static let headphoneBit = 8
    static let headphonePartnerBit = 9

    static func setting(_ mask: UInt16, bit: Int, enabled: Bool) -> UInt16 {
        var bits = [bit]
        if bit == headphoneBit { bits.append(headphonePartnerBit) }
        var result = mask
        for bit in bits {
            if enabled {
                result |= UInt16(1) << bit
            } else {
                result &= ~(UInt16(1) << bit)
            }
        }
        return result
    }
}

// MARK: - Analog Channels (0xCF)

nonisolated enum OrpheusAnalogInputType: UInt8 {
    case line = 0
    case mic = 1
    case instrument = 2

    var label: String {
        switch self {
        case .line: return "Line"
        case .mic: return "Mic"
        case .instrument: return "Inst"
        }
    }
}

nonisolated struct OrpheusAnalogChannelState: Equatable {
    static let gainRange: ClosedRange<UInt8> = 10...65

    var inputType: UInt8 = 0
    var lineInputLevel: UInt8 = 1
    var lineOutputLevel: UInt8 = 1
    var overkiller = false
    var midSide = false
    var phantom = false
    var phase = false
    var filter: UInt8 = 0
    var micGain: UInt8 = 10
    var instrumentGain: UInt8 = 10

    var type: OrpheusAnalogInputType? { OrpheusAnalogInputType(rawValue: inputType) }

    static func hasPreamp(channel: Int) -> Bool { channel < 4 }
    static func hasInstrumentInput(channel: Int) -> Bool { channel < 2 }
}

/// Mid-side decoding exists for AI 1/2 and AI 3/4; the command channel is the
/// pair index and the state lives in that channel's `midSide` flag.
nonisolated enum OrpheusMidSide {
    static let pairCount = 2

    static func isAvailable(pair: Int, inputTypes: [UInt8]) -> Bool {
        let first = pair * 2
        guard pair >= 0, pair < pairCount, first + 1 < inputTypes.count else { return false }
        return inputTypes[first] < 2 && inputTypes[first + 1] < 2
    }
}

// MARK: - Headphones

nonisolated enum OrpheusHeadphoneRouting: Hashable {
    case mixer
    case daw
    case mirror(bus: Int)

    var label: String {
        switch self {
        case .mixer: return "Headphone mixer"
        case .daw: return "DAW"
        case .mirror(let bus): return "Mirror \(OrpheusMix.busNames[bus])"
        }
    }
}

nonisolated enum OrpheusHeadphones {
    static let dedicatedMixSource: UInt8 = 5
    static let headphoneBus = 5

    static let routings: [OrpheusHeadphoneRouting] =
        [.mixer, .daw] + (0..<headphoneBus).map { .mirror(bus: $0) }

    static func routing(source: UInt8, headphoneBusDefeated: Bool) -> OrpheusHeadphoneRouting {
        if Int(source) < headphoneBus { return .mirror(bus: Int(source)) }
        return headphoneBusDefeated ? .daw : .mixer
    }

    /// Source byte for `0xCA` and, for the dedicated mix, the headphone bus defeat.
    static func settings(for routing: OrpheusHeadphoneRouting) -> (source: UInt8, defeat: Bool?) {
        switch routing {
        case .mixer: return (dedicatedMixSource, false)
        case .daw: return (dedicatedMixSource, true)
        case .mirror(let bus): return (UInt8(bus), nil)
        }
    }
}

// MARK: - Digital I/O (0xDF)

nonisolated struct OrpheusDigitalState: Equatable {
    var inputType: UInt8 = 0
    var channelStatus: UInt8 = 0
    var bitDepth: UInt8 = 24
    var sampleRate: UInt8 = 2
    var syncSource: UInt8 = 0
    var unlocked = false
    var asynchronous = false
}

// MARK: - Mixer (0xEF / 0xE0)

nonisolated enum OrpheusMix {
    static let busNames = ["AO 1/2", "AO 3/4", "AO 5/6", "AO 7/8", "DO 1/2", "Headphones"]
    static let inputNames = ["AI 1", "AI 2", "AI 3", "AI 4", "AI 5", "AI 6", "AI 7", "AI 8",
                             "DI 1", "DI 2", "DAW 1", "DAW 2"]
    static let positionRange: ClosedRange<Int8> = -20...20
    /// Host playback meters start after AI/DI/AO/DO/HP (0…21).
    static let dawMeterBase = 22
    /// Even inputs that can be stereo-linked with the next one.
    /// Pairs the mixer can actually stereo-link. The DAW pair (10/11) is
    /// always in balance mode on the hardware; original Orpheus hides that
    /// stereo button and refuses SetMix type 5 when `(input | 1) == 11`.
    static let hardwareLinkablePairs = [0, 2, 4, 6, 8]
    static let linkablePairs = hardwareLinkablePairs + [10]

    /// Each mix bus returns its own DAW pair: AO 1/2 → DAW 1/2, AO 3/4 → DAW 3/4, …
    static func inputName(bus: Int, input: Int) -> String {
        if input < 10 { return inputNames[input] }
        return "DAW \(bus * 2 + input - 9)"
    }

    static func meterIndex(bus: Int, input: Int) -> Int {
        input < 10 ? input : dawMeterBase + bus * 2 + (input - 10)
    }

    static func isLinkable(input: Int) -> Bool {
        linkablePairs.contains(input & ~1)
    }

    static func partner(of input: Int) -> Int { input ^ 1 }

    /// Balance of a newly linked pair: the average of the two pans.
    static func balanceWhenLinking(leftPan: Int8, rightPan: Int8) -> Int8 {
        Int8((Int(leftPan) + Int(rightPan)) / 2)
    }

    /// Pans of a pair being unlinked, derived from its balance.
    static func pansWhenUnlinking(balance: Int8) -> (left: Int8, right: Int8) {
        let value = Int(balance)
        if value < 0 {
            return (-20, Int8(clamping: value * 2 + 20))
        }
        return (Int8(clamping: value * 2 - 20), 20)
    }

    /// Solo is exclusive: a single input, plus its partner when linked.
    static func soloMask(input: Int?, linked: Bool) -> UInt16 {
        guard let input, (0..<OrpheusWire.mixInputCount).contains(input) else { return 0 }
        var mask = UInt16(1) << input
        if linked { mask |= UInt16(1) << partner(of: input) }
        return mask
    }
}

nonisolated struct OrpheusMixInputState: Equatable {
    var gain: Int16 = OrpheusLevel.silent
    var mute = false
    var linked = false
    /// Pan for mono inputs, balance when the pair is linked.
    var position: Int8 = 0
}

nonisolated struct OrpheusMixBusState: Equatable {
    var gain: Int16 = OrpheusLevel.unity
    var mute = false
    var soloMask: UInt16 = 0
    var defeated = false
    var inputs = Array(repeating: OrpheusMixInputState(), count: OrpheusWire.mixInputCount)

    var soloedInput: Int? {
        (0..<OrpheusWire.mixInputCount).first { soloMask & (UInt16(1) << $0) != 0 }
    }
}

// MARK: - Sync Source (AV/C SIGNAL SOURCE on the unit)

nonisolated enum OrpheusSyncSource: UInt8, CaseIterable, Identifiable {
    case csp = 0
    case firewire = 1
    case local = 2
    case digitalInput = 3
    case adat = 4
    case wordClock = 5

    var id: UInt8 { rawValue }

    var label: String {
        switch self {
        case .csp: return "CSP"
        case .firewire: return "FireWire (slave)"
        case .local: return "Local"
        case .digitalInput: return "Digital input"
        case .adat: return "ADAT"
        case .wordClock: return "Word clock"
        }
    }

    var classicLabel: String {
        switch self {
        case .csp: return "CSP"
        case .firewire: return "FW"
        case .local: return "Local"
        case .digitalInput: return "DI"
        case .adat: return "ADAT"
        case .wordClock: return "WCK"
        }
    }

    /// The vendor app lists FireWire only while it is the active source.
    static func selectable(current: OrpheusSyncSource?, hasAdatInput: Bool) -> [OrpheusSyncSource] {
        allCases.filter { source in
            switch source {
            case .firewire: return current == .firewire
            case .adat: return hasAdatInput
            default: return true
            }
        }
    }
}

// MARK: - Meters

nonisolated struct OrpheusMeterSnapshot: Equatable {
    var levels: [UInt16]
    var masterVolume: Int16?
    var analogInputTypes: [UInt8]?
    var digitalAsynchronous: Bool?
    var digitalUnlocked: Bool?
    var legacyDecay = false

    static let analogMeterCount = 8
    static let legacyDecayStartIndex = 22

    init?(data: Data, hasStatusQuadlet: Bool) {
        let bytes = [UInt8](data)
        let meterBytes = OrpheusWire.meterCount * 4
        guard bytes.count >= meterBytes else { return nil }
        legacyDecay = !hasStatusQuadlet
        levels = (0..<OrpheusWire.meterCount).map { index in
            let base = index * 4
            if !hasStatusQuadlet && index >= Self.legacyDecayStartIndex {
                return Self.uint16BE(bytes[base], bytes[base + 1])
            }
            return Self.uint16BE(bytes[base + 2], bytes[base + 3])
        }
        guard hasStatusQuadlet, bytes.count >= meterBytes + 4, bytes[meterBytes + 3] != 0 else { return }
        masterVolume = Self.int16BE(bytes[meterBytes], bytes[meterBytes + 1])
        let types = bytes[meterBytes + 2]
        analogInputTypes = (0..<4).map { (types >> ($0 * 2)) & 0x03 }
        digitalAsynchronous = bytes[meterBytes + 3] & 0x02 != 0
        digitalUnlocked = bytes[meterBytes + 3] & 0x04 != 0
    }

    func fullScale(at index: Int) -> UInt16 {
        legacyDecay && index >= Self.legacyDecayStartIndex
            ? OrpheusMeterScale.signedFullScale
            : OrpheusMeterScale.unsignedFullScale
    }

    private static func uint16BE(_ high: UInt8, _ low: UInt8) -> UInt16 {
        (UInt16(high) << 8) | UInt16(low)
    }

    private static func int16BE(_ high: UInt8, _ low: UInt8) -> Int16 {
        Int16(bitPattern: uint16BE(high, low))
    }
}

nonisolated struct OrpheusMeterChannelBallistics: Equatable {
    static let clipHoldTicks: UInt8 = 12
    static let decayMultiplier: UInt32 = 0xDEF7

    var current: UInt16 = 0
    var previous: UInt16 = 0
    var clipTicks: UInt8 = 0

    mutating func setValue(_ sample: UInt16) {
        if sample == 0 {
            if current != 0 {
                if previous == 0 { current = 0 } else { previous = 0 }
            }
        } else {
            previous = current
            current = sample
        }
        if current >= OrpheusMeterScale.clipThreshold {
            clipTicks = Self.clipHoldTicks
        } else if clipTicks > 0 {
            clipTicks -= 1
        }
    }

    mutating func setValueWithDecay(_ sample: UInt16) {
        let decayed = UInt32(current) * Self.decayMultiplier >> 16
        current = UInt16(max(UInt32(sample), decayed))
        if current >= OrpheusMeterScale.signedFullScale &- 0xFF {
            clipTicks = Self.clipHoldTicks
        } else if clipTicks > 0 {
            clipTicks -= 1
        }
    }
}

nonisolated struct OrpheusMeterBallistics {
    private var channels: [OrpheusMeterChannelBallistics] = []

    mutating func tick(levels: [UInt16], legacyDecay: Bool = false) -> (levels: [UInt16], clips: [Bool]) {
        if channels.count != levels.count {
            channels = Array(repeating: OrpheusMeterChannelBallistics(), count: levels.count)
        }
        for index in levels.indices {
            if legacyDecay && index >= OrpheusMeterSnapshot.legacyDecayStartIndex {
                channels[index].setValueWithDecay(levels[index])
            } else {
                channels[index].setValue(levels[index])
            }
        }
        return (channels.map(\.current), channels.map { $0.clipTicks > 0 })
    }
}

/// Meter levels are linear peak amplitudes; the vendor meter spans 48 dB in
/// 0.3 dB steps and latches its clip LED at 0xFF00.
nonisolated enum OrpheusMeterScale {
    static let unsignedFullScale: UInt16 = 0xFFFF
    static let signedFullScale: UInt16 = 0x7FFF
    static let clipThreshold: UInt16 = 0xFF00
    static let floorDecibels = -48.0

    static func decibels(_ level: UInt16, fullScale: UInt16 = unsignedFullScale) -> Double? {
        guard level > 0 else { return nil }
        return 20 * log10(Double(min(level, fullScale)) / Double(fullScale))
    }

    static func fraction(_ level: UInt16, fullScale: UInt16 = unsignedFullScale) -> Double {
        guard let decibels = decibels(level, fullScale: fullScale) else { return 0 }
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }

    static func isClipping(_ level: UInt16, fullScale: UInt16 = unsignedFullScale) -> Bool {
        fullScale == unsignedFullScale && level >= clipThreshold
    }
}
