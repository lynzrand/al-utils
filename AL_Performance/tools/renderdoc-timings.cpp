#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#include "renderdoc_replay.h"

REPLAY_PROGRAM_MARKER()

struct Work
{
    double milliseconds = 0;
    unsigned draws = 0;
    unsigned dispatches = 0;
    unsigned timed = 0;

    void Add(const Work& work)
    {
        milliseconds += work.milliseconds;
        draws += work.draws;
        dispatches += work.dispatches;
        timed += work.timed;
    }
};

struct TimedAction
{
    unsigned eventId;
    std::string name;
    Work work;
};

struct RenderTargetUse
{
    unsigned colorDraws = 0;
    unsigned depthDraws = 0;
    double colorDrawMilliseconds = 0;
    double depthDrawMilliseconds = 0;
    unsigned firstEvent = 0;
    std::string firstPass;
};

using EventTimings = std::map<unsigned, double>;
using RenderTargets = std::map<ResourceId, RenderTargetUse>;
using ViewportBounds = std::array<float, 4>;

struct DrawBinding
{
    ResourceId pipeline;
    ViewportBounds viewport{};
};

using DrawBindings = std::map<unsigned, DrawBinding>;

struct ReplayComparison
{
    unsigned eventId = 0;
    const char* bytecode = nullptr;
};

static DrawBindings GetDrawBindings(IReplayController& controller);

struct TextureReadback
{
    ResourceId resource;
    unsigned eventId = 0;
    unsigned width = 0;
    unsigned height = 0;
    unsigned samples = 0;
    ResourceFormat format;

    uint64_t PixelCount() const { return uint64_t(width) * height; }
    bool HasHalfComponents() const
    {
        return format.type == ResourceFormatType::Regular && format.compType == CompType::Float &&
            format.compByteWidth == 2 && format.compCount == 4;
    }
    bool CanReadHdr() const { return HasHalfComponents() || format.type == ResourceFormatType::R11G11B10; }

    bytebuf Read(IReplayController& controller, bool allowMultisampled = false) const
    {
        if (!eventId || (samples != 1 && !allowMultisampled)) return {};
        controller.SetFrameEvent(eventId, true);
        return controller.GetTextureData(resource, {});
    }
};

static TextureReadback MakeReadback(IReplayController& controller, ResourceId resource, unsigned eventId)
{
    if (resource == ResourceId::Null()) return {};
    for (const auto& texture : controller.GetTextures())
    {
        if (texture.resourceId != resource) continue;
        return {resource, eventId, texture.width, texture.height, texture.msSamp, texture.format};
    }
    return {};
}

static const ShaderReflection* BoundShader(IReplayController& controller, bool compute, ResourceId& pipeline)
{
    if (const auto* d3d12 = controller.GetD3D12PipelineState())
    {
        pipeline = d3d12->pipelineResourceId;
        return (compute ? d3d12->computeShader : d3d12->pixelShader).reflection;
    }
    if (const auto* d3d11 = controller.GetD3D11PipelineState())
        return (compute ? d3d11->computeShader : d3d11->pixelShader).reflection;
    return nullptr;
}

static EventTimings MeasureEvents(IReplayController& controller)
{
    EventTimings timings;
    const auto counter = GPUCounter::EventGPUDuration;
    const auto available = controller.EnumerateCounters();
    if (std::find(available.begin(), available.end(), counter) == available.end()) return timings;

    for (const auto& result : controller.FetchCounters({counter}))
    {
        if (std::isfinite(result.value.d) && result.value.d >= 0)
            timings.emplace(result.eventId, result.value.d * 1000.0);
    }
    return timings;
}

static void RecordTargetUse(RenderTargets& targets, ResourceId id, const TimedAction& action, bool depth)
{
    if (id == ResourceId::Null()) return;

    auto& use = targets[id];
    if (use.firstEvent == 0)
    {
        use.firstEvent = action.eventId;
        use.firstPass = action.name;
    }
    if (depth)
    {
        ++use.depthDraws;
        use.depthDrawMilliseconds += action.work.milliseconds;
    }
    else
    {
        ++use.colorDraws;
        use.colorDrawMilliseconds += action.work.milliseconds;
    }
}

