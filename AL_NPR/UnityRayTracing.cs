extern alias unity;
using System.Runtime.InteropServices;
using Il2CppInterop.Runtime;
using unity::UnityEngine;
using unity::UnityEngine.Bindings;
using unity::UnityEngine.Rendering;
using Object = unity::UnityEngine.Object;

namespace AL_NPR;

// The IL2CPP build retains Unity's native ray-tracing bindings but strips
// managed entry points it never calls. Keep this bridge tied to the audited
// engine ABI until there is a public constructor in the runtime assemblies.
public static class UnityRayTracing
{
    private const string EngineVersion = "6000.0.65f1";

    public static string Capabilities() => $"{SystemInfo.graphicsDeviceType}, {SystemInfo.graphicsDeviceName}, " +
        $"ray tracing shaders: {GetSupport("SupportsRayTracingShaders")}, inline rays: {GetSupport("SupportsInlineRayTracing")}.";

    public static string ProbeNativeInterfaces() => UnityNativeInterfaces.Describe();

    public static string ProbeDevice(string diagnosticLibrary)
    {
        if (SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D12)
            throw new NotSupportedException("This device probe requires Direct3D 12.");
        var module = NativeLibrary.Load(diagnosticLibrary);
        try
        {
            var query = Marshal.GetDelegateForFunctionPointer<QueryDevice>(NativeLibrary.GetExport(module, "AL_QueryDxr"));
            var buffer = new ComputeBuffer(1, 16);
            try
            {
                uint caps = query(buffer.GetNativeBufferPtr());
                return $"{Capabilities()} D3D12 native ray tracing tier {(caps & 0xffff) / 10}.{(caps & 0xffff) % 10}, " +
                    $"shader model 0x{caps >> 16:x}.";
            }
            finally
            {
                buffer.Release();
            }
        }
        finally
        {
            NativeLibrary.Free(module);
        }
    }

    public static string Probe()
    {
        var scene = Create();
        try
        {
            int map = LayerMask.GetMask("Map");
            foreach (var renderer in Object.FindObjectsOfType<MeshRenderer>())
            {
                if (!renderer.enabled || renderer.forceRenderingOff ||
                    renderer.shadowCastingMode == ShadowCastingMode.Off ||
                    (map & (1 << renderer.gameObject.layer)) == 0) continue;
                var mesh = renderer.GetComponent<MeshFilter>()?.sharedMesh;
                if (!mesh) continue;
                var materials = renderer.sharedMaterials;
                var flags = new RayTracingSubMeshFlags[mesh!.subMeshCount];
                bool hasGeometry = false;
                for (int submesh = 0; submesh < flags.Length && submesh < materials.Length; submesh++)
                {
                    var material = materials[submesh];
                    if (!material || material!.renderQueue >= (int)RenderQueue.AlphaTest ||
                        material.IsKeywordEnabled("_ALPHATEST_ON") || mesh.GetTopology(submesh) != MeshTopology.Triangles ||
                        mesh.GetIndexCount(submesh) == 0) continue;
                    flags[submesh] = RayTracingSubMeshFlags.Enabled | RayTracingSubMeshFlags.ClosestHitOnly;
                    hasGeometry = true;
                }
                if (!hasGeometry) continue;

                int handle = AddInstance(scene, renderer, flags, 1);
                scene.Build();
                uint instances = scene.GetInstanceCount();
                ulong bytes = scene.GetSize();
                if (handle < 0 || instances != 1 || bytes == 0)
                    throw new InvalidOperationException($"Unity did not build the expected ray-tracing instance ({handle}, {instances}, {bytes}).");
                return $"Unity RTAS: {instances} instance, {bytes:N0} bytes, {renderer.name}, CPU mesh access: {mesh.isReadable}.";
            }
            throw new InvalidOperationException("The map has no suitable opaque mesh for the Unity ray-tracing probe.");
        }
        finally
        {
            scene.Release();
        }
    }

    private static unsafe int AddInstance(RayTracingAccelerationStructure scene, Renderer renderer,
        RayTracingSubMeshFlags[] flags, uint id)
    {
        // The generated IL2CPP array class is absent. The native binding reads
        // a contiguous array of 32-bit submesh flags during this call.
        fixed (RayTracingSubMeshFlags* data = flags)
        {
            var span = new ManagedSpanWrapper(data, flags.Length);
            return RayTracingAccelerationStructure.AddInstanceSubMeshFlagsArray_Injected(scene.m_Ptr,
                Object.MarshalledUnityObject.MarshalNotNull(renderer), ref span, false, false, 0xff, id);
        }
    }

    internal static RayTracingAccelerationStructure Create()
    {
        if (Application.unityVersion != EngineVersion || SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D12)
            throw new NotSupportedException($"The ray-tracing bridge expects Unity {EngineVersion} and Direct3D 12.");
        if (!GetSupport("SupportsRayTracingShaders") && !GetSupport("SupportsInlineRayTracing"))
            throw new NotSupportedException(Capabilities());

        var create = IL2CPP.ResolveICall<CreateAccelerationStructure>(
            "UnityEngine.Rendering.RayTracingAccelerationStructure::Create_Injected");
        var instance = new RayTracingAccelerationStructure(
            IL2CPP.il2cpp_object_new(Il2CppClassPointerStore<RayTracingAccelerationStructure>.NativeClassPtr));
        var settings = new Settings
        {
            ManagementMode = RayTracingAccelerationStructure.ManagementMode.Manual,
            RayTracingMode = RayTracingAccelerationStructure.RayTracingModeMask.Everything,
            LayerMask = -1,
            StaticFlags = RayTracingAccelerationStructureBuildFlags.PreferFastTrace,
            DynamicFlags = RayTracingAccelerationStructureBuildFlags.PreferFastBuild
        };
        instance.m_Ptr = create(ref settings);
        if (instance.m_Ptr == IntPtr.Zero)
            throw new InvalidOperationException("Unity could not allocate a ray-tracing acceleration structure.");
        return instance;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Settings
    {
        public RayTracingAccelerationStructure.ManagementMode ManagementMode;
        public RayTracingAccelerationStructure.RayTracingModeMask RayTracingMode;
        public int LayerMask;
        public RayTracingAccelerationStructureBuildFlags StaticFlags;
        public RayTracingAccelerationStructureBuildFlags DynamicFlags;
        public int EnableCompaction;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool GetRayTracingSupport();

    private static bool GetSupport(string method)
        => IL2CPP.ResolveICall<GetRayTracingSupport>("UnityEngine.SystemInfo::" + method)();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr CreateAccelerationStructure(ref Settings settings);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate uint QueryDevice(IntPtr resource);
}
