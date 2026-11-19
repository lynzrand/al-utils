extern alias unity;
using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Il2CppInterop.Runtime.Attributes;
using Il2CppInterop.Runtime.InteropTypes.Arrays;
using UnityEngine.Rendering.Universal;
using unity::Unity.Profiling;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;
using unity::UnityEngine.SceneManagement;

namespace AL_Performance;

public sealed class PerformanceController : MonoBehaviour
{
    public PerformanceController(IntPtr pointer) : base(pointer) { }

    private readonly RenderOverrides rendering = new();
    private BenchmarkRequest? request;
    private string? controlPath, lastRequestId;
    private long nextPoll;
    private int oldVSync, oldFrameRate;
    private bool controlsFrameLimit;
    private Benchmark? benchmark;
    private (int Width, int Height, FullScreenMode Mode)? originalWindow;
    private (int Width, int Height)? requestedSize;

    public void Start()
    {
        controlPath = Environment.GetEnvironmentVariable("AL_PERF_CONTROL");
        Plugin.Instance.Log.LogInfo(controlPath is null
            ? "Render scale and upscaling are configurable in com.al-povx.performance.cfg."
            : $"Benchmark control file: {controlPath}");
    }

    public void LateUpdate()
    {
        try
        {
            var now = Stopwatch.GetTimestamp();
            if (now >= nextPoll)
            {
                nextPoll = now + Stopwatch.Frequency / 4;
                PollControl();
                if (request?.Uncap == true)
                {
                    QualitySettings.vSyncCount = 0;
                    Application.targetFrameRate = -1;
                }
                ApplyRendering();
            }

            if (benchmark?.Sample(now) == true)
            {
                benchmark.Write();
                benchmark.Dispose();
                benchmark = null;
            }
        }
        catch (Exception error)
        {
            Plugin.Instance.Log.LogError(error);
            Shutdown();
            enabled = false;
        }
    }

    [HideFromIl2Cpp]
    private void PollControl()
    {
        if (controlPath is null || !File.Exists(controlPath)) return;

        BenchmarkRequest? next;
        try
        {
            next = JsonSerializer.Deserialize<BenchmarkRequest>(File.ReadAllText(controlPath));
        }
        catch (JsonException)
        {
            // Editors can truncate and rewrite the control file between polls.
            return;
        }
        catch (IOException)
        {
            return;
        }

        if (next is null || string.IsNullOrWhiteSpace(next.Id) || next.Id == lastRequestId) return;
        if (next.Id.Length > 80 || next.Id.Any(c => c is not (>= 'A' and <= 'Z' or >= 'a' and <= 'z'
            or >= '0' and <= '9' or '-' or '_')))
        {
            Plugin.Instance.Log.LogWarning("Benchmark Id must use only ASCII letters, digits, hyphens, and underscores.");
            lastRequestId = next.Id;
            return;
        }

        lastRequestId = next.Id;
        benchmark?.Dispose();
        benchmark = null;
        rendering.Restore();
        RestoreFrameLimit();
        request = next;
        SetBenchmarkWindow(next.OutputWidth, next.OutputHeight);

        if (next.Uncap)
        {
            oldVSync = QualitySettings.vSyncCount;
            oldFrameRate = Application.targetFrameRate;
            controlsFrameLimit = true;
            QualitySettings.vSyncCount = 0;
            Application.targetFrameRate = -1;
        }

        ApplyRendering();
        string outputDirectory = Path.GetDirectoryName(Path.GetFullPath(controlPath))!;
        if (SceneManager.GetActiveScene().name == "Title")
        {
            if (next.OpenCharacterMaker) AL.Title.TitleScene.GotoCustomScene(true);
            if (next.OpenFreeScene) AL.Title.TitleScene.GotoFreeHScene();
        }
        if (next.OpenTestScene && AL.FreeH.Initialized) BenchmarkScenes.LoadStockScene(next.TestMap);
        if (next.Capture)
        {
            string template = Path.Combine(outputDirectory, next.Id);
            Plugin.Instance.Log.LogInfo(RenderDocCapture.TryTrigger(template)
                ? $"RenderDoc capture queued for {template}."
                : "RenderDoc capture requires an injected RenderDoc and AL_PERF_RENDERDOC=1.");
        }
        if (next.Seconds > 0) benchmark = new Benchmark(next, outputDirectory);
        else Benchmark.WriteState(Path.Combine(outputDirectory, next.Id + ".json"));
    }

