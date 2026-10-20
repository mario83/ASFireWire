// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 ASFireWire Project

#include "Audio/Protocols/Prism/Orpheus/OrpheusControlModel.hpp"
#include "Audio/Controls/CoreAudioProjection.hpp"
#include "Audio/Model/Topology/Validate.hpp"
#include <gtest/gtest.h>
#include <algorithm>

namespace {

using namespace ASFW::Audio::Prism::Orpheus;
namespace C = ASFW::Audio::Controls;
namespace AM = ASFW::AudioModel;

OrpheusControlsState MakeDefaultState() {
    OrpheusControlsState state;
    state.unit.masterVolume = -2560; // -10 dB in 1/256 dB
    state.unit.adatMode = 3;         // Send/Return
    state.syncSource = OrpheusSyncSource::Local;

    // Channels 0..1: Mic (XLR) / Instrument (jack)
    state.analog[0].inputType = static_cast<uint8_t>(OrpheusInputType::Mic);
    state.analog[0].micGain = 45;
    state.analog[0].phantom = true;

    state.analog[1].inputType = static_cast<uint8_t>(OrpheusInputType::Instrument);
    state.analog[1].instrumentGain = 20;

    // Channels 2..3: Mic (XLR) default
    state.analog[2].inputType = static_cast<uint8_t>(OrpheusInputType::Mic);
    state.analog[2].micGain = 30;
    state.analog[2].phantom = true;

    state.analog[3].inputType = static_cast<uint8_t>(OrpheusInputType::Mic);
    state.analog[3].micGain = 25;

    // Channels 4..7: Line
    for (size_t ch = 4; ch < 8; ++ch) {
        state.analog[ch].lineInputLevel = 1; // +4 dBu
    }

    return state;
}

TEST(OrpheusControlModelTests, SilentHardwareStateValidates) {
    OrpheusControlsState state;
    state.mixer[0].inputGains[3] = Scales::kSilent;
    state.unit.meterBrightness = 0;
    state.analog[0].filter = 9; // unknown wire value; model clamps to Flat
    const auto model = BuildOrpheusControls(state, 1, 0);
    const auto topValidation = AM::validate(model.topology);
    ASSERT_TRUE(topValidation) << topValidation.error().message;
    const auto stateValidation = AM::validateState(model.topology, model.state);
    ASSERT_TRUE(stateValidation) << stateValidation.error().message;
    EXPECT_EQ(std::get<double>(model.state.parameters.at(AM::ParameterId{OrpheusControl::OutputVolume}).value),
              static_cast<double>(Scales::kSilent) / 256.0);
    EXPECT_EQ(std::get<int64_t>(model.state.parameters.at(AM::ParameterId{OrpheusControl::HighPassFilter}).value), 0);
}

TEST(OrpheusControlModelTests, TopologyAndObservedStateValidate) {
    const auto model = BuildOrpheusControls(MakeDefaultState(), 1, 100);
    const auto topValidation = AM::validate(model.topology);
    ASSERT_TRUE(topValidation) << topValidation.error().message;

    const auto stateValidation = AM::validateState(model.topology, model.state);
    ASSERT_TRUE(stateValidation) << stateValidation.error().message;

    EXPECT_EQ(model.family, "orpheus");
    EXPECT_EQ(model.sequence, 100U);
}

TEST(OrpheusControlModelTests, CoreAudioProjectionPublishesExactlyFourPhantomControls) {
    const auto model = BuildOrpheusControls(MakeDefaultState(), 1, 0);
    const auto controls = C::ProjectCoreAudioControls(model.topology, model.state);

    std::vector<C::CoreAudioControl> phantoms;
    for (const auto& c : controls) {
        if (c.classId == uint32_t{'phan'} && c.scope == uint32_t{'inpt'}) {
            phantoms.push_back(c);
        }
    }

    ASSERT_EQ(phantoms.size(), 4U);
    EXPECT_EQ(phantoms[0].element, 1U);
    EXPECT_EQ(phantoms[1].element, 2U);
    EXPECT_EQ(phantoms[2].element, 3U);
    EXPECT_EQ(phantoms[3].element, 4U);

    // Channels 5..8 do not have phantom power
    for (const auto& p : phantoms) {
        EXPECT_LE(p.element, 4U);
    }
}

TEST(OrpheusControlModelTests, CoreAudioProjectionMasterVolumeLandsOnElementZero) {
    const auto model = BuildOrpheusControls(MakeDefaultState(), 1, 0);
    const auto controls = C::ProjectCoreAudioControls(model.topology, model.state);

    const auto vol = std::ranges::find_if(controls, [](const auto& c) {
        return c.parameter == AM::ParameterId{OrpheusControl::OutputVolume};
    });

    ASSERT_NE(vol, controls.end());
    EXPECT_EQ(vol->scope, uint32_t{'outp'});
    EXPECT_EQ(vol->element, 0U); // Promoted to Master!
    EXPECT_EQ(vol->classId, uint32_t{'vlme'});
}

TEST(OrpheusControlModelTests, PreampWritesStayApplicableIndependentOfJackDetect) {
    auto state = MakeDefaultState();
    state.analog[2].inputType = static_cast<uint8_t>(OrpheusInputType::Line);
    const auto model = BuildOrpheusControls(state, 1, 0);
    EXPECT_TRUE(model.state.parameters.at(AM::ParameterId{OrpheusControl::Gain + 0}).applicable);
    EXPECT_TRUE(model.state.parameters.at(AM::ParameterId{OrpheusControl::Gain + 2}).applicable);
    EXPECT_TRUE(model.state.parameters.at(AM::ParameterId{OrpheusControl::Phantom + 2}).applicable);
    EXPECT_EQ(std::get<int64_t>(model.state.parameters.at(AM::ParameterId{OrpheusControl::AnalogInputType + 2}).value), 0);
    EXPECT_EQ(std::get<double>(model.state.parameters.at(AM::ParameterId{OrpheusControl::FirmwareVersion}).value),
              (1 << 8) | 6);
}

TEST(OrpheusControlModelTests, CompositeInputTypesArePublishedForPreampChannels) {
    const auto model = BuildOrpheusControls(MakeDefaultState(), 1, 0);
    const auto types = C::ProjectInputTypes(model.topology, model.state);

    ASSERT_EQ(types.size(), 4U); // Ch 1..4 have composite routers
    EXPECT_EQ(types[0].element, 1U);
    EXPECT_EQ(types[1].element, 2U);
    EXPECT_EQ(types[2].element, 3U);
    EXPECT_EQ(types[3].element, 4U);

    // AI 1/2 expose XLR vs instrument via the router; line +4/-10 is a separate level.
    EXPECT_GE(types[0].choices.size(), 2U);
}

TEST(OrpheusControlModelTests, MixerCrosspointCountMatchesSixBusesByTwelveInputs) {
    const auto model = BuildOrpheusControls(MakeDefaultState(), 1, 0);
    const auto node = std::ranges::find_if(model.topology.nodes, [](const auto& n) {
        return n.name == "Hardware Mixer";
    });

    ASSERT_NE(node, model.topology.nodes.end());
    const auto* mixer = std::get_if<AM::MixerNode>(&node->body);
    ASSERT_NE(mixer, nullptr);
    EXPECT_EQ(mixer->inputs.size(), 12U);
    EXPECT_EQ(mixer->outputs.size(), 6U);
    EXPECT_EQ(mixer->crosspoints.size(), 72U);
}

TEST(OrpheusControlModelTests, MixerDawPairFollowsTheOutputBus) {
    const auto model = BuildOrpheusControls(MakeDefaultState(), 1, 0);
    const auto nameOf = [&](uint32_t id) {
        const auto found = std::ranges::find_if(model.topology.parameters, [&](const auto& p) {
            return p.id.value == id;
        });
        return found == model.topology.parameters.end() ? std::string{} : found->name;
    };
    EXPECT_NE(nameOf(OrpheusControl::Mixer + 10).find("DAW 1"), std::string::npos);
    EXPECT_NE(nameOf(OrpheusControl::Mixer + 12 + 10).find("DAW 3"), std::string::npos);
    EXPECT_NE(nameOf(OrpheusControl::Mixer + 12 + 11).find("DAW 4"), std::string::npos);
}

} // namespace
