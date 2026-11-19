extern alias unity;
using System.Runtime.InteropServices;
using System.Text;
using Il2CppInterop.Runtime;
using Il2CppInterop.Runtime.InteropTypes.Arrays;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;

namespace AL_NPR;

public static unsafe class NativeVisibilityProbe
{
    private const int Count = 129;
    private const uint Seed = 0x27182818;
    private const uint Step = 0x9e3779b9;
    private static Probe? current;

    public static string Begin(string libraryPath, string shaderPath)
    {
        if (current is not null) return Status();
        if (SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D12)
            throw new NotSupportedException("The visibility interop probe requires Direct3D 12.");
        var probe = new Probe(libraryPath, shaderPath);
        current = probe;
        probe.Submit();
        return Status();
    }

    public static string Status() => current is { } probe ? probe.Status : "No native visibility probe has been started.";

    public static string Retire()
    {
        current?.Retire();
        return Status();
    }

    private static uint InitialValue(int index) => unchecked(0x13579bdfu + (uint)index * 0xa53u);

    private sealed class Probe
    {
        private readonly IntPtr module;
        private readonly IntPtr callback;
        private readonly int eventId;
        private readonly Queue queue;
        private readonly GetStatus getStatus;
        private readonly CanUnload canUnload;
        private readonly ComputeBuffer output;
        private Il2CppSystem.Action<AsyncGPUReadbackRequest>? onReadback;
        private string result = "Waiting for Unity readback.";
        private bool readbackDone, released;

        internal Probe(string libraryPath, string shaderPath)
        {
            var registry = UnityNativeInterfaces.Get();
            var shader = File.ReadAllBytes(shaderPath);
            module = NativeLibrary.Load(libraryPath);
            try
            {
                Export<Register>("UnityPluginLoad")(registry);
                queue = Export<Queue>("ALVIS_QueueWrite");
                getStatus = Export<GetStatus>("ALVIS_GetStatus");
                canUnload = Export<CanUnload>("ALVIS_CanUnload");
                callback = Export<GetCallback>("ALVIS_GetRenderEventFunc")();
                eventId = Export<GetEventId>("ALVIS_GetEventId")();
                fixed (byte* bytes = shader)
                {
                    if (eventId < 0 || callback == IntPtr.Zero ||
                        Export<SetShader>("ALVIS_SetShader")(bytes, (uint)shader.Length) == 0)
                        throw new InvalidOperationException("The native visibility probe rejected its initialization.");
                }
                output = new ComputeBuffer(Count, 4, ComputeBufferType.Structured);
            }
            catch
            {
                if (NativeLibrary.TryGetExport(module, "UnityPluginUnload", out var unload))
                    Marshal.GetDelegateForFunctionPointer<Unload>(unload)();
                NativeLibrary.Free(module);
                throw;
            }
        }

        internal string Status
        {
            get
            {
                byte* report = stackalloc byte[1024];
                var length = getStatus(report, 1024);
                return result + " " + Encoding.UTF8.GetString(new ReadOnlySpan<byte>(report, (int)length));
            }
        }

        internal void Submit()
        {
            var initial = new Il2CppStructArray<uint>(Count);
            for (int i = 0; i < Count; i++) initial[i] = InitialValue(i);
            onReadback = DelegateSupport.ConvertDelegate<Il2CppSystem.Action<AsyncGPUReadbackRequest>>(
                new Action<AsyncGPUReadbackRequest>(Validate));
            var command = new CommandBuffer();
            try
            {
                command.SetBufferData(output, new Il2CppSystem.Array(initial.Pointer));
                command.IssuePluginEvent(callback, eventId);
                command.RequestAsyncReadback(output, onReadback);
                if (queue(output.GetNativeBufferPtr(), Count, Seed) == 0)
                    throw new InvalidOperationException(Status);
                Graphics.ExecuteCommandBuffer(command);
            }
            finally
            {
                command.Release();
            }
        }

        private void Validate(AsyncGPUReadbackRequest request)
        {
            readbackDone = true;
            if (request.hasError || request.layerDataSize != Count * sizeof(uint))
            {
                result = "Unity returned an invalid native visibility readback.";
                return;
            }

            var source = request.GetDataRaw(0);
            if (source == IntPtr.Zero)
            {
                result = "Unity returned no native visibility data.";
                return;
            }
            var values = new ReadOnlySpan<uint>((void*)source, Count);
            for (int i = 0; i < values.Length; i++)
            {
                uint expected = InitialValue(i) ^ Seed ^ unchecked(Step * (uint)i);
                if (values[i] == expected) continue;
                result = $"Native visibility readback mismatch at {i}: {values[i]:x8}, expected {expected:x8}.";
                return;
            }
            result = $"All {Count} Unity buffer values matched after the native compute event.";
        }

        internal void Retire()
        {
            if (!readbackDone || released) return;
            if (canUnload() != 0)
            {
                output.Release();
                released = true;
                return;
            }

            // The native callback retires resources once Unity's frame fence
            // passes the queued write. The test DLL stays loaded for this session.
            var command = new CommandBuffer();
            try
            {
                command.IssuePluginEvent(callback, eventId);
                Graphics.ExecuteCommandBuffer(command);
            }
            finally
            {
                command.Release();
            }
        }

        private T Export<T>(string name) where T : Delegate =>
            Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(module, name));
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void Register(IntPtr registry);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void Unload();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SetShader(byte* bytes, uint length);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate ulong Queue(IntPtr buffer, uint count, uint seed);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr GetCallback();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetEventId();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate uint GetStatus(byte* bytes, uint capacity);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int CanUnload();
}