static Work CollectTimings(const rdcarray<ActionDescription>& actions, const SDFile& structured,
    const EventTimings& timings, const std::string& parent, std::vector<TimedAction>& markers,
    std::vector<TimedAction>& events, RenderTargets& targets)
{
    Work total;
    for (const auto& action : actions)
    {
        const std::string name = action.GetName(structured).c_str();
        const std::string path = parent.empty() ? name : parent + " / " + name;
        if (!action.children.empty())
        {
            // Children own the timing. Summing a marker's timing as well would count its work twice.
            Work children = CollectTimings(action.children, structured, timings, path, markers, events, targets);
            markers.push_back({action.eventId, path, children});
            total.Add(children);
            continue;
        }

        Work work;
        work.draws = (action.flags & ActionFlags::Drawcall) != ActionFlags::NoFlags;
        constexpr auto dispatch = ActionFlags::Dispatch | ActionFlags::MeshDispatch | ActionFlags::DispatchRay;
        work.dispatches = (action.flags & dispatch) != ActionFlags::NoFlags;
        const auto timing = timings.find(action.eventId);
        if (timing != timings.end())
        {
            work.milliseconds = timing->second;
            work.timed = 1;
            events.push_back({action.eventId, path, work});
        }
        if (work.draws)
        {
            const TimedAction targetAction{action.eventId, parent, work};
            for (ResourceId target : action.outputs)
                RecordTargetUse(targets, target, targetAction, false);
            RecordTargetUse(targets, action.depthOut, targetAction, true);
        }
        total.Add(work);
    }
    return total;
}

static void PrintLargest(std::vector<TimedAction>& actions, size_t limit)
{
    std::stable_sort(actions.begin(), actions.end(), [](const auto& left, const auto& right)
    {
        return left.work.milliseconds > right.work.milliseconds;
    });

    std::cout << "    event     GPU ms     draws    dispatches  action\n";
    for (size_t index = 0; index < std::min(limit, actions.size()); ++index)
    {
        const auto& action = actions[index];
        std::cout << std::setw(9) << action.eventId << std::setw(11) << action.work.milliseconds
                  << std::setw(10) << action.work.draws << std::setw(14) << action.work.dispatches
                  << "  " << action.name << '\n';
    }
}

static void PrintRenderTargets(IReplayController& controller, const RenderTargets& targets)
{
    std::map<ResourceId, std::string> names;
    for (const auto& resource : controller.GetResources())
    {
        if (targets.find(resource.resourceId) != targets.end())
            names.emplace(resource.resourceId, resource.name.c_str());
    }

    std::cout << "Draw-bound render targets. A draw can appear under several color/depth targets.\n";
    for (const auto& texture : controller.GetTextures())
    {
        const auto target = targets.find(texture.resourceId);
        if (target == targets.end()) continue;

        const auto& use = target->second;
        const auto name = names.find(texture.resourceId);
        std::cout << "    " << texture.width << 'x' << texture.height << ' ' << texture.msSamp << "x MSAA"
                  << "   color draws " << use.colorDraws << " (" << use.colorDrawMilliseconds << " ms)"
                  << "   depth draws " << use.depthDraws << " (" << use.depthDrawMilliseconds << " ms)"
                  << "   event " << use.firstEvent << "   " << (name == names.end() ? "" : name->second)
                  << "   " << use.firstPass << '\n';
    }
}

static bool ExportShaders(IReplayController& controller, const std::vector<TimedAction>& events,
    const std::filesystem::path& directory, bool allPipelines)
{
    std::filesystem::create_directories(directory);
    std::ofstream index(directory / "shaders.tsv");
    if (!index) return false;
    index << "event\tGPU_ms\tstage\tbytecode_file\tpass\n";

    // Replay each selected event to resolve the bound shader. The duration belongs to the draw or dispatch.
    // A limited set avoids re-running the frame to inspect every low-cost draw.
    std::map<ResourceId, std::string> exported;
    std::set<ResourceId> pipelines;
    const auto bindings = allPipelines ? GetDrawBindings(controller) : DrawBindings{};
    if (allPipelines && bindings.empty()) return false;
    unsigned resolved = 0;
    for (const auto& event : events)
    {
        if (event.work.draws == 0 && event.work.dispatches == 0) continue;
        if (allPipelines)
        {
            const auto binding = bindings.find(event.eventId);
            if (binding == bindings.end() || !pipelines.insert(binding->second.pipeline).second) continue;
        }
        else if (++resolved > 20) break;
        const bool compute = event.work.dispatches != 0;
        controller.SetFrameEvent(event.eventId, false);

        ResourceId pipeline;
        const auto* shader = BoundShader(controller, compute, pipeline);
        if (!shader || shader->rawBytes.empty()) continue;

        auto [file, firstUse] = exported.try_emplace(shader->resourceId);
        if (firstUse)
        {
            const std::string stem = std::to_string(event.eventId) + (compute ? "-cs" : "-ps");
            file->second = stem + (shader->encoding == ShaderEncoding::DXBC ? ".dxbc"
                : shader->encoding == ShaderEncoding::DXIL ? ".dxil" : ".bin");
            std::ofstream bytecode(directory / file->second, std::ios::binary);
            std::ofstream disassembly(directory / (stem + ".txt"));
            if (!bytecode || !disassembly) return false;
            bytecode.write(reinterpret_cast<const char*>(shader->rawBytes.data()), shader->rawBytes.size());
            disassembly << controller.DisassembleShader(pipeline, shader, {}).c_str();
            if (!bytecode || !disassembly) return false;
        }
        index << event.eventId << '\t' << event.work.milliseconds << '\t' << (compute ? "CS" : "PS") << '\t'
              << file->second << '\t' << event.name << '\n';
    }
    return static_cast<bool>(index);
}

