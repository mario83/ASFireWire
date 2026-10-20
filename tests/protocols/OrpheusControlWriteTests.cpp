// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 ASFireWire Project

#include <gtest/gtest.h>
#include "ASFWDriver/Audio/Protocols/Prism/Orpheus/OrpheusControlWrite.hpp"

using namespace ASFW::Audio::Prism::Orpheus;
namespace AM = ASFW::AudioModel;

namespace {

OrpheusControlsState MakeState() {
    OrpheusControlsState state;
    state.unit.masterVolume = 0;
    state.unit.adatMode = 3;
    state.syncSource = OrpheusSyncSource::Local;
    state.analog[0].inputType = static_cast<uint8_t>(OrpheusInputType::Mic);
    state.analog[1].inputType = 2; // Inst
    return state;
}

} // namespace

TEST(OrpheusControlWriteTests, GainWriteBuildsMicGainFrame) {
    const auto state = MakeState();
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::Gain + 0}, 42.0);
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::Input);
    ASSERT_EQ(write->frames.size(), 1U);
    const auto& frame = write->frames[0];
    EXPECT_EQ(frame[Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MicGain));
    EXPECT_EQ(frame[7], 0);  // ch 0
    EXPECT_EQ(frame[8], 42); // gain
    EXPECT_EQ(write->desired.analog[0].micGain, 42);
}

TEST(OrpheusControlWriteTests, InstrumentGainWriteWhenInstrumentInputSelected) {
    const auto state = MakeState(); // analog[1].inputType == 2 (Instrument)
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::Gain + 1}, 25.0);
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::Input);
    ASSERT_EQ(write->frames.size(), 1U);
    const auto& frame = write->frames[0];
    EXPECT_EQ(frame[Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::InstrumentGain));
    EXPECT_EQ(frame[7], 1);  // ch 1
    EXPECT_EQ(frame[8], 25); // inst gain
    EXPECT_EQ(write->desired.analog[1].instrumentGain, 25);
}

TEST(OrpheusControlWriteTests, PhantomPowerWrite) {
    const auto state = MakeState();
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::Phantom + 0}, true);
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::Input);
    ASSERT_EQ(write->frames.size(), 1U);
    const auto& frame = write->frames[0];
    EXPECT_EQ(frame[Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::Phantom));
    EXPECT_EQ(frame[7], 0); // ch 0
    EXPECT_EQ(frame[8], 1); // enabled
    EXPECT_TRUE(write->desired.analog[0].phantom);
}

TEST(OrpheusControlWriteTests, AdatModeWrite) {
    const auto state = MakeState();
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::AdatMode}, int64_t(3));
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::Settings);
    ASSERT_EQ(write->frames.size(), 1U);
    const auto& frame = write->frames[0];
    EXPECT_EQ(frame[Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::AdatMode));
    EXPECT_EQ(frame[7], 3);
    EXPECT_EQ(write->desired.unit.adatMode, 3);
}

TEST(OrpheusControlWriteTests, OutputVolumeWriteSnapsToBigKnobValues) {
    const auto state = MakeState();
    // -10 dB -> -2560 raw
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::OutputVolume}, -10.0);
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::Output);
    ASSERT_EQ(write->frames.size(), 1U);
    const auto& frame = write->frames[0];
    EXPECT_EQ(frame[Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MasterVolume));
    EXPECT_EQ(write->desired.unit.masterVolume, -2560);
}

TEST(OrpheusControlWriteTests, MixerCrosspointWrite) {
    const auto state = MakeState();
    // Bus 1 (Mix AO 3/4), Input 4: crosspoint = 1 * 12 + 4 = 16
    const auto paramId = AM::ParameterId{OrpheusControl::Mixer + 16};
    const auto write = BuildOrpheusParameterWrite(state, paramId, 0.0); // 0 dB
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::Mixer);
    ASSERT_EQ(write->frames.size(), 1U);
    const auto& frame = write->frames[0];
    EXPECT_EQ(frame[Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MixInputGain));
    EXPECT_EQ(frame[7], 1); // Bus 1
    EXPECT_EQ(frame[8], 4); // Input 4
    EXPECT_EQ(frame[9], 0x00); // 0 dB raw
    EXPECT_EQ(frame[10], 0x00);
    EXPECT_EQ(write->desired.mixer[1].inputGains[4], 0);
}

TEST(OrpheusControlWriteTests, MixerPanWrite) {
    const auto state = MakeState();
    const auto paramId = AM::ParameterId{OrpheusControl::MixerPan + 16}; // bus 1, input 4
    const auto write = BuildOrpheusParameterWrite(state, paramId, -8.0);
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::Mixer);
    ASSERT_EQ(write->frames.size(), 1U);
    const auto& frame = write->frames[0];
    EXPECT_EQ(frame[Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MixInputPan));
    EXPECT_EQ(frame[7], 1);
    EXPECT_EQ(frame[8], 4);
    EXPECT_EQ(static_cast<int8_t>(frame[9]), -8);
    EXPECT_EQ(write->desired.mixer[1].inputPans[4], -8);
}

