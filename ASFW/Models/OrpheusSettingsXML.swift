import Foundation

/// Prism Orpheus.app 1.10 unit settings file (`Device::Save` / `Device::Load`).
enum OrpheusSettingsXML {
    struct Snapshot: Equatable {
        var unit: OrpheusUnitState
        var analog: [OrpheusAnalogChannelState]
        var digital: OrpheusDigitalState
        var mixBuses: [OrpheusMixBusState]
        var syncSource: OrpheusSyncSource?
    }

    enum ParseError: Swift.Error, LocalizedError {
        case invalidDocument

        var errorDescription: String? {
            "Not a Prism Orpheus settings file."
        }
    }

    static func encode(_ snapshot: Snapshot) throws -> Data {
        let root = XMLElement(name: "Orpheus")
        root.addChild(unitElement(snapshot))
        for channel in 0..<OrpheusWire.analogChannelCount {
            root.addChild(analogElement(channel: channel, state: snapshot.analog[channel]))
        }
        root.addChild(digitalElement(snapshot.digital))
        root.addChild(volumeElement(snapshot.unit))
        root.addChild(intElement("HP", Int(snapshot.unit.headphoneSource)))
        for bus in 0..<OrpheusWire.mixBusCount {
            root.addChild(mixBusElement(bus: bus, state: snapshot.mixBuses[bus]))
        }

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        return document.xmlData(options: .nodePrettyPrint)
    }

    static func decode(_ data: Data, base: Snapshot) throws -> Snapshot {
        let document = try XMLDocument(data: data, options: [.documentTidyXML])
        guard let root = document.rootElement(), root.name == "Orpheus" else {
            throw ParseError.invalidDocument
        }
        var snapshot = base
        for child in elements(root) {
            switch child.name {
            case "Unit": applyUnit(child, to: &snapshot)
            case "Analog": applyAnalog(child, to: &snapshot)
            case "digital": applyDigital(child, to: &snapshot)
            case "volume": applyVolume(child, to: &snapshot)
            case "HP":
                if let value = intValue(child) {
                    snapshot.unit.headphoneSource = UInt8(clamping: value)
                }
            case "mix": applyMixBus(child, to: &snapshot)
            default: break
            }
        }
        return snapshot
    }

    static let manualURL = URL(string: "https://www.prismsound.com/music_recording/products_subs/orpheus/online_manual/index.html")!
}

private extension OrpheusSettingsXML {
    static func unitElement(_ snapshot: Snapshot) -> XMLElement {
        let unit = XMLElement(name: "Unit")
        unit.addChild(intElement("adat", Int(snapshot.unit.adatMode)))
        unit.addChild(intElement("sync", Int(snapshot.syncSource?.rawValue ?? OrpheusSyncSource.local.rawValue)))
        unit.addChild(intElement("src", Int(snapshot.unit.sampleRateConverter)))
        unit.addChild(intElement("wck", Int(snapshot.unit.clockOutput)))
        unit.addChild(intElement("fp", Int(snapshot.unit.frontPanelMeterMode)))
        if snapshot.unit.identify { unit.addChild(XMLElement(name: "id")) }
        return unit
    }

    static func analogElement(channel: Int, state: OrpheusAnalogChannelState) -> XMLElement {
        let analog = XMLElement(name: "Analog")
        analog.addAttribute(XMLNode.attribute(withName: "i", stringValue: String(channel)) as! XMLNode)
        if channel < 4 {
            analog.addChild(intElement("m", Int(state.micGain)))
            if state.phantom { analog.addChild(XMLElement(name: "P")) }
            if state.overkiller { analog.addChild(XMLElement(name: "O")) }
            analog.addChild(intElement("f", Int(state.filter)))
            if state.phase { analog.addChild(XMLElement(name: "p")) }
            if channel < 2 {
                analog.addChild(intElement("i", Int(state.instrumentGain)))
                if state.midSide { analog.addChild(XMLElement(name: "ms")) }
            }
        }
        analog.addChild(intElement("l", Int(state.lineInputLevel)))
        analog.addChild(intElement("g", Int(state.lineOutputLevel)))
        if channel >= 4, state.overkiller { analog.addChild(XMLElement(name: "O")) }
        return analog
    }

