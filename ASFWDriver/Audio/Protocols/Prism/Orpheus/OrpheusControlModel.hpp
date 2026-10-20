// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 ASFireWire Project
#pragma once

#include "OrpheusTypes.hpp"
#include "../../../Controls/IControlProvider.hpp"
#include <algorithm>
#include <optional>
#include <string>

namespace ASFW::Audio::Prism::Orpheus {

namespace OrpheusControl {
inline constexpr uint32_t Gain = 0x4F520010;       // 'OR' (Orpheus)
inline constexpr uint32_t Phantom = 0x4F520020;
inline constexpr uint32_t Polarity = 0x4F520030;
inline constexpr uint32_t HighPassFilter = 0x4F520040;
inline constexpr uint32_t InputLevel = 0x4F520050;
inline constexpr uint32_t Overkiller = 0x4F520060;
inline constexpr uint32_t MidSide = 0x4F520070;
inline constexpr uint32_t LineOutputLevel = 0x4F520080;

inline constexpr uint32_t OutputVolume = 0x4F520100;
inline constexpr uint32_t OutputMute = 0x4F520101;
inline constexpr uint32_t VolumeSelectMask = 0x4F520102;
inline constexpr uint32_t MasterLock = 0x4F520103;

inline constexpr uint32_t AdatMode = 0x4F520300;
inline constexpr uint32_t ClockSource = 0x4F520301;
inline constexpr uint32_t ClockOutput = 0x4F520302;
inline constexpr uint32_t SampleRateConverter = 0x4F520303;
inline constexpr uint32_t FrontPanelMeterMode = 0x4F520304;
inline constexpr uint32_t MeterBrightness = 0x4F520305;
inline constexpr uint32_t Identify = 0x4F520306;
inline constexpr uint32_t HeadphoneSource = 0x4F520307;
inline constexpr uint32_t AnalogInputType = 0x4F520090;
inline constexpr uint32_t DigitalSampleRate = 0x4F520310;
inline constexpr uint32_t DigitalBitDepth = 0x4F520311;
inline constexpr uint32_t DigitalSync = 0x4F520312;
inline constexpr uint32_t DigitalInputType = 0x4F520313;
inline constexpr uint32_t DigitalChannelStatus = 0x4F520314;
inline constexpr uint32_t DigitalUnlocked = 0x4F520315;
inline constexpr uint32_t DigitalAsynchronous = 0x4F520316;
inline constexpr uint32_t FirmwareVersion = 0x4F520317;

inline constexpr uint32_t Mixer = 0x4F520400; // Crosspoints: bus * 12 + in
inline constexpr uint32_t MixerPan = 0x4F520500;
inline constexpr uint32_t MixerMute = 0x4F520600;
inline constexpr uint32_t MixerSolo = 0x4F520700;
inline constexpr uint32_t MixerBusGain = 0x4F520800;
inline constexpr uint32_t MixerBusMute = 0x4F520900;
inline constexpr uint32_t MixerDefeat = 0x4F520A00;
inline constexpr uint32_t MixerLink = 0x4F520B00;

inline constexpr uint32_t InputRouter = 0x4F521000;
} // namespace OrpheusControl

struct OrpheusControlsState {
    OrpheusUnitState unit;
    std::array<OrpheusAnalogChannelState, 8> analog{};
    std::array<OrpheusMixBusState, 6> mixer{};
    OrpheusDigitalState digital;
    OrpheusSyncSource syncSource{OrpheusSyncSource::Local};
    OrpheusFirmwareVersion firmware{1, 6};
};

inline Controls::ControlSnapshot BuildOrpheusControls(const OrpheusControlsState& native,
                                                      uint64_t revision,
                                                      uint64_t sequence) {
    namespace AM = ASFW::AudioModel;
    Controls::ControlSnapshot result;
    result.family = "orpheus";
    result.topology.revision = result.state.topologyRevision = revision;
    result.sequence = sequence;

    auto& t = result.topology;
    auto& s = result.state;
    uint32_t nextPort = 1;

    auto node = [&](uint32_t id, std::string name, AM::NodeBody body) {
        t.nodes.push_back({AM::NodeId{id}, std::move(name), std::move(body)});
    };

    auto port = [&](uint32_t owner, AM::PortDirection direction, std::string name, AM::SignalIdentity signal = {}) {
        const AM::PortId id{nextPort++};
        t.ports.push_back({id, AM::NodeId{owner}, direction, 1, std::move(name), signal});
        return id;
    };

    auto param = [&](uint32_t id, AM::ParameterTarget target, AM::ParameterSemantic semantic,
                     AM::ParameterDomain domain, std::string name, AM::ParameterValue value) {
        t.parameters.push_back({AM::ParameterId{id}, target, semantic, std::move(domain), std::move(name)});
        s.parameters.emplace(AM::ParameterId{id}, AM::ParameterState{std::move(value)});
    };

    const AM::EnumDomain analogInputTypes{{{0, "Line"}, {1, "Mic"}, {2, "Instrument"}}};
    const AM::EnumDomain lineOnlyLevels{{{1, "+4 dBu"}, {0, "-10 dBV"}}};
    const AM::EnumDomain hpfMic{{{0, "Flat"}, {1, "80 Hz"}}};
    const AM::EnumDomain hpfMicRiaa{{{0, "Flat"}, {1, "80 Hz"}, {2, "RIAA"}}};
    // Wire gains are 1/256 dB and unused mix paths sit at -inf (kSilent = -128 dB).
    // A 1 dB grid from -88/ -64 rejected live hardware and Prepare never published.
    const AM::ScalarDomain wireDb{static_cast<double>(Scales::kSilent) / 256.0, 0.0, std::nullopt,
                                  AM::ScalarUnit::Decibels};
    const AM::ScalarDomain preampGain{10, 65, 1, AM::ScalarUnit::Decibels};
    const AM::ScalarDomain brightness{0, 15, 1, AM::ScalarUnit::Generic};
    const AM::ScalarDomain mixPan{-20, 20, 1, AM::ScalarUnit::Generic};
    const AM::ScalarDomain mixSolo{0, 4095, 1, AM::ScalarUnit::Generic};
    const AM::ScalarDomain volumeMask{0, 1023, 1, AM::ScalarUnit::Generic};

    auto pickEnum = [](int64_t value, const AM::EnumDomain& domain) {
        for (const auto& item : domain.values) {
            if (item.value == value) return value;
        }
        return domain.values.front().value;
    };
    auto clampScalar = [](double value, const AM::ScalarDomain& domain) {
        return std::clamp(value, domain.min, domain.max);
    };

    // Host Endpoints
    node(1, "Host Capture", AM::EndpointNode{AM::EndpointKind::Host});
    node(2, "Host Playback", AM::EndpointNode{AM::EndpointKind::Host});
    node(40, "Device Settings", AM::EndpointNode{AM::EndpointKind::Host});

    std::array<AM::PortId, 8> analogInPorts{};
    std::array<AM::PortId, 8> hostPlaybackPorts{};

    // --- Analog Inputs 1 to 8 ---
    for (uint32_t ch = 0; ch < 8; ++ch) {
        const uint32_t physical = 10 + ch;
        const uint32_t router = OrpheusControl::InputRouter + ch;
        const uint32_t proc = 20 + ch;
        const auto capturePort = port(1, AM::PortDirection::Input, "Capture " + std::to_string(ch + 1),
                                      {AM::SignalKind::HostStream, ch + 1});

        if (ch < 2) {
            // Channels 1-2: Mic (XLR) or Instrument (1/4" Jack)
            node(physical, "Analog Input " + std::to_string(ch + 1), AM::EndpointNode{AM::EndpointKind::Physical});
            const auto xlr = port(physical, AM::PortDirection::Output, "XLR", {AM::SignalKind::AnalogMicXlr, ch + 1});
            const auto inst = port(physical, AM::PortDirection::Output, "Instrument", {AM::SignalKind::AnalogInstrument, ch + 1});

            const auto inA = port(router, AM::PortDirection::Input, "XLR");
            const auto inB = port(router, AM::PortDirection::Input, "Jack");
            const auto selected = port(router, AM::PortDirection::Output, "Selected");

            node(router, "Input " + std::to_string(ch + 1), AM::RouterNode{
                {inA, inB}, {selected},
                {{AM::RouteBundleId{1}, {{inA, selected}}}, {AM::RouteBundleId{2}, {{inB, selected}}}},
                {.maxActiveBundles = 1, .maxSourcesPerOutput = 1}, true
            });
            s.routers.emplace(AM::NodeId{router}, AM::RouterState{{AM::RouteBundleId{native.analog[ch].inputType == 2 ? 2u : 1u}}});

            const auto gi = port(proc, AM::PortDirection::Input, "In");
            const auto go = port(proc, AM::PortDirection::Output, "Out");
            node(proc, "Preamp " + std::to_string(ch + 1), AM::ProcessorNode{{gi}, {go}, true});

            t.fixedLinks.insert(t.fixedLinks.end(), {
                {xlr, inA}, {inst, inB}, {selected, gi}, {go, capturePort}
            });
            analogInPorts[ch] = go;

            // Parameters
            const bool isInst = native.analog[ch].inputType == static_cast<uint8_t>(OrpheusInputType::Instrument);
            const double gainVal = isInst ? native.analog[ch].instrumentGain : native.analog[ch].micGain;
            param(OrpheusControl::Gain + ch, go, AM::ParameterSemantic::Level, preampGain,
                  "Gain " + std::to_string(ch + 1), clampScalar(gainVal, preampGain));

            param(OrpheusControl::Phantom + ch, xlr, AM::ParameterSemantic::PhantomPower, AM::BooleanDomain{},
                  "Phantom " + std::to_string(ch + 1), native.analog[ch].phantom);

            param(OrpheusControl::Polarity + ch, xlr, AM::ParameterSemantic::PhaseInvert, AM::BooleanDomain{},
                  "Polarity " + std::to_string(ch + 1), native.analog[ch].phase);
            param(OrpheusControl::HighPassFilter + ch, xlr, AM::ParameterSemantic::HighPassFilter, hpfMicRiaa,
                  "Filter " + std::to_string(ch + 1), pickEnum(int64_t(native.analog[ch].filter), hpfMicRiaa));
            param(OrpheusControl::Overkiller + ch, xlr, AM::ParameterSemantic::Unknown, AM::BooleanDomain{},
                  "Overkiller " + std::to_string(ch + 1), native.analog[ch].overkiller);
            param(OrpheusControl::InputLevel + ch, xlr, AM::ParameterSemantic::NominalLevel, lineOnlyLevels,
                  "Line Level " + std::to_string(ch + 1), int64_t(native.analog[ch].lineInputLevel));
        } else if (ch < 4) {
            // Channels 3-4: Mic (XLR) or Line (TRS)
            node(physical, "Analog Input " + std::to_string(ch + 1), AM::EndpointNode{AM::EndpointKind::Physical});
            const auto xlr = port(physical, AM::PortDirection::Output, "XLR", {AM::SignalKind::AnalogMicXlr, ch + 1});
            const auto line = port(physical, AM::PortDirection::Output, "Line", {AM::SignalKind::AnalogLine, ch + 1});

            const auto inA = port(router, AM::PortDirection::Input, "XLR");
            const auto inB = port(router, AM::PortDirection::Input, "Line");
            const auto selected = port(router, AM::PortDirection::Output, "Selected");

            node(router, "Input " + std::to_string(ch + 1), AM::RouterNode{
                {inA, inB}, {selected},
                {{AM::RouteBundleId{1}, {{inA, selected}}}, {AM::RouteBundleId{2}, {{inB, selected}}}},
                {.maxActiveBundles = 1, .maxSourcesPerOutput = 1}, true
            });
            s.routers.emplace(AM::NodeId{router}, AM::RouterState{{AM::RouteBundleId{native.analog[ch].inputType == static_cast<uint8_t>(OrpheusInputType::Line) ? 2u : 1u}}});

            const auto gi = port(proc, AM::PortDirection::Input, "In");
            const auto go = port(proc, AM::PortDirection::Output, "Out");
            node(proc, "Preamp " + std::to_string(ch + 1), AM::ProcessorNode{{gi}, {go}, true});

            t.fixedLinks.insert(t.fixedLinks.end(), {
                {xlr, inA}, {line, inB}, {selected, gi}, {go, capturePort}
            });
            analogInPorts[ch] = go;

            // Parameters
            param(OrpheusControl::Gain + ch, go, AM::ParameterSemantic::Level, preampGain,
                  "Gain " + std::to_string(ch + 1), clampScalar(double(native.analog[ch].micGain), preampGain));

            param(OrpheusControl::Phantom + ch, xlr, AM::ParameterSemantic::PhantomPower, AM::BooleanDomain{},
                  "Phantom " + std::to_string(ch + 1), native.analog[ch].phantom);

            param(OrpheusControl::Polarity + ch, xlr, AM::ParameterSemantic::PhaseInvert, AM::BooleanDomain{},
                  "Polarity " + std::to_string(ch + 1), native.analog[ch].phase);
            param(OrpheusControl::HighPassFilter + ch, xlr, AM::ParameterSemantic::HighPassFilter, hpfMic,
                  "Filter " + std::to_string(ch + 1), pickEnum(int64_t(native.analog[ch].filter), hpfMic));
            param(OrpheusControl::Overkiller + ch, xlr, AM::ParameterSemantic::Unknown, AM::BooleanDomain{},
                  "Overkiller " + std::to_string(ch + 1), native.analog[ch].overkiller);
            param(OrpheusControl::InputLevel + ch, xlr, AM::ParameterSemantic::NominalLevel, lineOnlyLevels,
                  "Line Level " + std::to_string(ch + 1), int64_t(native.analog[ch].lineInputLevel));
        } else {
            // Channels 5-8: Line only (TRS)
            node(physical, "Analog Input " + std::to_string(ch + 1), AM::EndpointNode{AM::EndpointKind::Physical});
            const auto line = port(physical, AM::PortDirection::Output, "Line", {AM::SignalKind::AnalogLine, ch + 1});

            const auto gi = port(proc, AM::PortDirection::Input, "In");
            const auto go = port(proc, AM::PortDirection::Output, "Out");
            node(proc, "Line Input " + std::to_string(ch + 1), AM::ProcessorNode{{gi}, {go}, true});

            t.fixedLinks.insert(t.fixedLinks.end(), {
                {line, gi}, {go, capturePort}
            });
            analogInPorts[ch] = go;

            param(OrpheusControl::InputLevel + ch, line, AM::ParameterSemantic::NominalLevel, lineOnlyLevels,
                  "Line Level " + std::to_string(ch + 1), int64_t(native.analog[ch].lineInputLevel));
            param(OrpheusControl::Overkiller + ch, line, AM::ParameterSemantic::Unknown, AM::BooleanDomain{},
                  "Overkiller " + std::to_string(ch + 1), native.analog[ch].overkiller);
        }
        param(OrpheusControl::AnalogInputType + ch, AM::NodeId{physical}, AM::ParameterSemantic::Unknown,
              analogInputTypes, "Input Type " + std::to_string(ch + 1),
              pickEnum(int64_t(native.analog[ch].inputType), analogInputTypes));
        t.parameters.back().access = AM::ParameterAccess::ReadOnly;
        if (ch < 2) {
            param(OrpheusControl::MidSide + ch, AM::NodeId{physical}, AM::ParameterSemantic::Unknown,
                  AM::BooleanDomain{}, "Mid-side " + std::to_string(ch * 2 + 1) + "/" + std::to_string(ch * 2 + 2),
                  native.analog[ch].midSide);
        }
    }

    // --- Master Output Section ---
    node(50, "Master Output", AM::ProcessorNode{});
    auto& outProc = std::get<AM::ProcessorNode>(t.nodes.back().body);
    outProc.channelPreserving = true;

    node(51, "Analog Output", AM::EndpointNode{AM::EndpointKind::Physical});

    for (uint32_t ch = 0; ch < 8; ++ch) {
        hostPlaybackPorts[ch] = port(2, AM::PortDirection::Output, "Playback " + std::to_string(ch + 1),
                                     {AM::SignalKind::HostStream, ch + 1});
        const auto inP = port(50, AM::PortDirection::Input, "In " + std::to_string(ch + 1));
        const auto outP = port(50, AM::PortDirection::Output, "Out " + std::to_string(ch + 1));
        const auto physOut = port(51, AM::PortDirection::Input, "Line " + std::to_string(ch + 1),
                                  {AM::SignalKind::AnalogLine, ch + 1});

        outProc.inputs.push_back(inP);
        outProc.outputs.push_back(outP);
        t.fixedLinks.insert(t.fixedLinks.end(), {
            {hostPlaybackPorts[ch], inP}, {outP, physOut}
        });
        param(OrpheusControl::LineOutputLevel + ch, physOut, AM::ParameterSemantic::NominalLevel, lineOnlyLevels,
              "AO Level " + std::to_string(ch + 1), int64_t(native.analog[ch].lineOutputLevel));
    }

    param(OrpheusControl::OutputVolume, AM::NodeId{50}, AM::ParameterSemantic::Level, wireDb, "Output Volume",
          clampScalar(double(native.unit.masterVolume) / 256.0, wireDb));
    param(OrpheusControl::OutputMute, AM::NodeId{50}, AM::ParameterSemantic::Mute,
          AM::BooleanDomain{}, "Output Mute", native.unit.masterMute);
    param(OrpheusControl::MasterLock, AM::NodeId{50}, AM::ParameterSemantic::Unknown,
          AM::BooleanDomain{}, "Master Lock", native.unit.masterLock);
    param(OrpheusControl::VolumeSelectMask, AM::NodeId{50}, AM::ParameterSemantic::Unknown, volumeMask,
          "Volume Select", clampScalar(double(native.unit.volumeSelectMask), volumeMask));

    // --- 6-Bus Hardware Mixer ---
    AM::MixerNode mixerNode;
    auto mixInputName = [](uint32_t bus, uint32_t in) {
        if (in < 8) return "AI " + std::to_string(in + 1);
        if (in < 10) return "DI " + std::to_string(in - 7);
        return "DAW " + std::to_string(bus * 2 + (in - 9));
    };
    auto mixSlotName = [](uint32_t in) {
        if (in < 8) return "AI " + std::to_string(in + 1);
        if (in < 10) return "DI " + std::to_string(in - 7);
        return std::string("DAW pair");
    };
    // 12 slots per bus: AI 1-8, DI 1/2, and that bus's own DAW pair.
    for (uint32_t in = 0; in < 12; ++in) {
        std::string name = mixSlotName(in);

        const auto inputP = port(60, AM::PortDirection::Input, name);
        mixerNode.inputs.push_back(inputP);
        if (in < 8) {
            t.fixedLinks.push_back({analogInPorts[in], inputP});
        } else if (in >= 10) {
            t.fixedLinks.push_back({hostPlaybackPorts[in - 10], inputP});
        }
    }

    const std::array<std::string, 6> busNames{"AO 1/2", "AO 3/4", "AO 5/6", "AO 7/8", "DO 1/2", "HP 1/2"};
    for (uint32_t bus = 0; bus < 6; ++bus) {
        const auto mixOut = port(60, AM::PortDirection::Output, "Mix " + busNames[bus]);
        mixerNode.outputs.push_back(mixOut);

        for (uint32_t in = 0; in < 12; ++in) {
            const AM::CrosspointId cpId{bus * 12 + in + 1};
            mixerNode.crosspoints.push_back({cpId, mixerNode.inputs[in], mixOut});

            const int16_t gainRaw = native.mixer[bus].inputGains[in];
            param(OrpheusControl::Mixer + bus * 12 + in, cpId, AM::ParameterSemantic::Level, wireDb,
                  busNames[bus] + " \u2190 " + mixInputName(bus, in),
                  clampScalar(double(gainRaw) / 256.0, wireDb));
            param(OrpheusControl::MixerPan + bus * 12 + in, cpId, AM::ParameterSemantic::Pan, mixPan,
                  busNames[bus] + " pan " + mixInputName(bus, in),
                  clampScalar(double(native.mixer[bus].inputPans[in]), mixPan));
            param(OrpheusControl::MixerMute + bus * 12 + in, cpId, AM::ParameterSemantic::Mute, AM::BooleanDomain{},
                  busNames[bus] + " mute " + mixInputName(bus, in), native.mixer[bus].inputMutes[in]);
            param(OrpheusControl::MixerLink + bus * 12 + in, cpId, AM::ParameterSemantic::Unknown, AM::BooleanDomain{},
                  busNames[bus] + " link " + mixInputName(bus, in), native.mixer[bus].inputLinked[in]);
            s.parameters.at(AM::ParameterId{OrpheusControl::MixerLink + bus * 12 + in}).applicable = (in % 2 == 0);
        }
        param(OrpheusControl::MixerBusGain + bus, mixOut, AM::ParameterSemantic::Level, wireDb,
              busNames[bus] + " level", clampScalar(double(native.mixer[bus].masterGain) / 256.0, wireDb));
        param(OrpheusControl::MixerBusMute + bus, mixOut, AM::ParameterSemantic::Mute, AM::BooleanDomain{},
              busNames[bus] + " mute", native.mixer[bus].masterMute);
        param(OrpheusControl::MixerDefeat + bus, mixOut, AM::ParameterSemantic::Unknown, AM::BooleanDomain{},
              busNames[bus] + " DAW", native.mixer[bus].defeated);
        param(OrpheusControl::MixerSolo + bus, mixOut, AM::ParameterSemantic::Solo, mixSolo,
              busNames[bus] + " solo", clampScalar(double(native.mixer[bus].soloMask), mixSolo));
    }
    node(60, "Hardware Mixer", std::move(mixerNode));

    // --- Device Settings Node ---
    const AM::EnumDomain adatModes{{{0, "None"}, {1, "Send"}, {2, "Return"}, {3, "Send/Return"}, {4, "Direct"}}};
    const AM::EnumDomain syncSources{{{0, "CSP"}, {1, "FireWire"}, {2, "Local"}, {3, "Digital Input"}, {4, "ADAT"}, {5, "Word Clock"}}};
    const AM::EnumDomain clockOutputs{{{0, "fs (word clock)"}, {1, "Base clock"}, {2, "256x clock"}}};
    const AM::EnumDomain srcModes{{{0, "Disabled"}, {1, "Digital Input"}, {2, "Digital Output"}}};
    const AM::EnumDomain frontPanel{{{0, "Input"}, {1, "Output"}}};
    const AM::EnumDomain headphoneSources{{{0, "AO 1/2"}, {1, "AO 3/4"}, {2, "AO 5/6"},
                                           {3, "AO 7/8"}, {4, "DO 1/2"}, {5, "Headphone mixer"}}};

    param(OrpheusControl::AdatMode, AM::NodeId{40}, AM::ParameterSemantic::Unknown,
          adatModes, "ADAT Mode", pickEnum(int64_t(native.unit.adatMode), adatModes));
    param(OrpheusControl::ClockSource, AM::NodeId{40}, AM::ParameterSemantic::ClockSource,
          syncSources, "Sync Source", pickEnum(int64_t(native.syncSource), syncSources));
    param(OrpheusControl::ClockOutput, AM::NodeId{40}, AM::ParameterSemantic::Unknown,
          clockOutputs, "Word Clock Output", pickEnum(int64_t(native.unit.clockOutput), clockOutputs));
    param(OrpheusControl::SampleRateConverter, AM::NodeId{40}, AM::ParameterSemantic::Unknown,
          srcModes, "Sample Rate Converter", pickEnum(int64_t(native.unit.sampleRateConverter), srcModes));
    param(OrpheusControl::FrontPanelMeterMode, AM::NodeId{40}, AM::ParameterSemantic::Unknown,
          frontPanel, "Front Panel Meters", pickEnum(int64_t(native.unit.frontPanelMeterMode), frontPanel));
    param(OrpheusControl::MeterBrightness, AM::NodeId{40}, AM::ParameterSemantic::Unknown, brightness,
          "Meter Brightness", clampScalar(double(native.unit.meterBrightness), brightness));
    param(OrpheusControl::Identify, AM::NodeId{40}, AM::ParameterSemantic::Unknown, AM::BooleanDomain{},
          "Identify", native.unit.identify);
    param(OrpheusControl::HeadphoneSource, AM::NodeId{40}, AM::ParameterSemantic::Unknown, headphoneSources,
          "Headphone Source", pickEnum(int64_t(native.unit.headphoneSource), headphoneSources));

    const AM::EnumDomain digitalRates{{{1, "44.1 kHz"}, {2, "48 kHz"}, {3, "88.2 kHz"},
                                       {4, "96 kHz"}, {5, "176.4 kHz"}, {6, "192 kHz"}}};
    const AM::EnumDomain digitalDepth{{{24, "24 bit"}, {16, "16 bit"}, {0, "16 bit SNS1"},
                                       {1, "16 bit SNS2"}, {2, "16 bit SNS3"}, {3, "16 bit SNS4"}}};
    const AM::EnumDomain digitalSync{{{0, "Local"}, {1, "Word clock"}, {2, "Digital input"}}};
    const AM::EnumDomain digitalIn{{{0, "S/PDIF (coaxial)"}, {1, "TOSLINK (optical)"}}};
    const AM::EnumDomain digitalStatus{{{0, "S/PDIF (consumer)"}, {1, "AES3 (professional)"}}};

    param(OrpheusControl::DigitalSampleRate, AM::NodeId{40}, AM::ParameterSemantic::Unknown, digitalRates,
          "Digital Sample Rate", pickEnum(int64_t(native.digital.sampleRate), digitalRates));
    param(OrpheusControl::DigitalBitDepth, AM::NodeId{40}, AM::ParameterSemantic::Unknown, digitalDepth,
          "Digital Bit Depth", pickEnum(int64_t(native.digital.bitDepth), digitalDepth));
    param(OrpheusControl::DigitalSync, AM::NodeId{40}, AM::ParameterSemantic::Unknown, digitalSync,
          "Digital Sync", pickEnum(int64_t(native.digital.syncSource), digitalSync));
    param(OrpheusControl::DigitalInputType, AM::NodeId{40}, AM::ParameterSemantic::Unknown, digitalIn,
          "Digital Input", pickEnum(int64_t(native.digital.inputType), digitalIn));
    param(OrpheusControl::DigitalChannelStatus, AM::NodeId{40}, AM::ParameterSemantic::Unknown, digitalStatus,
          "Digital Channel Status", pickEnum(int64_t(native.digital.channelStatus), digitalStatus));
    param(OrpheusControl::DigitalUnlocked, AM::NodeId{40}, AM::ParameterSemantic::Unknown, AM::BooleanDomain{},
          "Digital Unlocked", native.digital.unlocked);
    t.parameters.back().access = AM::ParameterAccess::ReadOnly;
    param(OrpheusControl::DigitalAsynchronous, AM::NodeId{40}, AM::ParameterSemantic::Unknown, AM::BooleanDomain{},
          "Digital Async", native.digital.asynchronous);
    t.parameters.back().access = AM::ParameterAccess::ReadOnly;
    const AM::ScalarDomain firmwareVersion{0, 65535, 1, AM::ScalarUnit::Generic};
    param(OrpheusControl::FirmwareVersion, AM::NodeId{40}, AM::ParameterSemantic::Unknown, firmwareVersion,
          "Firmware",
          clampScalar(double((uint32_t(native.firmware.major) << 8) | native.firmware.minor), firmwareVersion));
    t.parameters.back().access = AM::ParameterAccess::ReadOnly;

    return result;
}

} // namespace ASFW::Audio::Prism::Orpheus