static const ActionDescription* FindAction(const rdcarray<ActionDescription>& actions, unsigned eventId)
{
    for (const auto& action : actions)
    {
        if (action.eventId == eventId) return &action;
        if (const auto* child = FindAction(action.children, eventId)) return child;
    }
    return nullptr;
}

static const ActionDescription* FindPresent(const rdcarray<ActionDescription>& actions)
{
    for (size_t index = actions.size(); index > 0; --index)
    {
        const auto& action = actions[index - 1];
        if (const auto* child = FindPresent(action.children)) return child;
        if ((action.flags & ActionFlags::Present) != ActionFlags::NoFlags) return &action;
    }
    return nullptr;
}

static void CollectDrawBindings(const rdcarray<ActionDescription>& actions, const SDFile& structured,
    std::map<ResourceId, DrawBinding>& bindingsByCommandList, DrawBindings& result)
{
    for (const auto& action : actions)
    {
        ResourceId commandList;
        for (const auto& event : action.events)
        {
            if (event.chunkIndex >= structured.chunks.size()) continue;
            const auto* chunk = structured.chunks[event.chunkIndex];
            const auto* command = chunk->FindChild("pCommandList");
            if (!command) continue;
            commandList = command->AsResourceId();
            auto& binding = bindingsByCommandList[commandList];

            // D3D12 Reset starts each command list's state. SetPipelineState replaces it.
            if (chunk->name == "ID3D12GraphicsCommandList::Reset")
            {
                const auto* initial = chunk->FindChild("pInitialState");
                binding = {initial ? initial->AsResourceId() : ResourceId::Null(), {}};
            }
            if (chunk->name == "ID3D12GraphicsCommandList::SetPipelineState")
            {
                const auto* bound = chunk->FindChild("pPipelineState");
                binding.pipeline = bound ? bound->AsResourceId() : ResourceId::Null();
            }
            if (chunk->name == "ID3D12GraphicsCommandList::RSSetViewports")
            {
                binding.viewport = {};
                const auto* viewports = chunk->FindChild("pViewports");
                if (!viewports || viewports->NumChildren() != 1) continue;
                const auto* viewport = viewports->GetChild(0);
                constexpr const char* keys[] = {"TopLeftX", "TopLeftY", "Width", "Height"};
                for (size_t index = 0; index < binding.viewport.size(); ++index)
                {
                    if (const auto* element = viewport->FindChild(keys[index]))
                        binding.viewport[index] = element->AsFloat();
                }
            }
        }
        constexpr auto drawOrDispatch = ActionFlags::Drawcall | ActionFlags::Dispatch;
        if ((action.flags & drawOrDispatch) != ActionFlags::NoFlags)
        {
            const auto binding = bindingsByCommandList.find(commandList);
            if (binding != bindingsByCommandList.end()) result.emplace(action.eventId, binding->second);
        }
        CollectDrawBindings(action.children, structured, bindingsByCommandList, result);
    }
}

static DrawBindings GetDrawBindings(IReplayController& controller)
{
    DrawBindings draws;
    std::map<ResourceId, DrawBinding> bindingsByCommandList;
    CollectDrawBindings(controller.GetRootActions(), controller.GetStructuredFile(), bindingsByCommandList, draws);
    return draws;
}