    static func digitalElement(_ state: OrpheusDigitalState) -> XMLElement {
        let digital = XMLElement(name: "digital")
        digital.addChild(intElement("fs", Int(state.sampleRate)))
        digital.addChild(intElement("bits", Int(state.bitDepth)))
        digital.addChild(intElement("sync", Int(state.syncSource)))
        digital.addChild(intElement("type", Int(state.inputType)))
        digital.addChild(intElement("cs", Int(state.channelStatus)))
        return digital
    }

    static func volumeElement(_ unit: OrpheusUnitState) -> XMLElement {
        let volume = XMLElement(name: "volume")
        volume.addChild(intElement("v", Int(unit.masterVolume)))
        volume.addChild(intElement("E", Int(unit.volumeSelectMask)))
        if unit.masterMute { volume.addChild(XMLElement(name: "m")) }
        if unit.masterLock { volume.addChild(XMLElement(name: "L")) }
        return volume
    }

    static func mixBusElement(bus: Int, state: OrpheusMixBusState) -> XMLElement {
        let mix = XMLElement(name: "mix")
        mix.addAttribute(XMLNode.attribute(withName: "o", stringValue: String(bus)) as! XMLNode)
        mix.addChild(intElement("g", Int(state.gain)))
        mix.addChild(intElement("s", Int(state.soloMask)))
        if state.mute { mix.addChild(XMLElement(name: "m")) }
        if state.defeated { mix.addChild(XMLElement(name: "d")) }
        for input in 0..<OrpheusWire.mixInputCount {
            mix.addChild(mixInputElement(input: input, state: state.inputs[input]))
        }
        return mix
    }

    static func mixInputElement(input: Int, state: OrpheusMixInputState) -> XMLElement {
        let mix = XMLElement(name: "mix")
        mix.addAttribute(XMLNode.attribute(withName: "i", stringValue: String(input)) as! XMLNode)
        mix.addChild(intElement("g", Int(state.gain)))
        if state.mute { mix.addChild(XMLElement(name: "m")) }
        mix.addChild(intElement(state.linked ? "b" : "p", Int(state.position)))
        mix.addChild(intElement("S", state.linked ? 1 : 0))
        return mix
    }

    static func applyUnit(_ element: XMLElement, to snapshot: inout Snapshot) {
        snapshot.unit.identify = !element.elements(forName: "id").isEmpty
        for child in elements(element) {
            switch child.name {
            case "adat": snapshot.unit.adatMode = uint8Value(child) ?? snapshot.unit.adatMode
            case "sync":
                if let value = uint8Value(child) {
                    snapshot.syncSource = OrpheusSyncSource(rawValue: value)
                }
            case "src": snapshot.unit.sampleRateConverter = uint8Value(child) ?? snapshot.unit.sampleRateConverter
            case "wck": snapshot.unit.clockOutput = uint8Value(child) ?? snapshot.unit.clockOutput
            case "fp": snapshot.unit.frontPanelMeterMode = uint8Value(child) ?? snapshot.unit.frontPanelMeterMode
            default: break
            }
        }
    }

