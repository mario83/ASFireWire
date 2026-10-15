import Foundation

nonisolated struct OrpheusDeviceInfo: Equatable {
    let guid: UInt64
    let nodeID: UInt8?
    let generation: UInt32?
    let modelName: String

    var guidHex: String { String(format: "0x%016llX", guid) }
}

extension ASFWDriverConnector {
    static let orpheusVendorID: UInt32 = 0x001198

    private static let orpheusCommandTimeoutMs: UInt32 = 2_000
    private static let orpheusReadTimeout: TimeInterval = 0.5

    // MARK: - Device Selection

    static func isOrpheus(vendorID: UInt32, modelName: String?) -> Bool {
        vendorID == orpheusVendorID || (modelName?.lowercased().contains("orpheus") ?? false)
    }

    func findOrpheusDevice() -> OrpheusDeviceInfo? {
        let devices = getDiscoveredDevices() ?? []
        let unitGUID = getAVCUnits()?.first(where: { $0.vendorID == Self.orpheusVendorID })?.guid
        let device = devices.first(where: { $0.guid == unitGUID })
            ?? devices.first(where: { Self.isOrpheus(vendorID: $0.vendorId, modelName: $0.modelName) })

        guard let guid = unitGUID ?? device?.guid else { return nil }
        return OrpheusDeviceInfo(guid: guid,
                                 nodeID: device?.nodeId,
                                 generation: device?.generation,
                                 modelName: device?.modelName ?? "Orpheus")
    }

    // MARK: - STATUS Reads

    func getOrpheusFirmwareVersion(guid: UInt64) -> OrpheusFirmwareVersion? {
        orpheusStatus(guid: guid, command: .firmwareVersion, frame: OrpheusStatus.firmwareVersion())
            .flatMap(OrpheusFirmwareVersion.init(statusResponse:))
    }

    func getOrpheusUnitState(guid: UInt64) -> OrpheusUnitState? {
        orpheusStatus(guid: guid, command: .unitState, frame: OrpheusStatus.unitState())
            .flatMap(OrpheusUnitState.init(statusResponse:))
    }

    func getOrpheusAnalogChannel(guid: UInt64, channel: Int) -> OrpheusAnalogChannelState? {
        orpheusStatus(guid: guid, command: .analogChannelState, frame: OrpheusStatus.analogChannel(channel))
            .flatMap { OrpheusAnalogChannelState(statusResponse: $0, channel: channel) }
    }

    func getOrpheusDigitalState(guid: UInt64) -> OrpheusDigitalState? {
        orpheusStatus(guid: guid, command: .digitalState, frame: OrpheusStatus.digitalState())
            .flatMap(OrpheusDigitalState.init(statusResponse:))
    }

    func getOrpheusMixDefeats(guid: UInt64) -> [Bool]? {
        orpheusStatus(guid: guid, command: .mixDefeat, frame: OrpheusStatus.mixDefeats())
            .flatMap(OrpheusMix.parseDefeats(statusResponse:))
    }

    func getOrpheusMixBus(guid: UInt64, bus: Int) -> OrpheusMixBusState? {
        orpheusStatus(guid: guid,
                      command: .mixBusState,
                      frame: OrpheusStatus.mixBus(bus),
                      minimumLength: OrpheusWire.mixBusFrameLength)
            .flatMap { OrpheusMixBusState(statusResponse: $0, bus: bus) }
    }

    func getOrpheusSyncSource(guid: UInt64, hasAdatInput: Bool) -> OrpheusSyncSource? {
        let frame = OrpheusSignalSourceCodec.statusFrame(hasAdatInput: hasAdatInput)
        guard let response = sendRawFCPCommand(guid: guid, frame: frame, timeoutMs: Self.orpheusCommandTimeoutMs) else {
            return nil
        }
        return OrpheusSignalSourceCodec.parseStatus(response, hasAdatInput: hasAdatInput)
    }