static std::set<unsigned> ShaderUsers(IReplayController& controller, ResourceId shader)
{
    if (!controller.GetD3D12PipelineState()) return {};

    std::set<ResourceId> pipelines;
    for (const auto& resource : controller.GetResources())
    {
        if (resource.resourceId != shader) continue;
        pipelines.insert(resource.derivedResources.begin(), resource.derivedResources.end());
        break;
    }
    const auto draws = GetDrawBindings(controller);

    std::set<unsigned> users;
    for (const auto& [event, binding] : draws)
    {
        if (pipelines.count(binding.pipeline)) users.insert(event);
    }
    std::cout << "D3D12 pipeline linkage covers " << draws.size() << " draws/dispatches, shader used by "
              << pipelines.size() << " pipelines.\n";
    return users;
}

static void PrintDepthViewports(IReplayController& controller, const RenderTargets& targets,
    const EventTimings& timings)
{
    if (!controller.GetD3D12PipelineState()) return;
    const auto bindings = GetDrawBindings(controller);
    for (const auto& [resource, target] : targets)
    {
        if (target.depthDraws == 0 || target.colorDraws != 0) continue;
        std::map<ViewportBounds, Work> viewports;
        for (const auto& use : controller.GetUsage(resource))
        {
            if (use.usage != ResourceUsage::DepthStencilTarget) continue;
            const auto bound = bindings.find(use.eventId);
            if (bound == bindings.end()) continue;
            auto& work = viewports[bound->second.viewport];
            ++work.draws;
            const auto duration = timings.find(use.eventId);
            if (duration != timings.end()) work.milliseconds += duration->second;
        }
        if (viewports.empty()) continue;
        std::cout << "Depth viewports for target first used at event " << target.firstEvent << '\n';
        for (const auto& [viewport, work] : viewports)
        {
            std::cout << "    (" << viewport[0] << ", " << viewport[1] << ") " << viewport[2] << 'x' << viewport[3]
                      << "  " << work.draws << " draws  " << work.milliseconds << " ms\n";
        }
    }
}

static bytebuf ReadConstantRegister(IReplayController& controller, unsigned binding, unsigned index)
{
    const auto* state = controller.GetD3D12PipelineState();
    if (!state) return {};

    constexpr auto visibility = ShaderStageMask::Pixel;
    const auto offset = uint64_t(index) * 16;
    bytebuf value;
    for (const auto& param : state->rootSignature.parameters)
    {
        if ((param.visibility & visibility) == ShaderStageMask::Unknown) continue;
        if (param.reg == binding && param.space == 0)
        {
            if (param.constants.size() >= offset + 16)
            {
                value.assign(param.constants.data() + offset, 16);
                break;
            }
            if (param.descriptor.type == DescriptorType::ConstantBuffer && param.descriptor.resource != ResourceId::Null())
            {
                value = controller.GetBufferData(param.descriptor.resource, param.descriptor.byteOffset + offset, 16);
                break;
            }
        }
        for (const auto& range : param.tableRanges)
        {
            if (range.category != DescriptorCategory::ConstantBlock || range.space != 0 ||
                binding < range.baseRegister || binding - range.baseRegister >= range.count) continue;

            DescriptorRange descriptors;
            descriptors.type = DescriptorType::ConstantBuffer;
            descriptors.offset = param.heapByteOffset + range.tableByteOffset + binding - range.baseRegister;
            const auto matches = controller.GetDescriptors(param.heap, {descriptors});
            if (matches.empty() || matches[0].resource == ResourceId::Null()) continue;
            value = controller.GetBufferData(matches[0].resource, matches[0].byteOffset + offset, 16);
            break;
        }
        if (!value.empty()) break;
    }
    return value;
}

static void PrintConstantValue(unsigned binding, unsigned index, const bytebuf& value)
{
    std::cout << " cb" << binding << '[' << index << "]=";
    if (value.size() != 16)
    {
        std::cout << "unavailable";
        return;
    }
    float components[4];
    std::memcpy(components, value.data(), 16);
    std::cout << '[' << components[0] << ',' << components[1] << ',' << components[2] << ',' << components[3] << ']';
}

static void PrintConstantRegister(IReplayController& controller, unsigned binding, unsigned index)
{
    PrintConstantValue(binding, index, ReadConstantRegister(controller, binding, index));
}