TEST(OrpheusControlWriteTests, MixerLinkUnlinkSendsHardPans) {
    auto state = MakeState();
    state.mixer[0].inputLinked[0] = true;
    state.mixer[0].inputLinked[1] = true;
    state.mixer[0].inputPans[0] = 0;
    state.mixer[0].inputPans[1] = 0;
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::MixerLink}, false);
    ASSERT_TRUE(write.has_value());
    ASSERT_EQ(write->frames.size(), 2U);
    EXPECT_EQ(write->frames[0][Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MixInputPan));
    EXPECT_EQ(write->frames[0][7], 0);
    EXPECT_EQ(write->frames[0][8], 0);
    EXPECT_EQ(static_cast<int8_t>(write->frames[0][9]), -20);
    EXPECT_EQ(write->frames[1][Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MixInputPan));
    EXPECT_EQ(write->frames[1][8], 1);
    EXPECT_EQ(static_cast<int8_t>(write->frames[1][9]), 20);
    EXPECT_FALSE(write->desired.mixer[0].inputLinked[0]);
    EXPECT_FALSE(write->desired.mixer[0].inputLinked[1]);
    EXPECT_EQ(write->desired.mixer[0].inputPans[0], -20);
    EXPECT_EQ(write->desired.mixer[0].inputPans[1], 20);
}

TEST(OrpheusControlWriteTests, MixerLinkJoinSendsBalance) {
    auto state = MakeState();
    state.mixer[0].inputPans[0] = -20;
    state.mixer[0].inputPans[1] = 20;
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::MixerLink}, true);
    ASSERT_TRUE(write.has_value());
    ASSERT_GE(write->frames.size(), 1U);
    EXPECT_EQ(write->frames[0][Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MixInputBalance));
    EXPECT_EQ(write->frames[0][8], 0);
    EXPECT_EQ(static_cast<int8_t>(write->frames[0][9]), 0);
    EXPECT_TRUE(write->desired.mixer[0].inputLinked[0]);
    EXPECT_TRUE(write->desired.mixer[0].inputLinked[1]);
    EXPECT_EQ(write->desired.mixer[0].inputPans[0], 0);
    EXPECT_EQ(write->desired.mixer[0].inputPans[1], 0);
}

TEST(OrpheusControlWriteTests, MixerLinkRejectsDawPair) {
    auto state = MakeState();
    state.mixer[0].inputLinked[10] = true;
    state.mixer[0].inputLinked[11] = true;
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::MixerLink + 10}, false);
    EXPECT_FALSE(write.has_value());
}

TEST(OrpheusControlWriteTests, MixerPanUsesEvenLinkOnly) {
    auto state = MakeState();
    state.mixer[0].inputLinked[0] = false;
    state.mixer[0].inputLinked[1] = true;
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::MixerPan + 1}, 12.0);
    ASSERT_TRUE(write.has_value());
    ASSERT_EQ(write->frames.size(), 1U);
    EXPECT_EQ(write->frames[0][Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MixInputPan));
    EXPECT_EQ(write->frames[0][8], 1);
    EXPECT_EQ(static_cast<int8_t>(write->frames[0][9]), 12);
}

TEST(OrpheusControlWriteTests, MixerBusMuteWrite) {
    const auto state = MakeState();
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::MixerBusMute + 2}, true);
    ASSERT_TRUE(write.has_value());
    ASSERT_EQ(write->frames.size(), 1U);
    EXPECT_EQ(write->frames[0][Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::MixMute));
    EXPECT_EQ(write->frames[0][7], 2);
    EXPECT_EQ(write->frames[0][8], 1);
    EXPECT_TRUE(write->desired.mixer[2].masterMute);
}

TEST(OrpheusControlWriteTests, DigitalSampleRateWrite) {
    const auto state = MakeState();
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::DigitalSampleRate}, int64_t{4});
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::Digital);
    ASSERT_EQ(write->frames.size(), 1U);
    EXPECT_EQ(write->frames[0][Wire::kCommandOffset], static_cast<uint8_t>(OrpheusCommand::DigitalSampleRate));
    EXPECT_EQ(write->frames[0][7], 4);
    EXPECT_EQ(write->desired.digital.sampleRate, 4);
}

TEST(OrpheusControlWriteTests, ClockSourceWriteHandlesSignalSource) {
    const auto state = MakeState();
    const auto write = BuildOrpheusParameterWrite(state, AM::ParameterId{OrpheusControl::ClockSource}, int64_t(OrpheusSyncSource::WordClock));
    ASSERT_TRUE(write.has_value());
    EXPECT_EQ(write->group, OrpheusControlGroup::ClockSource);
    ASSERT_EQ(write->frames.size(), 1U);
    const auto& frame = write->frames[0];
    EXPECT_EQ(frame[2], 0x1A); // SIGNAL SOURCE
    EXPECT_EQ(write->desired.syncSource, OrpheusSyncSource::WordClock);
}
