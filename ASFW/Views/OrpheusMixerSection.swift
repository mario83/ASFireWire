import SwiftUI

struct OrpheusMixerSection: View {
    @ObservedObject var viewModel: OrpheusControlViewModel

    private var bus: Int { viewModel.selectedBus }
    private var busState: OrpheusMixBusState { viewModel.mixBuses[bus] }
    private var isHeadphoneBus: Bool { bus == OrpheusHeadphones.headphoneBus }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("Bus")
                        .font(.subheadline)
                        .frame(minWidth: 36, alignment: .leading)
                    Picker("Bus", selection: $viewModel.selectedBus) {
                        ForEach(0..<OrpheusWire.mixBusCount, id: \.self) { bus in
                            Text(OrpheusMix.busNames[bus]).tag(bus)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        viewModel.refreshMixBus(bus)
                    } label: {
                        Label("Reload bus", systemImage: "arrow.clockwise")
                    }
                }

                busMasterRow

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(0..<OrpheusWire.mixInputCount, id: \.self) { input in
                            inputStrip(input)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .opacity(busState.defeated ? 0.55 : 1)

                if busState.defeated {
                    Text("This bus plays the DAW signal directly; the mixer settings below are kept but not heard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Mixer", systemImage: "slider.vertical.3")
                .font(.headline)
        }
    }

    private var busMasterRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            OrpheusSteppedSlider(title: "Bus level",
                                 raw: busState.gain,
                                 scale: .mixGain) { viewModel.setBusGain(bus: bus, gain: $0) }

            HStack(spacing: 12) {
                Toggle("Mute bus", isOn: Binding(get: { busState.mute },
                                                 set: { viewModel.setBusMute(bus: bus, muted: $0) }))

                Text("Source")
                    .font(.subheadline)
                if isHeadphoneBus {
                    Picker("Source", selection: Binding(get: { viewModel.headphoneRouting },
                                                        set: { viewModel.setHeadphoneRouting($0) })) {
                        ForEach(OrpheusHeadphones.routings, id: \.self) { routing in
                            Text(routing.label).tag(routing)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 300, alignment: .leading)
                } else {
                    Picker("Source", selection: Binding(get: { busState.defeated },
                                                        set: { viewModel.setBusDefeat(bus: bus, defeated: $0) })) {
                        Text("Mixer").tag(false)
                        Text("DAW").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 24)
        }
    }

    private func inputStrip(_ input: Int) -> some View {
        let state = busState.inputs[input]
        let linked = viewModel.isLinked(bus: bus, input: input)
        let soloed = busState.soloMask & (UInt16(1) << input) != 0

        return VStack(spacing: 6) {
            Text(OrpheusMix.inputNames[input])
                .font(.caption.weight(.semibold))

            OrpheusVerticalFader(raw: state.gain) { viewModel.setInputGain(bus: bus, input: input, gain: $0) }

            VStack(spacing: 2) {
                Text(linked ? "Bal \(state.position)" : "Pan \(state.position)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(state.position) },
                                      set: { viewModel.setInputPosition(bus: bus, input: input, position: Int8($0.rounded())) }),
                       in: Double(OrpheusMix.positionRange.lowerBound)...Double(OrpheusMix.positionRange.upperBound))
                    .controlSize(.mini)
                    .labelsHidden()
                    .frame(width: 64)
            }

            HStack(spacing: 4) {
                stripButton("M", active: state.mute, color: .red) {
                    viewModel.setInputMute(bus: bus, input: input, muted: !state.mute)
                }
                stripButton("S", active: soloed, color: .yellow) {
                    viewModel.setSolo(bus: bus, input: input, enabled: !soloed)
                }
            }

            if OrpheusMix.isLinkable(input: input) && input % 2 == 0 {
                Toggle("Link", isOn: Binding(get: { linked },
                                             set: { viewModel.setLink(bus: bus, pair: input, linked: $0) }))
                    .toggleStyle(.checkbox)
                    .font(.caption2)
            } else {
                Text(" ").font(.caption2)
            }
        }
        .frame(width: 70)
        .padding(.vertical, 6)
        .background(linked ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private func stripButton(_ title: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 18)
                .background(active ? color.opacity(0.85) : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(active ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