static int InspectMapLights(IReplayController& controller, unsigned eventId)
{
    const auto* action = FindAction(controller.GetRootActions(), eventId);
    if (!action || (action->flags & ActionFlags::Drawcall) == ActionFlags::NoFlags)
    {
        std::cerr << "Select a graphics draw in this capture.\n";
        return 1;
    }
    controller.SetFrameEvent(eventId, false);
    const auto header = ReadConstantRegister(controller, 10, 0);
    uint32_t count = 0;
    if (header.size() != 16)
    {
        std::cerr << "The draw has no readable b10 constant buffer.\n";
        return 1;
    }
    std::memcpy(&count, header.data(), sizeof(count));
    if (count > 32)
    {
        std::cerr << "b10 does not contain the authored map light list.\n";
        return 1;
    }
    std::cout << "Authored map directionals at event " << eventId << ": " << count << '\n';
    std::cout << std::hexfloat;
    for (unsigned index = 0; index < count; ++index)
    {
        const unsigned slot = 1 + 2 * index;
        const auto direction = ReadConstantRegister(controller, 10, slot);
        const auto color = ReadConstantRegister(controller, 10, slot + 1);
        if (direction.size() != 16 || color.size() != 16)
        {
            std::cerr << "An authored directional record is missing.\n";
            return 1;
        }
        PrintConstantValue(10, slot, direction);
        PrintConstantValue(10, slot + 1, color);
        std::cout << '\n';
    }
    return 0;
}

static EventTimings MedianTimings(const std::vector<EventTimings>& samples)
{
    EventTimings medians;
    for (const auto& [event, first] : samples.front())
    {
        std::vector<double> values = {first};
        for (size_t sample = 1; sample < samples.size(); ++sample)
        {
            const auto value = samples[sample].find(event);
            if (value != samples[sample].end()) values.push_back(value->second);
        }
        std::sort(values.begin(), values.end());
        medians[event] = values[values.size() / 2];
    }
    return medians;
}

static double SumTimings(const EventTimings& timings, const std::set<unsigned>* subset = nullptr)
{
    double total = 0;
    for (const auto& [event, duration] : timings)
    {
        if (!subset || subset->count(event)) total += duration;
    }
    return total;
}

static void PrintImageDiff(const bytebuf& baseline, const bytebuf& variant,
    const TextureReadback& target, const char* label)
{
    const uint64_t pixelCount = target.PixelCount();
    if (baseline.empty() || baseline.size() != variant.size() || !pixelCount || baseline.size() % pixelCount)
    {
        std::cout << label << " unavailable (" << baseline.size() << '/' << variant.size() << " readback bytes).\n";
        return;
    }
    const auto pixelBytes = static_cast<size_t>(baseline.size() / pixelCount);

    uint64_t changedPixels = 0;
    uint64_t totalAbsoluteDelta = 0;
    unsigned largestDelta = 0;
    for (size_t pixel = 0; pixel < baseline.size(); pixel += pixelBytes)
    {
        bool changed = false;
        for (size_t component = 0; component < pixelBytes; ++component)
        {
            const unsigned delta = std::abs(int(baseline[pixel + component]) - int(variant[pixel + component]));
            changed |= delta != 0;
            largestDelta = std::max(largestDelta, delta);
            totalAbsoluteDelta += delta;
        }
        changedPixels += changed;
    }
    std::cout << label << "  " << changedPixels << '/' << pixelCount << " changed texels, " << pixelBytes
              << " bytes per texel";
    if (target.format.type == ResourceFormatType::Regular && target.format.compByteWidth == 1)
        std::cout << ", max component delta " << largestDelta << ", mean absolute component delta "
                  << double(totalAbsoluteDelta) / baseline.size();
    std::cout << '\n';
}

