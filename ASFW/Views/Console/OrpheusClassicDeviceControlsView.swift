import SwiftUI

/// Device Controls console for family "orpheus": the classic Prism chrome,
/// bound to the driver's control snapshot. Vendor bitmaps stay local until
/// Prism grants a redistribution license.
struct OrpheusClassicDeviceControlsView: View {
    let snapshot: ControlSnapshot
    @ObservedObject var model: DeviceControlsViewModel
    @StateObject private var session = OrpheusControlViewModel()

    var body: some View {
        OrpheusClassicView(viewModel: session)
            .onAppear {
                session.attach(model)
                session.apply(snapshot)
            }
            .onDisappear { session.stopMeters() }
            .onChange(of: snapshot) { _, snapshot in session.apply(snapshot) }
            .alert(phantomTitle, isPresented: phantomPresented) {
                Button("Cancel", role: .cancel) { session.pendingPhantomChannel = nil }
                Button("Enable") { session.confirmPendingPhantom() }
            } message: {
                Text("Never apply phantom power to ribbon microphones or to sources that are not designed for it.")
            }
    }

    private var phantomTitle: String {
        guard let channel = session.pendingPhantomChannel else { return "Enable phantom power?" }
        return "Enable 48 V phantom power on AI \(channel + 1)?"
    }

    private var phantomPresented: Binding<Bool> {
        Binding(get: { session.pendingPhantomChannel != nil },
                set: { if !$0 { session.pendingPhantomChannel = nil } })
    }
}
