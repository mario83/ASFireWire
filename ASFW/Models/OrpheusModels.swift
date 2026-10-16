import Foundation

// MARK: - Prism Sound Orpheus Wire Constants
//
// Reconstructed from Orpheus.app 1.10 (Prism Sound control panel). All vendor
// commands are AV/C VENDOR-DEPENDENT frames addressed to the audio subunit,
// carrying the Prism Media Products company ID and a one-byte command code.

nonisolated enum OrpheusWire {
    static let companyID: [UInt8] = [0x00, 0x11, 0x98]

    static let ctypeControl: UInt8 = 0x00
    static let ctypeStatus: UInt8 = 0x01
    static let responseAccepted: UInt8 = 0x09
    static let responseStable: UInt8 = 0x0C

    static let subunitAudio: UInt8 = 0x08
    static let subunitUnit: UInt8 = 0xFF
    static let opcodeVendorDependent: UInt8 = 0x00
    static let opcodeSignalSource: UInt8 = 0x1A

    static let frameLength = 15
    static let mixBusFrameLength = 74
    static let commandOffset = 6
    static let payloadOffset = 7

    static let analogChannelCount = 8
    static let mixBusCount = 6
    static let mixInputCount = 12
    static let allMixBuses: UInt8 = 7

    static let meterAddressHigh: UInt16 = 0xFFC7
    static let meterAddressLow: UInt32 = 0x0060_0420
    static let meterCount = 50
    static let legacyMeterReadLength: UInt32 = 200
    static let meterReadLength: UInt32 = 204
}

nonisolated enum OrpheusCommand: UInt8 {
    case masterVolume = 0xA0
    case masterMute = 0xA1
    case volumeSelect = 0xA2
    case masterLock = 0xA3
    case frontPanelMeterMode = 0xB0
    case sampleRateConverter = 0xB1
    case clockOutput = 0xB2
    case adatMode = 0xB3
    case identify = 0xB4
    case firmwareVersion = 0xB6
    case meterBrightness = 0xB7
    case unitState = 0xBF

    case overkiller = 0xC1
    case phantom = 0xC2
    case filter = 0xC3
    case phase = 0xC4
    case midSide = 0xC5
    case lineInputLevel = 0xC6
    case micGain = 0xC7
    case instrumentGain = 0xC8
    case lineOutputLevel = 0xC9
    case headphoneSource = 0xCA
    case analogChannelState = 0xCF

    case digitalSampleRate = 0xD0
    case digitalBitDepth = 0xD2
    case digitalSync = 0xD3
    case digitalInputType = 0xD4
    case digitalChannelStatus = 0xD7
    case digitalState = 0xDF

    case mixDefeat = 0xE0
    case mixSolo = 0xE2
    case mixMute = 0xE3
    case mixGain = 0xE4
    case mixInputMute = 0xE5
    case mixInputGain = 0xE6
    case mixInputPan = 0xE7
    case mixInputBalance = 0xE8
    case mixBusState = 0xEF
}

// MARK: - Vendor Frame Codec

nonisolated enum OrpheusCodec {
    static func frame(ctype: UInt8,
                      command: OrpheusCommand,
                      operands: [UInt8] = [],
                      length: Int = OrpheusWire.frameLength) -> Data? {
        guard length <= 512, OrpheusWire.payloadOffset + operands.count <= length else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: length)
        bytes[0] = ctype
        bytes[1] = OrpheusWire.subunitAudio
        bytes[2] = OrpheusWire.opcodeVendorDependent
        bytes[3] = OrpheusWire.companyID[0]
        bytes[4] = OrpheusWire.companyID[1]
        bytes[5] = OrpheusWire.companyID[2]
        bytes[OrpheusWire.commandOffset] = command.rawValue
        for (index, byte) in operands.enumerated() {
            bytes[OrpheusWire.payloadOffset + index] = byte
        }
        return Data(bytes)
    }

    static func controlFrame(_ command: OrpheusCommand, operands: [UInt8]) -> Data? {
        frame(ctype: OrpheusWire.ctypeControl, command: command, operands: operands)
    }

    static func statusFrame(_ command: OrpheusCommand,
                            operands: [UInt8] = [],
                            length: Int = OrpheusWire.frameLength) -> Data? {
        frame(ctype: OrpheusWire.ctypeStatus, command: command, operands: operands, length: length)
    }

    /// Returns the response bytes (absolute offsets, same layout as the command)
    /// when the reply is ACCEPTED (CONTROL) or STABLE (STATUS) for `command`.
    static func validatedResponse(_ response: Data,
                                  command: OrpheusCommand,
                                  isControl: Bool,
                                  minimumLength: Int = OrpheusWire.payloadOffset) -> [UInt8]? {
        let bytes = [UInt8](response)
        guard bytes.count >= max(OrpheusWire.payloadOffset, minimumLength) else { return nil }

        let expected = isControl ? OrpheusWire.responseAccepted : OrpheusWire.responseStable
        guard bytes[0] == expected,
              Array(bytes[3...5]) == OrpheusWire.companyID,
              bytes[OrpheusWire.commandOffset] == command.rawValue
        else {
            return nil
        }
        return bytes
    }

    static func int16BE(_ high: UInt8, _ low: UInt8) -> Int16 {
        Int16(bitPattern: (UInt16(high) << 8) | UInt16(low))
    }

    static func uint16BE(_ high: UInt8, _ low: UInt8) -> UInt16 {
        (UInt16(high) << 8) | UInt16(low)
    }

    static func bytesBE(_ value: Int16) -> [UInt8] {
        let raw = UInt16(bitPattern: value)
        return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
    }

    static func bytesBE(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }
}