static void PrintDrawHighlightStats(const bytebuf& prior, const bytebuf& stock, const bytebuf& changed,
    const TextureReadback& target)
{
    const bool half = target.HasHalfComponents();
    const size_t pixelBytes = half ? 4 * sizeof(uint16_t) : sizeof(uint32_t);
    if (!target.CanReadHdr() || prior.size() != target.PixelCount() * pixelBytes ||
        prior.size() != stock.size() || prior.size() != changed.size() || prior.empty())
        return;

    // Normalize both formats into the binary16 exponent and mantissa layout.
    // Positive finite values are ordered by their raw bits.
    const auto peak = [half](const byte* pixel) -> uint16_t
    {
        if (!half)
        {
            uint32_t value;
            std::memcpy(&value, pixel, sizeof(value));
            return static_cast<uint16_t>(std::max({(value & 0x7ff) << 4,
                ((value >> 11) & 0x7ff) << 4, (value >> 22) << 5}));
        }
        uint16_t result = 0;
        for (unsigned channel = 0; channel < 3; ++channel)
        {
            uint16_t value;
            std::memcpy(&value, pixel + channel * sizeof(value), sizeof(value));
            if (!(value & 0x8000)) result = std::max(result, value);
        }
        return result;
    };
    // 0.75, 1.0 and 2.0 in binary16.
    constexpr std::array<uint16_t, 3> thresholds = {0x3a00, 0x3c00, 0x4000};
    std::array<uint64_t, thresholds.size()> oldCounts{}, newCounts{};
    uint64_t affected = 0;
    for (size_t offset = 0; offset < prior.size(); offset += pixelBytes)
    {
        if (std::memcmp(prior.data() + offset, stock.data() + offset, pixelBytes) == 0 &&
            std::memcmp(prior.data() + offset, changed.data() + offset, pixelBytes) == 0)
            continue;
        ++affected;
        const auto a = peak(stock.data() + offset);
        const auto b = peak(changed.data() + offset);
        for (size_t i = 0; i < thresholds.size(); ++i)
        {
            oldCounts[i] += a >= thresholds[i];
            newCounts[i] += b >= thresholds[i];
        }
    }
    std::cout << "Linear HDR at sample 0 for " << affected << " pixels changed by the draw"
              << " in either version (baseline / replacement)\n";
    std::cout << "  Peak >= 0.75: " << oldCounts[0] << " / " << newCounts[0] << '\n'
              << "  Peak >= 1.0:  " << oldCounts[1] << " / " << newCounts[1] << '\n'
              << "  Peak >= 2.0:  " << oldCounts[2] << " / " << newCounts[2] << '\n';
}

