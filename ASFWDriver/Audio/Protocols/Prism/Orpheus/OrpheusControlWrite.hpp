// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 ASFireWire Project
#pragma once

#include "OrpheusControlModel.hpp"
#include "OrpheusVendorCodec.hpp"
#include <cmath>
#include <optional>
#include <vector>

namespace ASFW::Audio::Prism::Orpheus {

enum class OrpheusControlGroup {
    Input,
    Output,
    Mixer,
    Settings,
    ClockSource,
    Digital,
    Firmware
};

struct OrpheusControlWrite {
    OrpheusControlsState desired;
    OrpheusControlGroup group;
    uint8_t index{0};
    std::vector<std::vector<uint8_t>> frames;
};

inline std::optional<OrpheusControlWrite> BuildOrpheusParameterWrite(const OrpheusControlsState& current,
                                                                    AudioModel::ParameterId id,
                                                                    const AudioModel::ParameterValue& value) {
    auto next = current;
    OrpheusControlGroup group = OrpheusControlGroup::Input;
    uint8_t index = 0;
    std::vector<std::vector<uint8_t>> frames;

    if (id.value >= OrpheusControl::Gain && id.value < OrpheusControl::Gain + 8) {
        const auto ch = id.value - OrpheusControl::Gain;
        if (ch >= 4) return std::nullopt; // Only Ch 1..4 have preamps
        const auto* db = std::get_if<double>(&value);
        if (!db) return std::nullopt;
        const auto gainVal = static_cast<uint8_t>(std::clamp(std::lround(*db), 10L, 65L));

        if (next.analog[ch].inputType == 2) {
            next.analog[ch].instrumentGain = gainVal;
            const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::InstrumentGain, ch, gainVal);
            if (f) frames.push_back(*f);
        } else {
            next.analog[ch].micGain = gainVal;
            const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::MicGain, ch, gainVal);
            if (f) frames.push_back(*f);
        }
        group = OrpheusControlGroup::Input;
        index = static_cast<uint8_t>(ch);
    } else if (id.value >= OrpheusControl::Phantom && id.value < OrpheusControl::Phantom + 4) {
        const auto ch = id.value - OrpheusControl::Phantom;
        const auto* enabled = std::get_if<bool>(&value);
        if (!enabled) return std::nullopt;
        next.analog[ch].phantom = *enabled;
        const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::Phantom, ch, *enabled ? 1 : 0);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Input;
        index = static_cast<uint8_t>(ch);
    } else if (id.value >= OrpheusControl::Polarity && id.value < OrpheusControl::Polarity + 4) {
        const auto ch = id.value - OrpheusControl::Polarity;
        const auto* enabled = std::get_if<bool>(&value);
        if (!enabled) return std::nullopt;
        next.analog[ch].phase = *enabled;
        const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::Phase, ch, *enabled ? 1 : 0);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Input;
        index = static_cast<uint8_t>(ch);
    } else if (id.value >= OrpheusControl::HighPassFilter && id.value < OrpheusControl::HighPassFilter + 4) {
        const auto ch = id.value - OrpheusControl::HighPassFilter;
        const auto* filter = std::get_if<int64_t>(&value);
        if (!filter) return std::nullopt;
        next.analog[ch].filter = static_cast<uint8_t>(*filter);
        const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::Filter, ch, static_cast<uint8_t>(*filter));
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Input;
        index = static_cast<uint8_t>(ch);
    } else if (id.value >= OrpheusControl::Overkiller && id.value < OrpheusControl::Overkiller + 8) {
        const auto ch = id.value - OrpheusControl::Overkiller;
        const auto* enabled = std::get_if<bool>(&value);
        if (!enabled) return std::nullopt;
        next.analog[ch].overkiller = *enabled;
        const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::Overkiller, ch, *enabled ? 1 : 0);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Input;
        index = static_cast<uint8_t>(ch);
    } else if (id.value >= OrpheusControl::InputLevel && id.value < OrpheusControl::InputLevel + 8) {
        const auto ch = id.value - OrpheusControl::InputLevel;
        const auto* level = std::get_if<int64_t>(&value);
        if (!level) return std::nullopt;
        next.analog[ch].lineInputLevel = static_cast<uint8_t>(*level);
        const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::LineInputLevel, ch, static_cast<uint8_t>(*level));
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Input;
        index = static_cast<uint8_t>(ch);
    } else if (id.value == OrpheusControl::OutputVolume) {
        const auto* db = std::get_if<double>(&value);
        if (!db) return std::nullopt;
        const int16_t raw = static_cast<int16_t>(std::lround(*db * 256.0));
        const size_t pos = Scales::BigKnobPositionForRaw(raw);
        next.unit.masterVolume = Scales::kBigKnobValues[pos];
        frames.push_back(OrpheusVendorCodec::BuildMasterVolumeControl(next.unit.masterVolume));
        group = OrpheusControlGroup::Output;
    } else if (id.value == OrpheusControl::OutputMute) {
        const auto* mute = std::get_if<bool>(&value);
        if (!mute) return std::nullopt;
        next.unit.masterMute = *mute;
        frames.push_back(OrpheusVendorCodec::BuildMasterMuteControl(*mute));
        group = OrpheusControlGroup::Output;
    } else if (id.value == OrpheusControl::AdatMode) {
        const auto* mode = std::get_if<int64_t>(&value);
        if (!mode) return std::nullopt;
        next.unit.adatMode = static_cast<uint8_t>(*mode);
        const uint8_t op[] = {static_cast<uint8_t>(*mode)};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::AdatMode, op));
        group = OrpheusControlGroup::Settings;
    } else if (id.value == OrpheusControl::ClockOutput) {
        const auto* out = std::get_if<int64_t>(&value);
        if (!out) return std::nullopt;
        next.unit.clockOutput = static_cast<uint8_t>(*out);
        const uint8_t op[] = {static_cast<uint8_t>(*out)};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::ClockOutput, op));
        group = OrpheusControlGroup::Settings;
    } else if (id.value == OrpheusControl::SampleRateConverter) {
        const auto* src = std::get_if<int64_t>(&value);
        if (!src) return std::nullopt;
        next.unit.sampleRateConverter = static_cast<uint8_t>(*src);
        const uint8_t op[] = {static_cast<uint8_t>(*src)};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::SampleRateConverter, op));
        group = OrpheusControlGroup::Settings;
    } else if (id.value == OrpheusControl::ClockSource) {
        const auto* src = std::get_if<int64_t>(&value);
        if (!src) return std::nullopt;
        next.syncSource = static_cast<OrpheusSyncSource>(*src);
        const auto f = OrpheusVendorCodec::BuildSignalSourceControl(next.syncSource, next.unit.HasAdatInput());
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::ClockSource;
    } else if (id.value >= OrpheusControl::Mixer && id.value < OrpheusControl::Mixer + 72) {
        const auto cp = id.value - OrpheusControl::Mixer;
        const auto bus = cp / 12;
        const auto in = cp % 12;
        const auto* db = std::get_if<double>(&value);
        if (!db) return std::nullopt;
        const int16_t raw = static_cast<int16_t>(std::lround(*db * 256.0));
        const size_t pos = Scales::MixGainPositionForRaw(raw);
        const int16_t snapped = Scales::kMixGainValues[pos];
        next.mixer[bus].inputGains[in] = snapped;
        const auto f = OrpheusVendorCodec::BuildMixInputGainControl(bus, in, snapped);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Mixer;
        index = static_cast<uint8_t>(bus);
    } else if (id.value == OrpheusControl::MasterLock) {
        const auto* locked = std::get_if<bool>(&value);
        if (!locked) return std::nullopt;
        next.unit.masterLock = *locked;
        const uint8_t op[] = {static_cast<uint8_t>(*locked ? 1 : 0)};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::MasterLock, op));
        group = OrpheusControlGroup::Output;
    } else if (id.value == OrpheusControl::Identify) {
        const auto* enabled = std::get_if<bool>(&value);
        if (!enabled) return std::nullopt;
        next.unit.identify = *enabled;
        const uint8_t op[] = {static_cast<uint8_t>(*enabled ? 1 : 0)};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::Identify, op));
        group = OrpheusControlGroup::Settings;
    } else if (id.value == OrpheusControl::FrontPanelMeterMode) {
        const auto* mode = std::get_if<int64_t>(&value);
        if (!mode) return std::nullopt;
        next.unit.frontPanelMeterMode = static_cast<uint8_t>(*mode);
        const uint8_t op[] = {static_cast<uint8_t>(*mode)};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::FrontPanelMeterMode, op));
        group = OrpheusControlGroup::Settings;
    } else if (id.value == OrpheusControl::MeterBrightness) {
        const auto* db = std::get_if<double>(&value);
        if (!db) return std::nullopt;
        next.unit.meterBrightness = static_cast<uint8_t>(std::clamp(std::lround(*db), 0L, 15L));
        const uint8_t op[] = {next.unit.meterBrightness};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::MeterBrightness, op));
        group = OrpheusControlGroup::Settings;
    } else if (id.value == OrpheusControl::VolumeSelectMask) {
        const auto* mask = std::get_if<double>(&value);
        if (!mask) return std::nullopt;
        next.unit.volumeSelectMask = static_cast<uint16_t>(std::clamp(std::lround(*mask), 0L, 1023L));
        frames.push_back(OrpheusVendorCodec::BuildVolumeSelectControl(next.unit.volumeSelectMask));
        group = OrpheusControlGroup::Output;
    } else if (id.value == OrpheusControl::HeadphoneSource) {
        const auto* source = std::get_if<int64_t>(&value);
        if (!source) return std::nullopt;
        next.unit.headphoneSource = static_cast<uint8_t>(*source);
        const uint8_t op[] = {next.unit.headphoneSource};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::HeadphoneSource, op));
        group = OrpheusControlGroup::Output;
    } else if (id.value == OrpheusControl::DigitalSampleRate) {
        const auto* rate = std::get_if<int64_t>(&value);
        if (!rate) return std::nullopt;
        next.digital.sampleRate = static_cast<uint8_t>(*rate);
        const uint8_t op[] = {next.digital.sampleRate};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::DigitalSampleRate, op));
        group = OrpheusControlGroup::Digital;
    } else if (id.value == OrpheusControl::DigitalBitDepth) {
        const auto* depth = std::get_if<int64_t>(&value);
        if (!depth) return std::nullopt;
        next.digital.bitDepth = static_cast<uint8_t>(*depth);
        const uint8_t op[] = {next.digital.bitDepth};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::DigitalBitDepth, op));
        group = OrpheusControlGroup::Digital;
    } else if (id.value == OrpheusControl::DigitalSync) {
        const auto* sync = std::get_if<int64_t>(&value);
        if (!sync) return std::nullopt;
        next.digital.syncSource = static_cast<uint8_t>(*sync);
        const uint8_t op[] = {next.digital.syncSource};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::DigitalSync, op));
        group = OrpheusControlGroup::Digital;
    } else if (id.value == OrpheusControl::DigitalInputType) {
        const auto* type = std::get_if<int64_t>(&value);
        if (!type) return std::nullopt;
        next.digital.inputType = static_cast<uint8_t>(*type);
        const uint8_t op[] = {next.digital.inputType};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::DigitalInputType, op));
        group = OrpheusControlGroup::Digital;
    } else if (id.value == OrpheusControl::DigitalChannelStatus) {
        const auto* status = std::get_if<int64_t>(&value);
        if (!status) return std::nullopt;
        next.digital.channelStatus = static_cast<uint8_t>(*status);
        const uint8_t op[] = {next.digital.channelStatus};
        frames.push_back(OrpheusVendorCodec::BuildControlFrame(OrpheusCommand::DigitalChannelStatus, op));
        group = OrpheusControlGroup::Digital;
    } else if (id.value >= OrpheusControl::MidSide && id.value < OrpheusControl::MidSide + 2) {
        const auto pair = id.value - OrpheusControl::MidSide;
        const auto* enabled = std::get_if<bool>(&value);
        if (!enabled) return std::nullopt;
        next.analog[pair].midSide = *enabled;
        const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::MidSide, static_cast<uint8_t>(pair),
                                                              *enabled ? 1 : 0);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Input;
        index = static_cast<uint8_t>(pair);
    } else if (id.value >= OrpheusControl::LineOutputLevel && id.value < OrpheusControl::LineOutputLevel + 8) {
        const auto ch = id.value - OrpheusControl::LineOutputLevel;
        const auto* level = std::get_if<int64_t>(&value);
        if (!level) return std::nullopt;
        next.analog[ch].lineOutputLevel = static_cast<uint8_t>(*level);
        const auto f = OrpheusVendorCodec::BuildAnalogControl(OrpheusCommand::LineOutputLevel, static_cast<uint8_t>(ch),
                                                              static_cast<uint8_t>(*level));
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Output;
        index = static_cast<uint8_t>(ch);
    } else if (id.value >= OrpheusControl::MixerPan && id.value < OrpheusControl::MixerPan + 72) {
        const auto cp = id.value - OrpheusControl::MixerPan;
        const auto bus = cp / 12;
        const auto in = cp % 12;
        const auto* pan = std::get_if<double>(&value);
        if (!pan) return std::nullopt;
        const auto position = static_cast<int8_t>(std::clamp(std::lround(*pan), -20L, 20L));
        next.mixer[bus].inputPans[in] = position;
        const bool balance = next.mixer[bus].inputLinked[in & ~1u];
        const auto f = OrpheusVendorCodec::BuildMixInputPositionControl(static_cast<uint8_t>(bus),
                                                                        static_cast<uint8_t>(balance ? (in & ~1u) : in),
                                                                        position, balance);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Mixer;
        index = static_cast<uint8_t>(bus);
    } else if (id.value >= OrpheusControl::MixerMute && id.value < OrpheusControl::MixerMute + 72) {
        const auto cp = id.value - OrpheusControl::MixerMute;
        const auto bus = cp / 12;
        const auto in = cp % 12;
        const auto* muted = std::get_if<bool>(&value);
        if (!muted) return std::nullopt;
        next.mixer[bus].inputMutes[in] = *muted;
        const auto f = OrpheusVendorCodec::BuildMixInputMuteControl(static_cast<uint8_t>(bus), static_cast<uint8_t>(in),
                                                                    *muted);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Mixer;
        index = static_cast<uint8_t>(bus);
    } else if (id.value >= OrpheusControl::MixerSolo && id.value < OrpheusControl::MixerSolo + 6) {
        const auto bus = id.value - OrpheusControl::MixerSolo;
        const auto* mask = std::get_if<double>(&value);
        if (!mask) return std::nullopt;
        next.mixer[bus].soloMask = static_cast<uint16_t>(std::clamp(std::lround(*mask), 0L, 4095L));
        const auto f = OrpheusVendorCodec::BuildMixBusSoloControl(static_cast<uint8_t>(bus), next.mixer[bus].soloMask);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Mixer;
        index = static_cast<uint8_t>(bus);
    } else if (id.value >= OrpheusControl::MixerBusGain && id.value < OrpheusControl::MixerBusGain + 6) {
        const auto bus = id.value - OrpheusControl::MixerBusGain;
        const auto* db = std::get_if<double>(&value);
        if (!db) return std::nullopt;
        const int16_t raw = static_cast<int16_t>(std::lround(*db * 256.0));
        const size_t pos = Scales::MixGainPositionForRaw(raw);
        next.mixer[bus].masterGain = Scales::kMixGainValues[pos];
        const auto f = OrpheusVendorCodec::BuildMixBusGainControl(static_cast<uint8_t>(bus), next.mixer[bus].masterGain);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Mixer;
        index = static_cast<uint8_t>(bus);
    } else if (id.value >= OrpheusControl::MixerBusMute && id.value < OrpheusControl::MixerBusMute + 6) {
        const auto bus = id.value - OrpheusControl::MixerBusMute;
        const auto* muted = std::get_if<bool>(&value);
        if (!muted) return std::nullopt;
        next.mixer[bus].masterMute = *muted;
        const auto f = OrpheusVendorCodec::BuildMixBusMuteControl(static_cast<uint8_t>(bus), *muted);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Mixer;
        index = static_cast<uint8_t>(bus);
    } else if (id.value >= OrpheusControl::MixerDefeat && id.value < OrpheusControl::MixerDefeat + 6) {
        const auto bus = id.value - OrpheusControl::MixerDefeat;
        const auto* defeated = std::get_if<bool>(&value);
        if (!defeated) return std::nullopt;
        next.mixer[bus].defeated = *defeated;
        const auto f = OrpheusVendorCodec::BuildMixDefeatControl(static_cast<uint8_t>(bus), *defeated);
        if (f) frames.push_back(*f);
        group = OrpheusControlGroup::Mixer;
        index = static_cast<uint8_t>(bus);
    } else if (id.value >= OrpheusControl::MixerLink && id.value < OrpheusControl::MixerLink + 72) {
        const auto cp = id.value - OrpheusControl::MixerLink;
        const auto bus = cp / 12;
        const auto in = cp % 12;
        const auto* linked = std::get_if<bool>(&value);
        if (!linked) return std::nullopt;
        if ((in | 1u) == 11u) return std::nullopt; // DAW pair: original SetMix type 5 skips it
        next.mixer[bus].inputLinked[in] = *linked;
        const uint8_t left = static_cast<uint8_t>(in & ~1u);
        next.mixer[bus].inputLinked[left] = *linked;
        next.mixer[bus].inputLinked[left + 1] = *linked;
        if (*linked) {
            const int avg = (static_cast<int>(next.mixer[bus].inputPans[left]) +
                             static_cast<int>(next.mixer[bus].inputPans[left + 1])) / 2;
            const auto balance = static_cast<int8_t>(std::clamp(avg, -20, 20));
            next.mixer[bus].inputPans[left] = balance;
            next.mixer[bus].inputPans[left + 1] = balance;
            next.mixer[bus].inputGains[left + 1] = next.mixer[bus].inputGains[left];
            next.mixer[bus].inputMutes[left + 1] = next.mixer[bus].inputMutes[left];
            const auto f = OrpheusVendorCodec::BuildMixInputPositionControl(
                static_cast<uint8_t>(bus), left, balance, true);
            if (f) frames.push_back(*f);
            const auto gain = OrpheusVendorCodec::BuildMixInputGainControl(
                static_cast<uint8_t>(bus), static_cast<uint8_t>(left + 1), next.mixer[bus].inputGains[left + 1]);
            if (gain) frames.push_back(*gain);
            const auto mute = OrpheusVendorCodec::BuildMixInputMuteControl(
                static_cast<uint8_t>(bus), static_cast<uint8_t>(left + 1), next.mixer[bus].inputMutes[left + 1]);
            if (mute) frames.push_back(*mute);
        } else {
            const int value = static_cast<int>(next.mixer[bus].inputPans[left]);
            const auto leftPan = static_cast<int8_t>(value < 0 ? -20 : std::clamp(value * 2 - 20, -20, 20));
            const auto rightPan = static_cast<int8_t>(value < 0 ? std::clamp(value * 2 + 20, -20, 20) : 20);
            next.mixer[bus].inputPans[left] = leftPan;
            next.mixer[bus].inputPans[left + 1] = rightPan;
            const auto l = OrpheusVendorCodec::BuildMixInputPositionControl(
                static_cast<uint8_t>(bus), left, leftPan, false);
            const auto r = OrpheusVendorCodec::BuildMixInputPositionControl(
                static_cast<uint8_t>(bus), static_cast<uint8_t>(left + 1), rightPan, false);
            if (l) frames.push_back(*l);
            if (r) frames.push_back(*r);
        }
        group = OrpheusControlGroup::Mixer;
        index = static_cast<uint8_t>(bus);
    } else {
        return std::nullopt;
    }

    if (frames.empty()) return std::nullopt;
    return OrpheusControlWrite{std::move(next), group, index, std::move(frames)};
}

} // namespace ASFW::Audio::Prism::Orpheus