// MARK: - CONTROL Frame Builders

nonisolated enum OrpheusControl {
    static func masterVolume(_ value: Int16) -> Data? {
        OrpheusCodec.controlFrame(.masterVolume, operands: OrpheusCodec.bytesBE(value))
    }

    /// The vendor app sends the selection mask low byte first.
    static func volumeSelect(mask: UInt16) -> Data? {
        OrpheusCodec.controlFrame(.volumeSelect, operands: [UInt8(mask & 0xFF), UInt8(mask >> 8)])
    }

    static func flag(_ command: OrpheusCommand, _ enabled: Bool) -> Data? {
        OrpheusCodec.controlFrame(command, operands: [enabled ? 1 : 0])
    }

    static func value(_ command: OrpheusCommand, _ value: UInt8) -> Data? {
        OrpheusCodec.controlFrame(command, operands: [value])
    }

    static func analog(_ command: OrpheusCommand, channel: Int, value: UInt8) -> Data? {
        guard (0..<OrpheusWire.analogChannelCount).contains(channel) else { return nil }
        return OrpheusCodec.controlFrame(command, operands: [UInt8(channel), value])
    }

    static func mixBusGain(bus: Int, gain: Int16) -> Data? {
        guard isValidBus(bus) else { return nil }
        return OrpheusCodec.controlFrame(.mixGain, operands: [UInt8(bus)] + OrpheusCodec.bytesBE(gain))
    }

    static func mixBusMute(bus: Int, muted: Bool) -> Data? {
        guard isValidBus(bus) else { return nil }
        return OrpheusCodec.controlFrame(.mixMute, operands: [UInt8(bus), muted ? 1 : 0])
    }

    static func mixBusSolo(bus: Int, mask: UInt16) -> Data? {
        guard isValidBus(bus) else { return nil }
        return OrpheusCodec.controlFrame(.mixSolo, operands: [UInt8(bus)] + OrpheusCodec.bytesBE(mask))
    }

    static func mixBusDefeat(bus: Int, defeated: Bool) -> Data? {
        guard isValidBus(bus) else { return nil }
        return OrpheusCodec.controlFrame(.mixDefeat, operands: [UInt8(bus), defeated ? 1 : 0])
    }

    static func mixInputGain(bus: Int, input: Int, gain: Int16) -> Data? {
        guard isValidBus(bus), isValidInput(input) else { return nil }
        return OrpheusCodec.controlFrame(.mixInputGain,
                                         operands: [UInt8(bus), UInt8(input)] + OrpheusCodec.bytesBE(gain))
    }

    static func mixInputMute(bus: Int, input: Int, muted: Bool) -> Data? {
        guard isValidBus(bus), isValidInput(input) else { return nil }
        return OrpheusCodec.controlFrame(.mixInputMute, operands: [UInt8(bus), UInt8(input), muted ? 1 : 0])
    }

    /// Pan for a mono input, or balance (`0xE8`) for the even input of a linked pair.
    static func mixInputPosition(bus: Int, input: Int, position: Int8, balance: Bool) -> Data? {
        guard isValidBus(bus), isValidInput(input) else { return nil }
        let command: OrpheusCommand = balance ? .mixInputBalance : .mixInputPan
        return OrpheusCodec.controlFrame(command,
                                         operands: [UInt8(bus), UInt8(input), UInt8(bitPattern: position)])
    }

    private static func isValidBus(_ bus: Int) -> Bool {
        (0..<OrpheusWire.mixBusCount).contains(bus)
    }

    private static func isValidInput(_ input: Int) -> Bool {
        (0..<OrpheusWire.mixInputCount).contains(input)
    }
}