    func refreshOrpheusState(guid: UInt64) -> OrpheusStateSnapshot {
        var snapshot = OrpheusStateSnapshot()
        snapshot.firmware = getOrpheusFirmwareVersion(guid: guid)
        snapshot.unit = getOrpheusUnitState(guid: guid)
        snapshot.analog = (0..<OrpheusWire.analogChannelCount).map { getOrpheusAnalogChannel(guid: guid, channel: $0) }
        snapshot.digital = getOrpheusDigitalState(guid: guid)
        snapshot.mixDefeats = getOrpheusMixDefeats(guid: guid)
        snapshot.mixBuses = (0..<OrpheusWire.mixBusCount).map { getOrpheusMixBus(guid: guid, bus: $0) }
        snapshot.syncSource = getOrpheusSyncSource(guid: guid, hasAdatInput: snapshot.unit?.hasAdatInput ?? false)
        snapshot.updatedAt = Date()
        return snapshot
    }

    // MARK: - CONTROL Writes

    /// Sends a prebuilt vendor CONTROL frame and reports whether it was ACCEPTED.
    func sendOrpheusControl(guid: UInt64, frame: Data?) -> Bool {
        guard let frame,
              frame.count > OrpheusWire.commandOffset,
              let command = OrpheusCommand(rawValue: frame[OrpheusWire.commandOffset]),
              let response = sendRawFCPCommand(guid: guid, frame: frame, timeoutMs: Self.orpheusCommandTimeoutMs)
        else {
            return false
        }
        let accepted = OrpheusCodec.validatedResponse(response, command: command, isControl: true) != nil
        if !accepted {
            log(String(format: "Orpheus CONTROL 0x%02X rejected: %@", command.rawValue,
                       response.map { String(format: "%02X", $0) }.joined(separator: " ")),
                level: .warning)
        }
        return accepted
    }

    func setOrpheusSyncSource(guid: UInt64, source: OrpheusSyncSource, hasAdatInput: Bool) -> Bool {
        guard let frame = OrpheusSignalSourceCodec.controlFrame(source: source, hasAdatInput: hasAdatInput),
              let response = sendRawFCPCommand(guid: guid, frame: frame, timeoutMs: Self.orpheusCommandTimeoutMs)
        else {
            return false
        }
        return OrpheusSignalSourceCodec.isAccepted(response)
    }

    // MARK: - Meters

    func readOrpheusMeters(device: OrpheusDeviceInfo, firmware: OrpheusFirmwareVersion?) -> OrpheusMeterSnapshot? {
        guard let nodeID = device.nodeID else { return nil }
        let hasStatusQuadlet = firmware?.hasMeterStatusQuadlet ?? true
        let length = hasStatusQuadlet ? OrpheusWire.meterReadLength : OrpheusWire.legacyMeterReadLength
        guard let data = orpheusSyncRead(node: UInt16(0xFFC0) | UInt16(nodeID),
                                         addressHigh: OrpheusWire.meterAddressHigh,
                                         addressLow: OrpheusWire.meterAddressLow,
                                         length: length)
        else {
            return nil
        }
        return OrpheusMeterSnapshot(data: data, hasStatusQuadlet: hasStatusQuadlet)
    }

    // MARK: - Transport Helpers

    private func orpheusStatus(guid: UInt64,
                               command: OrpheusCommand,
                               frame: Data?,
                               minimumLength: Int = OrpheusWire.frameLength) -> [UInt8]? {
        guard let frame,
              let response = sendRawFCPCommand(guid: guid, frame: frame, timeoutMs: Self.orpheusCommandTimeoutMs)
        else {
            return nil
        }
        return OrpheusCodec.validatedResponse(response, command: command, isControl: false, minimumLength: minimumLength)
    }

    private func orpheusSyncRead(node: UInt16, addressHigh: UInt16, addressLow: UInt32, length: UInt32) -> Data? {
        guard let handle = asyncRead(destinationID: node,
                                     addressHigh: addressHigh,
                                     addressLow: addressLow,
                                     length: length) else { return nil }
        let deadline = Date().addingTimeInterval(Self.orpheusReadTimeout)
        while Date() < deadline {
            if let result = getTransactionResult(handle: handle, initialPayloadCapacity: Int(length) + 128) {
                guard result.status == 0, result.responseCode == 0 else { return nil }
                return result.payload
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return nil
    }
}
