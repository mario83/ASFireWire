import Foundation
import Testing
@testable import ASFW

struct OrpheusCodecTests {
    private func response(_ ctype: UInt8, command: OrpheusCommand, payload: [UInt8], length: Int = 15) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        bytes[0] = ctype
        bytes[1] = 0x08
        bytes[3] = 0x00
        bytes[4] = 0x11
        bytes[5] = 0x98
        bytes[6] = command.rawValue
        for (index, byte) in payload.enumerated() { bytes[7 + index] = byte }
        return bytes
    }

    // MARK: - Frames

    @Test func statusFrameIsFifteenBytesWithPrismHeader() {
        let frame = OrpheusStatus.unitState()
        #expect(frame.map { [UInt8]($0) } == [0x01, 0x08, 0x00, 0x00, 0x11, 0x98, 0xBF,
                                              0, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func masterVolumeIsBigEndian() {
        let frame = [UInt8](OrpheusControl.masterVolume(-0x0A80)!)
        #expect(frame[0] == 0x00)
        #expect(frame[6] == 0xA0)
        #expect(Array(frame[7...8]) == [0xF5, 0x80])
        #expect(frame.count == 15)
    }

    @Test func volumeSelectSendsLowByteFirst() {
        let frame = [UInt8](OrpheusControl.volumeSelect(mask: 0x0301)!)
        #expect(Array(frame[6...8]) == [0xA2, 0x01, 0x03])
    }

    @Test func analogControlCarriesChannelThenValue() {
        let frame = [UInt8](OrpheusControl.analog(.micGain, channel: 3, value: 42)!)
        #expect(Array(frame[6...8]) == [0xC7, 0x03, 42])
        #expect(OrpheusControl.analog(.micGain, channel: 8, value: 42) == nil)
    }

    @Test func mixFramesUseBusInputAndBigEndianGain() {
        let gain = [UInt8](OrpheusControl.mixInputGain(bus: 5, input: 11, gain: -256)!)
        #expect(Array(gain[6...10]) == [0xE6, 0x05, 0x0B, 0xFF, 0x00])

        let solo = [UInt8](OrpheusControl.mixBusSolo(bus: 1, mask: 0x0201)!)
        #expect(Array(solo[6...9]) == [0xE2, 0x01, 0x02, 0x01])

        let balance = [UInt8](OrpheusControl.mixInputPosition(bus: 0, input: 2, position: -7, balance: true)!)
        #expect(Array(balance[6...9]) == [0xE8, 0x00, 0x02, 0xF9])

        let pan = [UInt8](OrpheusControl.mixInputPosition(bus: 0, input: 3, position: 20, balance: false)!)
        #expect(pan[6] == 0xE7)

        #expect(OrpheusControl.mixBusGain(bus: 6, gain: 0) == nil)
        #expect(OrpheusControl.mixInputMute(bus: 0, input: 12, muted: true) == nil)
    }

    @Test func mixBusStatusFrameIsSeventyFourBytes() {
        let frame = [UInt8](OrpheusStatus.mixBus(4)!)
        #expect(frame.count == 74)
        #expect(Array(frame[0...7]) == [0x01, 0x08, 0x00, 0x00, 0x11, 0x98, 0xEF, 0x04])
    }

    @Test func mixDefeatStatusAddressesAllBuses() {
        let frame = [UInt8](OrpheusStatus.mixDefeats()!)
        #expect(Array(frame[6...7]) == [0xE0, 0x07])
    }

    // MARK: - Response Validation

    @Test func validationRequiresCtypeCompanyAndCommand() {
        let ok = Data(response(0x0C, command: .unitState, payload: []))
        #expect(OrpheusCodec.validatedResponse(ok, command: .unitState, isControl: false) != nil)
        #expect(OrpheusCodec.validatedResponse(ok, command: .unitState, isControl: true) == nil)
        #expect(OrpheusCodec.validatedResponse(ok, command: .digitalState, isControl: false) == nil)

        var wrongCompany = response(0x0C, command: .unitState, payload: [])
        wrongCompany[5] = 0x99
        #expect(OrpheusCodec.validatedResponse(Data(wrongCompany), command: .unitState, isControl: false) == nil)

        let rejected = Data(response(0x0A, command: .identify, payload: [1]))
        #expect(OrpheusCodec.validatedResponse(rejected, command: .identify, isControl: true) == nil)

        let accepted = Data(response(0x09, command: .identify, payload: [1]))
        #expect(OrpheusCodec.validatedResponse(accepted, command: .identify, isControl: true) != nil)
    }

    // MARK: - State Parsing

    @Test func firmwareVersionThresholds() {
        let legacy = OrpheusFirmwareVersion(statusResponse: response(0x0C, command: .firmwareVersion, payload: [1, 2]))!
        #expect(legacy.description == "1.2")
        #expect(!legacy.hasMeterStatusQuadlet)
        #expect(legacy.meterReadLength == 200)
        #expect(legacy.supportsAdatDirect)

        let current = OrpheusFirmwareVersion(major: 1, minor: 3)
        #expect(current.hasMeterStatusQuadlet)
        #expect(current.meterReadLength == 204)
        #expect(OrpheusFirmwareVersion(major: 2, minor: 0).hasMeterStatusQuadlet)
        #expect(!OrpheusFirmwareVersion(major: 1, minor: 1).supportsAdatDirect)
        #expect(!OrpheusFirmwareVersion(major: 0, minor: 9).supportsAdatDirect)
    }

    @Test func unitStateParsesPackedFields() {
        let bytes = response(0x0C, command: .unitState,
                             payload: [0xF6, 0x00, 0x03, 0x0F, 0b0001_0111, 0x12, 0x03, 0x83])
        let state = OrpheusUnitState(statusResponse: bytes)!
        #expect(state.masterVolume == -0x0A00)
        #expect(state.volumeSelectMask == 0x030F)
        #expect(state.masterMute)
        #expect(state.masterLock)
        #expect(state.identify)
        #expect(state.frontPanelMeterMode == 1)
        #expect(state.sampleRateConverter == 2)
        #expect(state.clockOutput == 1)
        #expect(state.adatMode == 3)
        #expect(state.hasAdatInput)
        #expect(state.headphoneSource == 3)
        #expect(state.meterBrightness == 8)
        #expect(state.digitalOutputClockIsIndependent)
    }

    @Test func analogChannelParsesFlagsAndGatesPreampFields() {
        let flags: UInt8 = 0b0110_1101
        let preamp = OrpheusAnalogChannelState(statusResponse: response(0x0C, command: .analogChannelState,
                                                                        payload: [0, 1, flags, 2, 40, 30]),
                                               channel: 0)!
        #expect(preamp.type == .mic)
        #expect(preamp.lineInputLevel == 1)
        #expect(preamp.lineOutputLevel == 0)
        #expect(preamp.overkiller)
        #expect(preamp.midSide)
        #expect(preamp.phantom)
        #expect(preamp.phase)
        #expect(preamp.filter == 2)
        #expect(preamp.micGain == 40)
        #expect(preamp.instrumentGain == 30)

        let lineOnly = OrpheusAnalogChannelState(statusResponse: response(0x0C, command: .analogChannelState,
                                                                          payload: [5, 0, 0x02, 2, 40, 30]),
                                                 channel: 5)!
        #expect(lineOnly.type == .line)
        #expect(lineOnly.lineInputLevel == 0)
        #expect(lineOnly.lineOutputLevel == 1)
        #expect(lineOnly.filter == 0)
        #expect(lineOnly.micGain == 10)
        #expect(lineOnly.instrumentGain == 10)
    }

    @Test func digitalStateParsesStatusBits() {
        let state = OrpheusDigitalState(statusResponse: response(0x0C, command: .digitalState,
                                                                 payload: [1, 1, 2, 4, 2, 0x03]))!
        #expect(state.inputType == 1)
        #expect(state.channelStatus == 1)
        #expect(state.bitDepth == 2)
        #expect(state.sampleRate == 4)
        #expect(state.syncSource == 2)
        #expect(state.unlocked)
        #expect(state.asynchronous)
    }

    @Test func mixBusParsesInputBlocks() {
        var payload: [UInt8] = [2, 0xFE, 0x00, 1, 0x00, 0x04, 1]
        for input in 0..<12 {
            let linked: UInt8 = input == 2 ? OrpheusCommand.mixInputBalance.rawValue : OrpheusCommand.mixInputPan.rawValue
            payload += [0xFF, UInt8(input), input == 3 ? 1 : 0, linked, UInt8(bitPattern: Int8(input) - 6)]
        }
        let bytes = response(0x0C, command: .mixBusState, payload: payload, length: 74)
        let bus = OrpheusMixBusState(statusResponse: bytes, bus: 2)!
        #expect(bus.gain == -512)
        #expect(bus.mute)
        #expect(bus.soloMask == 0x0004)
        #expect(bus.soloedInput == 2)
        #expect(bus.defeated)
        #expect(bus.inputs[0].gain == Int16(bitPattern: 0xFF00))
        #expect(bus.inputs[3].mute)
        #expect(bus.inputs[2].linked)
        #expect(!bus.inputs[1].linked)
        #expect(bus.inputs[11].position == 5)

        #expect(OrpheusMixBusState(statusResponse: bytes, bus: 1) == nil)
        #expect(OrpheusMixBusState(statusResponse: Array(bytes.prefix(15)), bus: 2) == nil)
    }

    @Test func mixDefeatsParseSixBuses() {
        let bytes = response(0x0C, command: .mixDefeat, payload: [7, 0, 1, 0, 0, 1, 1])
        #expect(OrpheusMix.parseDefeats(statusResponse: bytes) == [false, true, false, false, true, true])
    }

    // MARK: - Mixer Logic

    @Test func linkAndUnlinkPositions() {
        #expect(OrpheusMix.balanceWhenLinking(leftPan: -20, rightPan: 20) == 0)
        #expect(OrpheusMix.balanceWhenLinking(leftPan: -10, rightPan: 20) == 5)
        let centered = OrpheusMix.pansWhenUnlinking(balance: 0)
        #expect(centered.left == -20 && centered.right == 20)
        let leftHeavy = OrpheusMix.pansWhenUnlinking(balance: -5)
        #expect(leftHeavy.left == -20 && leftHeavy.right == 10)
        let rightHeavy = OrpheusMix.pansWhenUnlinking(balance: 5)
        #expect(rightHeavy.left == -10 && rightHeavy.right == 20)
    }

    @Test func soloMaskIsExclusiveAndFollowsLink() {
        #expect(OrpheusMix.soloMask(input: 3, linked: false) == 0x0008)
        #expect(OrpheusMix.soloMask(input: 3, linked: true) == 0x000C)
        #expect(OrpheusMix.soloMask(input: nil, linked: true) == 0)
        #expect(OrpheusMix.isLinkable(input: 9))
        #expect(OrpheusMix.isLinkable(input: 11))
        #expect(!OrpheusMix.isLinkable(input: 12))
    }

    @Test func volumeSelectHeadphoneBitSetsPartner() {
        #expect(OrpheusVolumeSelect.setting(0, bit: 8, enabled: true) == 0x0300)
        #expect(OrpheusVolumeSelect.setting(0x0301, bit: 8, enabled: false) == 0x0001)
        #expect(OrpheusVolumeSelect.setting(0, bit: 2, enabled: true) == 0x0004)
    }

    @Test func headphoneRoutingRoundTrips() {
        #expect(OrpheusHeadphones.routing(source: 5, headphoneBusDefeated: false) == .mixer)
        #expect(OrpheusHeadphones.routing(source: 5, headphoneBusDefeated: true) == .daw)
        #expect(OrpheusHeadphones.routing(source: 2, headphoneBusDefeated: true) == .mirror(bus: 2))

        let daw = OrpheusHeadphones.settings(for: .daw)
        #expect(daw.source == 5)
        #expect(daw.defeat == true)
        let mirror = OrpheusHeadphones.settings(for: .mirror(bus: 4))
        #expect(mirror.source == 4)
        #expect(mirror.defeat == nil)
    }

    @Test func midSideNeedsLineOrMicOnBothChannels() {
        #expect(OrpheusMidSide.isAvailable(pair: 0, inputTypes: [0, 1, 2, 0]))
        #expect(!OrpheusMidSide.isAvailable(pair: 1, inputTypes: [0, 1, 2, 0]))
        #expect(!OrpheusMidSide.isAvailable(pair: 2, inputTypes: [0, 0, 0, 0, 0, 0]))
    }

    // MARK: - Sync Source

    @Test func signalSourceFramesDependOnAdatInput() {
        #expect([UInt8](OrpheusSignalSourceCodec.statusFrame(hasAdatInput: false))
                == [0x01, 0xFF, 0x1A, 0x0F, 0xFF, 0xFF, 0x60, 0x07])
        #expect([UInt8](OrpheusSignalSourceCodec.statusFrame(hasAdatInput: true)).last == 0x08)

        #expect([UInt8](OrpheusSignalSourceCodec.controlFrame(source: .local, hasAdatInput: false)!)
                == [0x00, 0xFF, 0x1A, 0x0F, 0xFF, 0x87, 0x60, 0x07])
        #expect([UInt8](OrpheusSignalSourceCodec.controlFrame(source: .csp, hasAdatInput: true)!)[4...5]
                == [0x60, 0x09])
        #expect([UInt8](OrpheusSignalSourceCodec.controlFrame(source: .wordClock, hasAdatInput: true)!)[5] == 0x87)
        #expect(OrpheusSignalSourceCodec.controlFrame(source: .adat, hasAdatInput: false) == nil)
    }

    @Test func signalSourceStatusParsing() {
        func parse(_ subunit: UInt8, _ plug: UInt8, adat: Bool) -> OrpheusSyncSource? {
            OrpheusSignalSourceCodec.parseStatus(Data([0x0C, 0xFF, 0x1A, 0x0F, subunit, plug, 0x60, 0x07]),
                                                 hasAdatInput: adat)
        }
        #expect(parse(0x60, 0x08, adat: false) == .csp)
        #expect(parse(0xFF, 0x00, adat: false) == .firewire)
        #expect(parse(0xFF, 0x85, adat: false) == .digitalInput)
        #expect(parse(0xFF, 0x86, adat: false) == .wordClock)
        #expect(parse(0xFF, 0x87, adat: false) == .local)
        #expect(parse(0xFF, 0x86, adat: true) == .adat)
        #expect(parse(0xFF, 0x87, adat: true) == .wordClock)
        #expect(parse(0xFF, 0x88, adat: true) == .local)
        #expect(OrpheusSignalSourceCodec.parseStatus(Data([0x0A, 0xFF, 0x1A, 0x0F, 0xFF, 0x87]), hasAdatInput: false) == nil)

        #expect(OrpheusSyncSource.selectable(current: .local, hasAdatInput: false) == [.csp, .local, .digitalInput, .wordClock])
        #expect(OrpheusSyncSource.selectable(current: .firewire, hasAdatInput: true).contains(.firewire))
    }

    // MARK: - Meters

    @Test func metersParseLevelsAndStatusQuadlet() {
        var bytes = [UInt8](repeating: 0, count: 204)
        for index in 0..<50 {
            bytes[index * 4] = 0xAA
            bytes[index * 4 + 2] = UInt8(index)
            bytes[index * 4 + 3] = 0x10
        }
        bytes[200] = 0xF6
        bytes[201] = 0x00
        bytes[202] = 0b00_10_01_00
        bytes[203] = 0x06

        let snapshot = OrpheusMeterSnapshot(data: Data(bytes), hasStatusQuadlet: true)!
        #expect(snapshot.levels.count == 50)
        #expect(snapshot.levels[0] == 0x0010)
        #expect(snapshot.levels[49] == 0x3110)
        #expect(snapshot.masterVolume == -0x0A00)
        #expect(snapshot.analogInputTypes == [0, 1, 2, 0])
        #expect(snapshot.digitalAsynchronous == true)
        #expect(snapshot.digitalUnlocked == true)

        bytes[203] = 0
        let quiet = OrpheusMeterSnapshot(data: Data(bytes), hasStatusQuadlet: true)!
        #expect(quiet.masterVolume == nil)
        #expect(quiet.analogInputTypes == nil)
    }

    @Test func legacyMetersUseUpperHalfFromIndex22() {
        var bytes = [UInt8](repeating: 0, count: 200)
        bytes[21 * 4 + 3] = 0x21
        bytes[22 * 4] = 0x12
        bytes[22 * 4 + 1] = 0x34
        bytes[22 * 4 + 3] = 0x99

        let snapshot = OrpheusMeterSnapshot(data: Data(bytes), hasStatusQuadlet: false)!
        #expect(snapshot.levels[21] == 0x0021)
        #expect(snapshot.levels[22] == 0x1234)
        #expect(snapshot.masterVolume == nil)
        #expect(OrpheusMeterSnapshot(data: Data(bytes.prefix(199)), hasStatusQuadlet: false) == nil)
    }

    // MARK: - Levels

    @Test func decibelConversionAndFormatting() {
        #expect(OrpheusLevel.decibels(.min) == nil)
        #expect(OrpheusLevel.decibels(-1536) == -6)
        #expect(OrpheusLevel.raw(decibels: -6.25) == -1600)
        #expect(OrpheusLevel.raw(decibels: nil) == .min)
        #expect(OrpheusLevel.raw(decibels: -500) == Int16.min + 1)
        #expect(OrpheusLevel.format(.min) == "-∞ dB")
        #expect(OrpheusLevel.format(-1600) == "-6.25 dB")

        let mapping = OrpheusDecibelMapping(floorDecibels: -96)
        #expect(mapping.raw(-96) == .min)
        #expect(mapping.sliderValue(.min) == -96)
        #expect(mapping.raw(-12) == -3072)
    }

    @Test func choiceListsKeepUnknownDeviceValues() {
        let choices = OrpheusChoices.including(9, in: OrpheusChoices.clockOutput)
        #expect(choices.count == 4)
        #expect(choices.last?.label == "Unknown (9)")
        #expect(OrpheusChoices.including(1, in: OrpheusChoices.clockOutput).count == 3)
        #expect(OrpheusChoices.filters(channel: 1).count == 3)
        #expect(OrpheusChoices.filters(channel: 2).count == 2)
        #expect(OrpheusChoices.adatModes(firmware: OrpheusFirmwareVersion(major: 1, minor: 1)).count == 4)
        #expect(OrpheusChoices.brightnessLabel(15) == "Max")
        #expect(OrpheusChoices.brightnessLabel(8) == "High")
        #expect(OrpheusChoices.brightnessLabel(4) == "Low")
        #expect(OrpheusChoices.brightnessLabel(1) == "Min")
    }

    // MARK: - Captured Orpheus responses (firmware 1.6)

    private func hex(_ text: String) -> Data {
        Data(text.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    @Test func capturedStatusResponsesParse() throws {
        let firmwareBytes = try #require(OrpheusCodec.validatedResponse(
            hex("0C 08 00 00 11 98 B6 01 06 00 1B 00 00 00 00"), command: .firmwareVersion, isControl: false))
        #expect(OrpheusFirmwareVersion(statusResponse: firmwareBytes) == OrpheusFirmwareVersion(major: 1, minor: 6))

        let unitBytes = try #require(OrpheusCodec.validatedResponse(
            hex("0C 08 00 00 11 98 BF D2 00 00 03 00 00 03 F0 00"), command: .unitState, isControl: false))
        let unit = try #require(OrpheusUnitState(statusResponse: unitBytes))
        #expect(unit.masterVolume == -46 * 256)
        #expect(unit.volumeSelectMask == 0x0003)
        #expect(!unit.masterMute && !unit.masterLock && !unit.identify)
        #expect(unit.adatMode == 3 && unit.hasAdatInput)
        #expect(unit.headphoneSource == 0)
        #expect(unit.meterBrightness == 15)

        let analogBytes = try #require(OrpheusCodec.validatedResponse(
            hex("0C 08 00 00 11 98 CF 00 01 07 00 0A 14 00 00 00"), command: .analogChannelState, isControl: false))
        let analog = try #require(OrpheusAnalogChannelState(statusResponse: analogBytes, channel: 0))
        #expect(analog.type == .mic)
        #expect(analog.lineInputLevel == 1 && analog.lineOutputLevel == 1)
        #expect(!analog.phantom)
        #expect(analog.micGain == 10 && analog.instrumentGain == 20)

        let digitalBytes = try #require(OrpheusCodec.validatedResponse(
            hex("0C 08 00 00 11 98 DF 00 00 18 02 00 00 00 00 00"), command: .digitalState, isControl: false))
        let digital = try #require(OrpheusDigitalState(statusResponse: digitalBytes))
        #expect(digital.bitDepth == 24 && digital.sampleRate == 2 && digital.syncSource == 0)
        #expect(!digital.unlocked && !digital.asynchronous)

        let defeatBytes = try #require(OrpheusCodec.validatedResponse(
            hex("0C 08 00 00 11 98 E0 07 00 00 00 00 01 00 00 00"), command: .mixDefeat, isControl: false))
        #expect(OrpheusMix.parseDefeats(statusResponse: defeatBytes) == [false, false, false, false, true, false])

        #expect(OrpheusSignalSourceCodec.parseStatus(hex("0C FF 1A 10 FF 88 60 08"), hasAdatInput: true) == .local)
    }

    @Test func capturedMixBusResponseLinksDawPair() throws {
        var bus = [UInt8](repeating: 0, count: 76)
        bus[0...6] = [0x0C, 0x08, 0x00, 0x00, 0x11, 0x98, 0xEF]
        bus[64...68] = [0xFB, 0xBF, 0x00, 0x01, 0x00]
        let bytes = try #require(OrpheusCodec.validatedResponse(
            Data(bus), command: .mixBusState, isControl: false, minimumLength: OrpheusWire.mixBusFrameLength))
        let state = try #require(OrpheusMixBusState(statusResponse: bytes, bus: 0))
        #expect(state.gain == 0 && !state.mute && !state.defeated)
        #expect(state.inputs[10].gain == -1089)
        #expect(state.inputs[10].linked)
        #expect(!state.inputs[0].linked)
    }
}