static int CompareShader(IReplayController& controller, const ReplayComparison& comparison)
{
    const auto& actions = controller.GetRootActions();
    const auto* action = FindAction(actions, comparison.eventId);
    if (!action)
    {
        std::cerr << "The requested event is absent from the capture.\n";
        return 1;
    }
    const bool compute = (action->flags & ActionFlags::Dispatch) != ActionFlags::NoFlags;
    if (!compute && (action->flags & ActionFlags::Drawcall) == ActionFlags::NoFlags)
    {
        std::cerr << "Select a graphics draw or compute dispatch.\n";
        return 1;
    }

    controller.SetFrameEvent(comparison.eventId, false);
    ResourceId pipeline;
    const auto* shader = BoundShader(controller, compute, pipeline);
    if (!shader)
    {
        std::cerr << "No pixel or compute shader was bound at the requested event.\n";
        return 1;
    }
    const ResourceId original = shader->resourceId;
    auto users = ShaderUsers(controller, original);
    if (!users.count(comparison.eventId))
    {
        std::cerr << "Could not verify shader event membership. Reporting the selected event only.\n";
        users = {comparison.eventId};
    }
    const auto encoding = std::filesystem::path(comparison.bytecode).extension() == ".dxil"
        ? ShaderEncoding::DXIL : ShaderEncoding::DXBC;
    std::ifstream file(comparison.bytecode, std::ios::binary | std::ios::ate);
    if (!file || file.tellg() <= 0)
    {
        std::cerr << "Could not read replacement shader bytecode.\n";
        return 1;
    }
    bytebuf bytecode;
    bytecode.resize(static_cast<size_t>(file.tellg()));
    file.seekg(0);
    file.read(reinterpret_cast<char*>(bytecode.data()), bytecode.size());
    if (!file) return 1;

    auto [replacement, messages] = controller.BuildTargetShader(shader->entryPoint, encoding, std::move(bytecode),
        {}, compute ? ShaderStage::Compute : ShaderStage::Pixel);
    if (!messages.empty()) std::cerr << messages.c_str() << '\n';
    if (replacement == ResourceId::Null())
    {
        std::cerr << "RenderDoc could not create the replacement shader.\n";
        return 1;
    }

    const auto* present = FindPresent(actions);
    const auto output = present ? MakeReadback(controller, present->copyDestination, present->eventId) : TextureReadback{};
    ResourceId actionOutput;
    for (ResourceId id : action->outputs)
    {
        if (id == ResourceId::Null()) continue;
        actionOutput = id;
        break;
    }
    const auto color = MakeReadback(controller, actionOutput, action->eventId);
    auto priorColor = color;
    priorColor.eventId = action->previousAction ? action->previousAction->eventId : 0;

    const ResourceId depthResource = action->depthOut;
    unsigned depthEvent = 0;
    if (depthResource != ResourceId::Null())
    {
        for (const auto& use : controller.GetUsage(depthResource))
        {
            if (use.usage == ResourceUsage::DepthStencilTarget)
                depthEvent = std::max(depthEvent, use.eventId);
        }
    }
    const auto depth = MakeReadback(controller, depthResource, depthEvent);

    // A/B/A brackets expose clock and replay variance. Readbacks stay outside timing runs.
    const auto measure = [&]() -> std::vector<EventTimings>
    {
        MeasureEvents(controller);
        return {MeasureEvents(controller), MeasureEvents(controller), MeasureEvents(controller)};
    };
    const auto beforeRuns = measure();
    const auto before = MedianTimings(beforeRuns);

    // Print the actual constants for the selected draw and hottest verified peers.
    if (!compute && controller.GetD3D12PipelineState())
    {
        std::vector<unsigned> sorted(users.begin(), users.end());
        const auto duration = [&](unsigned event) { return before.count(event) ? before.at(event) : 0.0; };
        std::sort(sorted.begin(), sorted.end(), [&](unsigned a, unsigned b) { return duration(a) > duration(b); });
        const auto print = [&](unsigned event)
        {
            controller.SetFrameEvent(event, false);
            std::cout << "Shader constants for event " << event;
            PrintConstantRegister(controller, 0, 4);
            PrintConstantRegister(controller, 1, 5);
            PrintConstantRegister(controller, 10, 0);
            PrintConstantRegister(controller, 10, 1);
            PrintConstantRegister(controller, 10, 2);
            std::cout << '\n';
        };
        print(comparison.eventId);
        for (size_t index = 0; index < std::min(sorted.size(), size_t(4)); ++index)
        {
            if (sorted[index] != comparison.eventId) print(sorted[index]);
        }
    }

    const auto priorColorData = color.CanReadHdr() ? priorColor.Read(controller, true) : bytebuf{};
    const auto beforeColor = color.Read(controller, color.CanReadHdr());
    const auto beforeDepth = depth.Read(controller);
    const auto beforeImage = output.Read(controller);
    controller.ReplaceResource(original, replacement);
    const auto changedRuns = measure();
    const auto changed = MedianTimings(changedRuns);
    const auto changedColor = color.Read(controller, color.CanReadHdr());
    const auto changedDepth = depth.Read(controller);
    const auto changedImage = output.Read(controller);
    controller.RemoveReplacement(original);
    const auto afterRuns = measure();
    const auto after = MedianTimings(afterRuns);
    const auto afterColor = color.Read(controller, color.CanReadHdr());
    const auto afterDepth = depth.Read(controller);
    const auto afterImage = output.Read(controller);
    controller.FreeTargetResource(replacement);

    std::cout << std::fixed << std::setprecision(5);
    std::cout << "Original, variant, restored GPU event medians (ms, three samples each)\n";
    const auto show = [&](unsigned id)
    {
        if (!before.count(id) || !changed.count(id) || !after.count(id)) return;
        std::cout << "  " << id << '\t' << before.at(id) << '\t' << changed.at(id) << '\t' << after.at(id) << '\n';
    };
    show(comparison.eventId);
    std::cout << "  median-event sum for " << users.size() << " shader draw/dispatch users\t"
              << SumTimings(before, &users) << '\t' << SumTimings(changed, &users) << '\t' << SumTimings(after, &users) << '\n';
    std::cout << "  whole capture median-event sum\t"
              << SumTimings(before) << '\t' << SumTimings(changed) << '\t' << SumTimings(after) << '\n';
    for (size_t sample = 0; sample < beforeRuns.size(); ++sample)
    {
        std::cout << "  shader user sum run " << sample + 1 << '\t' << SumTimings(beforeRuns[sample], &users)
                  << '\t' << SumTimings(changedRuns[sample], &users) << '\t' << SumTimings(afterRuns[sample], &users) << '\n';
    }
    PrintImageDiff(beforeImage, changedImage, output, "Present baseline versus replacement");
    PrintImageDiff(beforeImage, afterImage, output, "Present baseline versus restored");
    if (color.eventId)
    {
        std::cout << "Selected color target " << color.width << 'x' << color.height << ", "
                  << color.format.Name().c_str() << ", " << color.samples << " samples at event " << color.eventId << '\n';
        PrintImageDiff(beforeColor, changedColor, color, "Color baseline versus replacement");
        PrintImageDiff(beforeColor, afterColor, color, "Color baseline versus restored");
        PrintDrawHighlightStats(priorColorData, beforeColor, changedColor, color);
    }
    if (depth.eventId)
    {
        std::cout << "Depth target " << depth.width << 'x' << depth.height << " at last write event " << depth.eventId << '\n';
        PrintImageDiff(beforeDepth, changedDepth, depth, "Depth baseline versus replacement");
        PrintImageDiff(beforeDepth, afterDepth, depth, "Depth baseline versus restored");
    }
    return 0;
}