// MARK: - STATUS Frame Builders

nonisolated enum OrpheusStatus {
    static func firmwareVersion() -> Data? { OrpheusCodec.statusFrame(.firmwareVersion) }
    static func unitState() -> Data? { OrpheusCodec.statusFrame(.unitState) }
    static func digitalState() -> Data? { OrpheusCodec.statusFrame(.digitalState) }

    static func analogChannel(_ channel: Int) -> Data? {
        guard (0..<OrpheusWire.analogChannelCount).contains(channel) else { return nil }
        return OrpheusCodec.statusFrame(.analogChannelState, operands: [UInt8(channel)])
    }

    static func mixDefeats() -> Data? {
        OrpheusCodec.statusFrame(.mixDefeat, operands: [OrpheusWire.allMixBuses])
    }

    static func mixBus(_ bus: Int) -> Data? {
        guard (0..<OrpheusWire.mixBusCount).contains(bus) else { return nil }
        return OrpheusCodec.statusFrame(.mixBusState,
                                        operands: [UInt8(bus)],
                                        length: OrpheusWire.mixBusFrameLength)
    }
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

    static func format(_ raw: Int16, fractionDigits: Int = 2) -> String {
        guard let decibels = decibels(raw) else { return "-∞ dB" }
        return String(format: "%.\(fractionDigits)f dB", decibels)
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
    var id: UInt8 { value }
}

nonisolated enum OrpheusChoices {
    static let frontPanelMeter = [
        OrpheusChoice(value: 0, label: "Input"),
        OrpheusChoice(value: 1, label: "Output"),
    ]

    static let sampleRateConverter = [
        OrpheusChoice(value: 0, label: "Off"),
        OrpheusChoice(value: 1, label: "Digital input"),
        OrpheusChoice(value: 2, label: "Digital output"),
    ]

    static let clockOutput = [
        OrpheusChoice(value: 0, label: "fs (word clock)"),
        OrpheusChoice(value: 1, label: "Base clock"),
        OrpheusChoice(value: 2, label: "256× clock"),
    ]

    static func adatModes(firmware: OrpheusFirmwareVersion?) -> [OrpheusChoice] {
        var choices = [
            OrpheusChoice(value: 0, label: "None"),
            OrpheusChoice(value: 1, label: "Send"),
            OrpheusChoice(value: 2, label: "Return"),
            OrpheusChoice(value: 3, label: "Send/Return"),
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
            OrpheusChoice(value: 1, label: "80 Hz"),
        ]
        if channel < 2 {
            choices.append(OrpheusChoice(value: 2, label: "RIAA"))
        }
        return choices
    }

    static let digitalSampleRate = [
        OrpheusChoice(value: 1, label: "44.1 kHz"),
        OrpheusChoice(value: 2, label: "48 kHz"),
        OrpheusChoice(value: 3, label: "88.2 kHz"),
        OrpheusChoice(value: 4, label: "96 kHz"),
        OrpheusChoice(value: 5, label: "176.4 kHz"),
        OrpheusChoice(value: 6, label: "192 kHz"),
    ]

    static let digitalBitDepth = [
        OrpheusChoice(value: 24, label: "24 bit"),
        OrpheusChoice(value: 16, label: "16 bit"),
        OrpheusChoice(value: 0, label: "16 bit SNS1"),
        OrpheusChoice(value: 1, label: "16 bit SNS2"),
        OrpheusChoice(value: 2, label: "16 bit SNS3"),
        OrpheusChoice(value: 3, label: "16 bit SNS4"),
    ]

    static let digitalSync = [
        OrpheusChoice(value: 0, label: "Local"),
        OrpheusChoice(value: 1, label: "Word clock"),
        OrpheusChoice(value: 2, label: "Digital input"),
    ]

    static let digitalInputType = [
        OrpheusChoice(value: 0, label: "S/PDIF (coaxial)"),
        OrpheusChoice(value: 1, label: "TOSLINK (optical)"),
    ]

    static let digitalChannelStatus = [
        OrpheusChoice(value: 0, label: "S/PDIF (consumer)"),
        OrpheusChoice(value: 1, label: "AES3 (professional)"),
    ]

    /// Ensures a picker can always display the value reported by the device.
    static func including(_ current: UInt8?, in choices: [OrpheusChoice]) -> [OrpheusChoice] {
        guard let current, !choices.contains(where: { $0.value == current }) else { return choices }
        return choices + [OrpheusChoice(value: current, label: "Unknown (\(current))")]
    }

    static func brightnessLabel(_ value: UInt8) -> String {
        switch value {
        case 9...: return "Max"
        case 5...8: return "High"
        case 2...4: return "Low"
        default: return "Min"
        }
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

    init?(statusResponse bytes: [UInt8]) {
        guard bytes.count >= 9 else { return nil }
        self.init(major: bytes[7], minor: bytes[8])
    }

    /// Firmware 1.3+ appends a status quadlet to the meter block and drops NOTIFY.
    var hasMeterStatusQuadlet: Bool {
        major >= 2 || (major == 1 && minor >= 3)
    }

    var supportsAdatDirect: Bool {
        major != 0 && (major != 1 || minor > 1)
    }

    var meterReadLength: UInt32 {
        hasMeterStatusQuadlet ? OrpheusWire.meterReadLength : OrpheusWire.legacyMeterReadLength
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

    init() {}

    init?(statusResponse bytes: [UInt8]) {
        guard bytes.count >= 15 else { return nil }
        masterVolume = OrpheusCodec.int16BE(bytes[7], bytes[8])
        volumeSelectMask = OrpheusCodec.uint16BE(bytes[9], bytes[10])
        masterMute = bytes[11] & 0x01 != 0
        masterLock = bytes[11] & 0x02 != 0
        identify = bytes[11] & 0x04 != 0
        frontPanelMeterMode = bytes[11] >> 4
        sampleRateConverter = bytes[12] & 0x0F
        clockOutput = bytes[12] >> 4
        adatMode = bytes[13]
        headphoneSource = bytes[14] & 0x0F
        meterBrightness = bytes[14] >> 4
    }

    var hasAdatInput: Bool { OrpheusUnitState.adatModeHasInput(adatMode) }

    /// The digital output sample rate and sync are only selectable when the SRC
    /// sits on the digital output.
    var digitalOutputClockIsIndependent: Bool { sampleRateConverter == 2 }

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

    init() {}

    init?(statusResponse bytes: [UInt8], channel: Int) {
        guard bytes.count >= 13 else { return nil }
        let flags = bytes[9]
        inputType = bytes[8]
        lineInputLevel = flags & 0x01
        lineOutputLevel = (flags >> 1) & 0x01
        overkiller = flags & 0x04 != 0
        midSide = flags & 0x08 != 0
        phantom = flags & 0x20 != 0
        phase = flags & 0x40 != 0
        if channel < 4 {
            filter = bytes[10]
            micGain = bytes[11]
        }
        if channel < 2 {
            instrumentGain = bytes[12]
        }
    }

    var type: OrpheusAnalogInputType? { OrpheusAnalogInputType(rawValue: inputType) }

    static func hasPreamp(channel: Int) -> Bool { channel < 4 }
    static func hasInstrumentInput(channel: Int) -> Bool { channel < 2 }
}

/// Mid-side decoding exists for AI 1/2 and AI 3/4; the command channel is the
/// pair index and the state lives in that channel's `midSide` flag.
nonisolated enum OrpheusMidSide {
    static let pairCount = 2

    static func pairLabel(_ pair: Int) -> String { "AI \(pair * 2 + 1)/\(pair * 2 + 2)" }

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

    init() {}

    init?(statusResponse bytes: [UInt8]) {
        guard bytes.count >= 13 else { return nil }
        inputType = bytes[7]
        channelStatus = bytes[8]
        bitDepth = bytes[9]
        sampleRate = bytes[10]
        syncSource = bytes[11]
        unlocked = bytes[12] & 0x01 != 0
        asynchronous = bytes[12] & 0x02 != 0
    }
}

// MARK: - Mixer (0xEF / 0xE0)

nonisolated enum OrpheusMix {
    static let busNames = ["AO 1/2", "AO 3/4", "AO 5/6", "AO 7/8", "DO 1/2", "Headphones"]
    static let inputNames = ["AI 1", "AI 2", "AI 3", "AI 4", "AI 5", "AI 6", "AI 7", "AI 8",
                             "DI 1", "DI 2", "DAW 1", "DAW 2"]
    static let positionRange: ClosedRange<Int8> = -20...20
    /// Even inputs that can be stereo-linked with the next one.
    static let linkablePairs = [0, 2, 4, 6, 8, 10]

    static func isLinkable(input: Int) -> Bool {
        linkablePairs.contains(input & ~1)
    }

    static func partner(of input: Int) -> Int { input ^ 1 }

    static func parseDefeats(statusResponse bytes: [UInt8]) -> [Bool]? {
        guard bytes.count >= 8 + OrpheusWire.mixBusCount else { return nil }
        return (0..<OrpheusWire.mixBusCount).map { bytes[8 + $0] != 0 }
    }

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

    init() {}

    init?(statusResponse bytes: [UInt8], bus: Int) {
        guard bytes.count >= OrpheusWire.mixBusFrameLength, Int(bytes[7]) == bus else { return nil }
        gain = OrpheusCodec.int16BE(bytes[8], bytes[9])
        mute = bytes[10] != 0
        soloMask = OrpheusCodec.uint16BE(bytes[11], bytes[12])
        defeated = bytes[13] != 0
        inputs = (0..<OrpheusWire.mixInputCount).map { index in
            let base = 14 + index * 5
            return OrpheusMixInputState(gain: OrpheusCodec.int16BE(bytes[base], bytes[base + 1]),
                                        mute: bytes[base + 2] != 0,
                                        linked: bytes[base + 3] != 0 && bytes[base + 3] != OrpheusCommand.mixInputPan.rawValue,
                                        position: Int8(bitPattern: bytes[base + 4]))
        }
    }

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

nonisolated enum OrpheusSignalSourceCodec {
    private static let destinationSubunitPlug: UInt8 = 0x60

    private static func destinationPlug(hasAdatInput: Bool) -> UInt8 {
        0x07 + (hasAdatInput ? 1 : 0)
    }

    static func statusFrame(hasAdatInput: Bool) -> Data {
        Data([OrpheusWire.ctypeStatus, OrpheusWire.subunitUnit, OrpheusWire.opcodeSignalSource, 0x0F,
              0xFF, 0xFF, destinationSubunitPlug, destinationPlug(hasAdatInput: hasAdatInput)])
    }

    static func controlFrame(source: OrpheusSyncSource, hasAdatInput: Bool) -> Data? {
        guard let plug = sourcePlug(source, hasAdatInput: hasAdatInput) else { return nil }
        return Data([OrpheusWire.ctypeControl, OrpheusWire.subunitUnit, OrpheusWire.opcodeSignalSource, 0x0F,
                     plug.subunit, plug.plug, destinationSubunitPlug, destinationPlug(hasAdatInput: hasAdatInput)])
    }

    static func sourcePlug(_ source: OrpheusSyncSource, hasAdatInput: Bool) -> (subunit: UInt8, plug: UInt8)? {
        let adat: UInt8 = hasAdatInput ? 1 : 0
        switch source {
        case .csp: return (0x60, 0x08 + adat)
        case .firewire: return (0xFF, 0x00)
        case .local: return (0xFF, 0x87 + adat)
        case .digitalInput: return (0xFF, 0x85)
        case .adat: return hasAdatInput ? (0xFF, 0x86) : nil
        case .wordClock: return (0xFF, 0x86 | adat)
        }
    }

    static func parseStatus(_ response: Data, hasAdatInput: Bool) -> OrpheusSyncSource? {
        let bytes = [UInt8](response)
        guard bytes.count >= 6, bytes[0] == OrpheusWire.responseStable else { return nil }
        if bytes[4] == 0x60 { return .csp }
        guard bytes[4] == 0xFF else { return nil }

        switch (bytes[5], hasAdatInput) {
        case (0x00, _): return .firewire
        case (0x85, _): return .digitalInput
        case (0x86, false): return .wordClock
        case (0x87, false): return .local
        case (0x86, true): return .adat
        case (0x87, true): return .wordClock
        case (0x88, true): return .local
        default: return nil
        }
    }

    static func isAccepted(_ response: Data) -> Bool {
        response.first == OrpheusWire.responseAccepted
    }
}

// MARK: - Meters (block read at 0xFFC7_0060_0420)

nonisolated struct OrpheusMeterSnapshot: Equatable {
    var levels: [UInt16]
    var masterVolume: Int16?
    var analogInputTypes: [UInt8]?
    var digitalAsynchronous: Bool?
    var digitalUnlocked: Bool?

    /// Legacy firmware's decaying meters are signed, so their full scale is 0x7FFF.
    var legacyDecay = false

    static let analogMeterCount = 8
    /// Legacy firmware publishes meters from this index in the quadlet's upper half.
    static let legacyDecayStartIndex = 22

    init(levels: [UInt16],
         masterVolume: Int16? = nil,
         analogInputTypes: [UInt8]? = nil,
         digitalAsynchronous: Bool? = nil,
         digitalUnlocked: Bool? = nil) {
        self.levels = levels
        self.masterVolume = masterVolume
        self.analogInputTypes = analogInputTypes
        self.digitalAsynchronous = digitalAsynchronous
        self.digitalUnlocked = digitalUnlocked
    }

    init?(data: Data, hasStatusQuadlet: Bool) {
        let bytes = [UInt8](data)
        let meterBytes = OrpheusWire.meterCount * 4
        guard bytes.count >= meterBytes else { return nil }
        legacyDecay = !hasStatusQuadlet

        levels = (0..<OrpheusWire.meterCount).map { index in
            let base = index * 4
            if !hasStatusQuadlet && index >= Self.legacyDecayStartIndex {
                return OrpheusCodec.uint16BE(bytes[base], bytes[base + 1])
            }
            return OrpheusCodec.uint16BE(bytes[base + 2], bytes[base + 3])
        }

        guard hasStatusQuadlet, bytes.count >= meterBytes + 4, bytes[meterBytes + 3] != 0 else { return }
        masterVolume = OrpheusCodec.int16BE(bytes[meterBytes], bytes[meterBytes + 1])
        let types = bytes[meterBytes + 2]
        analogInputTypes = (0..<4).map { (types >> ($0 * 2)) & 0x03 }
        digitalAsynchronous = bytes[meterBytes + 3] & 0x02 != 0
        digitalUnlocked = bytes[meterBytes + 3] & 0x04 != 0
    }

    func fullScale(at index: Int) -> UInt16 {
        legacyDecay && index >= Self.legacyDecayStartIndex ? OrpheusMeterScale.signedFullScale : OrpheusMeterScale.unsignedFullScale
    }

    /// Indices 0-7, 10-11, 20-23 are confirmed on hardware; the rest follow the
    /// 50-entry layout (8 AI, 2 DI, 8 AO, 2 DO, 2 HP, 12 DAW, 8 + 8 ADAT).
    private static let labelGroups: [(prefix: String, count: Int)] = [
        ("AI", 8), ("DI", 2), ("AO", 8), ("DO", 2), ("HP", 2), ("DAW", 12), ("ADI", 8), ("ADO", 8),
    ]

    static func label(for index: Int) -> String {
        var start = 0
        for group in labelGroups {
            if index < start + group.count {
                let number = index - start
                if group.prefix == "HP" { return number == 0 ? "HP L" : "HP R" }
                return "\(group.prefix) \(number + 1)"
            }
            start += group.count
        }
        return "#\(index + 1)"
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

    static func format(_ level: UInt16, fullScale: UInt16 = unsignedFullScale) -> String {
        guard let decibels = decibels(level, fullScale: fullScale) else { return "-∞" }
        return String(format: "%.1f", decibels)
    }
}

// MARK: - Full Snapshot

nonisolated struct OrpheusStateSnapshot: Equatable {
    var firmware: OrpheusFirmwareVersion?
    var unit: OrpheusUnitState?
    var analog: [OrpheusAnalogChannelState?] = Array(repeating: nil, count: OrpheusWire.analogChannelCount)
    var digital: OrpheusDigitalState?
    var mixBuses: [OrpheusMixBusState?] = Array(repeating: nil, count: OrpheusWire.mixBusCount)
    var mixDefeats: [Bool]?
    var syncSource: OrpheusSyncSource?
    var updatedAt = Date()

    var failedReads: [String] {
        var failed: [String] = []
        if firmware == nil { failed.append("firmware") }
        if unit == nil { failed.append("unit") }
        for (index, channel) in analog.enumerated() where channel == nil { failed.append("AI\(index + 1)") }
        if digital == nil { failed.append("digital") }
        for (index, bus) in mixBuses.enumerated() where bus == nil { failed.append("mix \(OrpheusMix.busNames[index])") }
        if mixDefeats == nil { failed.append("mix defeats") }
        if syncSource == nil { failed.append("sync") }
        return failed
    }

    var hasAnyState: Bool { unit != nil || digital != nil || analog.contains { $0 != nil } }
}