    static func applyAnalog(_ element: XMLElement, to snapshot: inout Snapshot) {
        guard let channel = intValue(element.attribute(forName: "i")),
              (0..<OrpheusWire.analogChannelCount).contains(channel) else { return }
        var state = snapshot.analog[channel]
        if channel < 4 {
            state.phantom = false
            state.phase = false
            if channel < 2 { state.midSide = false }
        }
        state.overkiller = false
        for child in elements(element) {
            switch child.name {
            case "m": state.micGain = uint8Value(child) ?? state.micGain
            case "i": state.instrumentGain = uint8Value(child) ?? state.instrumentGain
            case "f": state.filter = uint8Value(child) ?? state.filter
            case "l": state.lineInputLevel = uint8Value(child) ?? state.lineInputLevel
            case "g": state.lineOutputLevel = uint8Value(child) ?? state.lineOutputLevel
            case "P": state.phantom = true
            case "O": state.overkiller = true
            case "p": state.phase = true
            case "ms": state.midSide = true
            default: break
            }
        }
        snapshot.analog[channel] = state
    }

    static func applyDigital(_ element: XMLElement, to snapshot: inout Snapshot) {
        for child in elements(element) {
            switch child.name {
            case "fs": snapshot.digital.sampleRate = uint8Value(child) ?? snapshot.digital.sampleRate
            case "bits": snapshot.digital.bitDepth = uint8Value(child) ?? snapshot.digital.bitDepth
            case "sync": snapshot.digital.syncSource = uint8Value(child) ?? snapshot.digital.syncSource
            case "type": snapshot.digital.inputType = uint8Value(child) ?? snapshot.digital.inputType
            case "cs": snapshot.digital.channelStatus = uint8Value(child) ?? snapshot.digital.channelStatus
            default: break
            }
        }
    }

    static func applyVolume(_ element: XMLElement, to snapshot: inout Snapshot) {
        snapshot.unit.masterMute = false
        snapshot.unit.masterLock = false
        for child in elements(element) {
            switch child.name {
            case "v":
                if let value = intValue(child) { snapshot.unit.masterVolume = Int16(clamping: value) }
            case "E":
                if let value = intValue(child) { snapshot.unit.volumeSelectMask = UInt16(clamping: value) }
            case "m": snapshot.unit.masterMute = true
            case "L": snapshot.unit.masterLock = true
            default: break
            }
        }
    }

    static func applyMixBus(_ element: XMLElement, to snapshot: inout Snapshot) {
        guard let bus = intValue(element.attribute(forName: "o")),
              (0..<OrpheusWire.mixBusCount).contains(bus) else { return }
        var state = snapshot.mixBuses[bus]
        state.mute = false
        state.defeated = false
        for child in elements(element) {
            switch child.name {
            case "g":
                if let value = intValue(child) { state.gain = Int16(clamping: value) }
            case "s":
                if let value = intValue(child) { state.soloMask = UInt16(clamping: value) }
            case "m": state.mute = true
            case "d": state.defeated = true
            case "mix": applyMixInput(child, to: &state)
            default: break
            }
        }
        snapshot.mixBuses[bus] = state
    }

    static func applyMixInput(_ element: XMLElement, to bus: inout OrpheusMixBusState) {
        guard let input = intValue(element.attribute(forName: "i")),
              (0..<OrpheusWire.mixInputCount).contains(input) else { return }
        var state = bus.inputs[input]
        state.mute = false
        state.linked = false
        for child in elements(element) {
            switch child.name {
            case "g":
                if let value = intValue(child) { state.gain = Int16(clamping: value) }
            case "m": state.mute = true
            case "S": state.linked = (intValue(child) ?? 0) != 0
            case "p", "b":
                if let value = intValue(child) { state.position = Int8(clamping: value) }
            default: break
            }
        }
        bus.inputs[input] = state
        if input % 2 == 0 {
            bus.inputs[input | 1].linked = state.linked
        }
    }

    static func intElement(_ name: String, _ value: Int) -> XMLElement {
        XMLElement(name: name, stringValue: String(value))
    }

    static func elements(_ element: XMLElement) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }
    }

    static func intValue(_ node: XMLNode?) -> Int? {
        guard let text = node?.stringValue, let value = Int(text) else { return nil }
        return value
    }

    static func uint8Value(_ node: XMLNode?) -> UInt8? {
        intValue(node).map { UInt8(clamping: $0) }
    }
}