    private void RestoreFrameLimit()
    {
        if (!controlsFrameLimit) return;
        QualitySettings.vSyncCount = oldVSync;
        Application.targetFrameRate = oldFrameRate;
        controlsFrameLimit = false;
    }

    private void ApplyRendering()
    {
        var settings = Plugin.Instance;
        rendering.Apply(request, settings.RenderScale.Value, settings.MsaaSamples.Value,
            settings.DisableFsr.Value, settings.SoftShadows.Value);
    }

    private void SetBenchmarkWindow(int width, int height)
    {
        if (width is < 800 or > 7680 || height is < 600 or > 4320)
        {
            if (originalWindow is { } previous)
                Screen.SetResolution(previous.Width, previous.Height, previous.Mode);
            originalWindow = null;
            requestedSize = null;
            return;
        }

        if (requestedSize == (width, height)) return;
        originalWindow ??= (Screen.width, Screen.height, Screen.fullScreenMode);
        requestedSize = (width, height);
        Screen.SetResolution(width, height, FullScreenMode.Windowed);
    }

    public void Shutdown()
    {
        benchmark?.Dispose();
        benchmark = null;
        rendering.Restore();
        RestoreFrameLimit();
        SetBenchmarkWindow(0, 0);
    }
}

internal sealed record BenchmarkRequest(
    string Id,
    double Seconds = 0,
    double Warmup = 4,
    bool Uncap = false,
    float Scale = 0,
    bool Fsr = false,
    bool DisableFsr = false,
    int MainShadowResolution = 0,
    int ShadowCascades = 0,
    float ShadowDistance = 0,
    int Msaa = 0,
    bool DisableShadows = false,
    bool DisableAdditionalShadows = false,
    bool DisableMainShadows = false,
    int ShadowFilter = 0,
    bool DisablePost = false,
    string[]? DisableFeatures = null,
    bool Capture = false,
    int OutputWidth = 0,
    int OutputHeight = 0,
    bool OpenCharacterMaker = false,
    bool OpenFreeScene = false,
    bool OpenTestScene = false,
    int TestMap = 2);