static int SummarizeCapture(const char* path, const char* shaderDirectory, bool allPipelines,
    const ReplayComparison& comparison, unsigned mapLightEvent)
{
    auto closeCapture = [](ICaptureFile* file) { file->Shutdown(); };
    std::unique_ptr<ICaptureFile, decltype(closeCapture)> capture(RENDERDOC_OpenCaptureFile(), closeCapture);
    const ResultDetails opened = capture->OpenFile(path, "rdc", nullptr);
    if (!opened)
    {
        std::cerr << "Opening capture failed with RenderDoc result " << static_cast<unsigned>(opened.code) << '\n';
        return 1;
    }

    auto [status, replay] = capture->OpenCapture({}, nullptr);
    if (!status)
    {
        std::cerr << "Opening replay failed with RenderDoc result " << static_cast<unsigned>(status.code) << '\n';
        return 1;
    }
    auto closeReplay = [](IReplayController* controller) { controller->Shutdown(); };
    std::unique_ptr<IReplayController, decltype(closeReplay)> controller(replay, closeReplay);

    if (comparison.bytecode) return CompareShader(*controller, comparison);
    if (mapLightEvent) return InspectMapLights(*controller, mapLightEvent);
    MeasureEvents(*controller);
    const auto timings = MedianTimings({MeasureEvents(*controller), MeasureEvents(*controller), MeasureEvents(*controller)});

    std::vector<TimedAction> markers;
    std::vector<TimedAction> events;
    RenderTargets targets;
    const auto& actions = controller->GetRootActions();
    const Work total = CollectTimings(actions, controller->GetStructuredFile(), timings, "", markers, events, targets);

    std::cout << std::fixed << std::setprecision(3);
    std::cout << path << '\n';
    std::cout << "Warmed replay leaf action median sum " << total.milliseconds << " ms across " << total.timed
              << " timed actions, " << total.draws << " draws and " << total.dispatches << " dispatches\n";
    if (events.empty()) std::cout << "Replay provided no GPU timestamps.\n";
    std::cout << "Largest inclusive marker durations. Nested rows overlap.\n";
    PrintLargest(markers, 35);
    std::cout << "Largest individual action durations\n";
    PrintLargest(events, 15);
    PrintRenderTargets(*controller, targets);
    PrintDepthViewports(*controller, targets, timings);
    if (shaderDirectory && !ExportShaders(*controller, events, shaderDirectory, allPipelines))
    {
        std::cerr << "Could not write shader export files in " << shaderDirectory << '\n';
        return 1;
    }
    return 0;
}

int main(int argc, char* argv[])
{
    ReplayComparison comparison;
    unsigned mapLightEvent = 0;
    const bool allPipelines = argc == 4 && std::string(argv[2]) == "--all-pipelines";
    const bool replace = argc == 5 && std::string(argv[2]) == "--replace";
    const bool mapLights = argc == 4 && std::string(argv[2]) == "--map-lights";
    if (replace || mapLights)
    {
        try
        {
            size_t end = 0;
            const auto eventId = std::stoul(argv[3], &end);
            if (argv[3][end] != '\0' || argv[3][0] == '-' || eventId == 0 || eventId > UINT32_MAX)
                throw std::invalid_argument("event ID");
            if (replace) comparison = {static_cast<unsigned>(eventId), argv[4]};
            else mapLightEvent = static_cast<unsigned>(eventId);
        }
        catch (const std::exception&)
        {
            std::cerr << "Invalid event ID.\n";
            return 2;
        }
    }
    else if (!allPipelines && (argc < 2 || argc > 3))
    {
        std::cerr << "Usage: renderdoc-timings <capture.rdc> [shader-output-directory]\n"
                  << "       renderdoc-timings <capture.rdc> --all-pipelines <shader-output-directory>\n"
                  << "       renderdoc-timings <capture.rdc> --map-lights <event-id>\n"
                  << "       renderdoc-timings <capture.rdc> --replace <event-id> <variant.dxbc|variant.dxil>\n";
        return 2;
    }

    GlobalEnvironment environment;
    environment.enumerateGPUs = false;
    RENDERDOC_InitialiseReplay(environment, {});
    const char* shaderDirectory = allPipelines ? argv[3] : (argc == 3 ? argv[2] : nullptr);
    const int result = SummarizeCapture(argv[1], shaderDirectory, allPipelines, comparison, mapLightEvent);
    RENDERDOC_ShutdownReplay();
    return result;
}
