import Foundation

extension ASFWDriverConnector {
    /// Meter peaks live in a FireWire block, not in the FCP control graph.
    func readOrpheusMeters(guid: UInt64, hasStatusQuadlet: Bool) -> OrpheusMeterSnapshot? {
        if let snapshot = readOrpheusMetersOnce(guid: guid, hasStatusQuadlet: hasStatusQuadlet) {
            return snapshot
        }
        return readOrpheusMetersOnce(guid: guid, hasStatusQuadlet: !hasStatusQuadlet)
    }

    private func readOrpheusMetersOnce(guid: UInt64, hasStatusQuadlet: Bool) -> OrpheusMeterSnapshot? {
        guard let device = (getDiscoveredDevices() ?? []).first(where: { $0.guid == guid }) else { return nil }
        let length = hasStatusQuadlet ? OrpheusWire.meterReadLength : OrpheusWire.legacyMeterReadLength
        let node = UInt16(0xFFC0) | UInt16(device.nodeId)
        guard let handle = asyncBlockRead(destinationID: node,
                                          addressHigh: OrpheusWire.meterAddressHigh,
                                          addressLow: OrpheusWire.meterAddressLow,
                                          length: length,
                                          quiet: true)
        else { return nil }
        let deadline = Date().addingTimeInterval(0.12)
        while Date() < deadline {
            if let result = getTransactionResult(handle: handle, initialPayloadCapacity: Int(length) + 128, quiet: true) {
                guard result.status == 0, result.responseCode == 0 else { return nil }
                return OrpheusMeterSnapshot(data: result.payload, hasStatusQuadlet: hasStatusQuadlet)
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return nil
    }
}