internal sealed class Benchmark : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private static readonly (ProfilerCategory Category, string Name)[] Counters =
    {
        (ProfilerCategory.Render, "Draw Calls Count"),
        (ProfilerCategory.Render, "SetPass Calls Count"),
        (ProfilerCategory.Render, "Batches Count"),
        (ProfilerCategory.Render, "Triangles Count"),
        (ProfilerCategory.Render, "Shadow Casters Count"),
        (ProfilerCategory.Internal, "Main Thread"),
        (ProfilerCategory.Internal, "Render Thread"),
        (ProfilerCategory.Internal, "CPU Main Thread Frame Time"),
        (ProfilerCategory.Internal, "CPU Main Thread Present Wait Time"),
        (ProfilerCategory.Internal, "GPU Frame Time")
    };

    private readonly BenchmarkRequest request;
    private readonly string directory;
    private readonly long start, end;
    private readonly List<SampleRow> samples = new();
    private readonly List<(string Name, ProfilerRecorder Recorder)> recorders = new();
    private readonly Il2CppStructArray<FrameTiming>? timings;
    private long previous, sampleStart;
    private ulong? lastTimingTimestamp;
    private object? startState;

    internal Benchmark(BenchmarkRequest request, string directory)
    {
        this.request = request;
        this.directory = directory;
        foreach (var (category, name) in Counters)
        {
            try
            {
                var recorder = ProfilerRecorder.StartNew(category, name, 1, ProfilerRecorderOptions.Default);
                if (recorder.Valid) recorders.Add((name, recorder));
            }
            catch (Exception)
            {
                // Some counters are stripped from retail players.
            }
        }
        if (FrameTimingManager.IsFeatureEnabled()) timings = new Il2CppStructArray<FrameTiming>(1);

        start = Stopwatch.GetTimestamp() + (long)(Math.Clamp(request.Warmup, 1, 30) * Stopwatch.Frequency);
        end = start + (long)(Math.Clamp(request.Seconds, 2, 60) * Stopwatch.Frequency);
        Plugin.Instance.Log.LogInfo($"Benchmark {request.Id} warming up.");
    }

    internal bool Sample(long now)
    {
        if (timings is not null) FrameTimingManager.CaptureFrameTimings();
        if (now < start) return false;
        if (previous == 0)
        {
            startState = DescribeState();
            sampleStart = previous = now;
            return false;
        }

        FrameTiming? timing = null;
        if (timings is not null && FrameTimingManager.GetLatestTimings(1, timings) > 0)
        {
            var latest = timings[0];
            if (latest.frameStartTimestamp != lastTimingTimestamp)
            {
                lastTimingTimestamp = latest.frameStartTimestamp;
                timing = latest;
            }
        }

        var values = new long[recorders.Count];
        for (int i = 0; i < values.Length; i++) values[i] = recorders[i].Recorder.LastValue;
        samples.Add(new SampleRow(Milliseconds(now - sampleStart), Milliseconds(now - previous),
            timing?.cpuFrameTime, timing?.cpuMainThreadFrameTime, timing?.cpuRenderThreadFrameTime,
            timing?.cpuMainThreadPresentWaitTime, timing?.gpuFrameTime, values));
        previous = now;
        return now >= end;
    }

    internal void Write()
    {
        var path = Path.Combine(directory, request.Id);
        using (var writer = new StreamWriter(path + ".csv"))
        {
            writer.Write("ElapsedMs,FrameIntervalMs,UnityCpuFrameMs,UnityMainThreadMs,UnityRenderThreadMs,UnityPresentWaitMs,UnityGpuFrameMs");
            foreach (var (name, _) in recorders) writer.Write("," + name);
            writer.WriteLine();
            foreach (var row in samples)
            {
                writer.Write(FormattableString.Invariant($"{row.Elapsed:F4},{row.Interval:F4},{row.Cpu:F4},{row.Main:F4},{row.Render:F4},{row.Present:F4},{row.Gpu:F4}"));
                foreach (long value in row.Counters) writer.Write("," + value.ToString(CultureInfo.InvariantCulture));
                writer.WriteLine();
            }
        }
        File.WriteAllText(path + ".json", JsonSerializer.Serialize(new
        {
            Request = request,
            Samples = samples.Count,
            Start = startState,
            End = DescribeState()
        }, JsonOptions));
        Plugin.Instance.Log.LogInfo($"Benchmark {request.Id}: {samples.Count} frame intervals written to {path}.csv");
    }

    internal static void WriteState(string path) =>
        File.WriteAllText(path, JsonSerializer.Serialize(DescribeState(), JsonOptions));

    private static object DescribeState()
    {
        var asset = GraphicsSettings.currentRenderPipeline?.TryCast<UniversalRenderPipelineAsset>();
        var cameras = new List<object>();
        foreach (var camera in Camera.allCameras)
        {
            if (!camera) continue;
            var data = camera.GetComponent<UniversalAdditionalCameraData>();
            var position = camera.transform.position;
            var rotation = camera.transform.rotation;
            cameras.Add(new
            {
                camera.name, Type = camera.cameraType.ToString(), camera.depth, camera.pixelWidth, camera.pixelHeight,
                camera.allowMSAA, camera.allowHDR,
                Position = new[] { position.x, position.y, position.z },
                Rotation = new[] { rotation.x, rotation.y, rotation.z, rotation.w },
                Target = camera.targetTexture ? camera.targetTexture.name : null,
                Post = data ? data!.renderPostProcessing : (bool?)null,
                Shadows = data ? data!.renderShadows : (bool?)null,
                RenderType = data ? data!.renderType.ToString() : null,
                Renderer = data && data!.scriptableRenderer != null ? data.scriptableRenderer.GetIl2CppType().Name : null
            });
        }

        return new
        {
            At = DateTimeOffset.Now,
            Scene = SceneManager.GetActiveScene().name,
            Api = SystemInfo.graphicsDeviceType.ToString(),
            Gpu = SystemInfo.graphicsDeviceName,
            Focused = Application.isFocused,
            Width = Screen.width,
            Height = Screen.height,
            VSync = QualitySettings.vSyncCount,
            TargetFrameRate = Application.targetFrameRate,
            TimeScale = Time.timeScale,
            UnityFrameTiming = FrameTimingManager.IsFeatureEnabled(),
            URP = asset ? RenderOverrides.Describe(asset!) : null,
            Cameras = cameras
        };
    }

    public void Dispose()
    {
        foreach (var (_, recorder) in recorders) recorder.Dispose();
        recorders.Clear();
    }

    private static double Milliseconds(long ticks) => ticks * (1000d / Stopwatch.Frequency);

    private sealed record SampleRow(double Elapsed, double Interval, double? Cpu, double? Main,
        double? Render, double? Present, double? Gpu, long[] Counters);
}
