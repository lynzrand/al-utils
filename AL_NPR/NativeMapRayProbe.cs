extern alias unity;
using System.Runtime.InteropServices;
using System.Text;
using Il2CppInterop.Runtime;
using Il2CppInterop.Runtime.InteropTypes.Arrays;
using unity::UnityEngine;
using unity::UnityEngine.Experimental.Rendering;
using unity::UnityEngine.Rendering;
using Object = unity::UnityEngine.Object;

namespace AL_NPR;

// On-demand diagnostic using the same original mesh buffers as the renderer.
// The native module and its callback stay loaded for the test process lifetime.
public static unsafe partial class NativeMapRayProbe
{
    private static Session? session;
    private static Session? depthSession;

    public static string WarmUp(string libraryPath, string shaderPath)
    {
        if (session is not null) return Status();
        if (SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D12)
            throw new NotSupportedException("The mesh ray probe requires Direct3D 12.");
        session = new Session(libraryPath, shaderPath, false);
        session.IssueEvent();
        return Status();
    }

    public static string Trace()
    {
        if (session is null) throw new InvalidOperationException("Warm up the native mesh ray probe first.");
        session.Trace();
        return Status();
    }

    public static string Status() => session?.Status ?? "No native mesh ray probe has started.";

    public static string TraceSceneComparison(bool includeSecond, bool legacyWrapper = false)
    {
        if (session is null) throw new InvalidOperationException("Warm up the native mesh ray probe first.");
        if (includeSecond && legacyWrapper)
            throw new ArgumentException("The legacy wrapper accepts only one mesh.");
        session.Trace(true, includeSecond, legacyWrapper);
        return Status();
    }

    public static string TraceMapGeometry()
    {
        if (session is null) throw new InvalidOperationException("Warm up the native mesh ray probe first.");
        session.TraceMapGeometry();
        return Status();
    }

    public static string ReadLater() => session?.ReadLater() ?? Status();

    public static string Retire()
    {
        session?.Retire();
        return Status();
    }

    public static string WarmUpDepth(string libraryPath, string shaderPath)
    {
        if (depthSession is not null) return DepthStatus();
        if (SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D12)
            throw new NotSupportedException("The depth ray probe requires Direct3D 12.");
        depthSession = new Session(libraryPath, shaderPath, true);
        depthSession.IssueEvent();
        return DepthStatus();
    }

    public static string TraceDepth(uint testMask)
    {
        if (depthSession is null) throw new InvalidOperationException("Warm up the depth ray probe first.");
        depthSession.TraceDepth(testMask);
        return DepthStatus();
    }

    public static string TraceDepthScene(uint testMask = 0, bool includeCharacter = false)
    {
        if (depthSession is null) throw new InvalidOperationException("Warm up the depth ray probe first.");
        depthSession.TraceDepth(testMask, true, includeCharacter);
        return DepthStatus();
    }

    public static string DepthStatus() => depthSession?.Status ?? "No depth ray probe has started.";

    public static string CompleteDepth()
    {
        depthSession?.CompleteDepth();
        return DepthStatus();
    }

    public static string ClearDepth()
    {
        MapDirectional.ClearVisibility();
        depthSession?.RetireDepth();
        return DepthStatus();
    }

    private sealed partial class Session
    {
        private uint[] expected = { 1, 1, 0, 2 };
        private readonly IntPtr module;
        private readonly IntPtr callback;
        private readonly int eventId;
        private readonly QueueMesh? queue;
        private readonly QueueDepth? queueDepth;
        private SceneCasters? sceneCasters;
        private readonly GetStatus getStatus;
        private readonly CanUnload canUnload;
        private GraphicsBuffer? vertex, index;
        private ComputeBuffer? output;
        private RenderTexture? visibility;
        private Il2CppSystem.Action<AsyncGPUReadbackRequest>? readback;
        private string result = "Waiting for map receiver rays.";
        private bool readbackDone;
        private Action? completeDepth;
        private (Mesh Mesh, MeshRenderer Renderer, int Submesh, Vector3 Center, Vector3 Normal)? comparisonSurface;

        internal Session(string libraryPath, string shaderPath, bool depth)
        {
            var registry = UnityNativeInterfaces.Get();
            var shader = File.ReadAllBytes(shaderPath);
            module = NativeLibrary.Load(libraryPath);
            try
            {
                Export<Register>("UnityPluginLoad")(registry);
                if (depth) queueDepth = Export<QueueDepth>("ALRAY_QueueDepth");
                else queue = Export<QueueMesh>("ALRAY_QueueMesh");
                getStatus = Export<GetStatus>("ALRAY_GetStatus");
                canUnload = Export<CanUnload>("ALRAY_CanUnload");
                callback = Export<GetCallback>("ALRAY_GetRenderEventFunc")();
                eventId = Export<GetEventId>("ALRAY_GetEventId")();
                fixed (byte* bytes = shader)
                {
                    if (eventId < 0 || callback == IntPtr.Zero ||
                        Export<SetShader>("ALRAY_SetShader")(bytes, (uint)shader.Length) == 0)
                        throw new InvalidOperationException("The native map ray probe rejected its initialization.");
                }
            }
            catch
            {
                if (NativeLibrary.TryGetExport(module, "UnityPluginUnload", out var unload))
                    Marshal.GetDelegateForFunctionPointer<Unload>(unload)();
                NativeLibrary.Free(module);
                throw;
            }
        }

        internal string Status => result + " " + NativeStatus();

        internal void Trace(bool compareScene = false, bool includeSecond = false, bool legacyWrapper = false)
        {
            if (!NativeStatus().Contains("initialized=1", StringComparison.Ordinal))
                throw new InvalidOperationException("The native ray probe has not warmed up. " + NativeStatus());
            if (output is not null) throw new InvalidOperationException("This probe already has a submitted request.");
            var surface = compareScene ? comparisonSurface ??= FindSurface() : FindSurface();
            var (mesh, renderer, submesh, center, normal) = surface;
            if (!mesh || !renderer) throw new InvalidOperationException("The comparison surface was destroyed; start a new probe session.");
            var matrix = renderer.transform.localToWorldMatrix;
            var desc = mesh.GetSubMesh(submesh);
            int stream = mesh.GetVertexAttributeStream(VertexAttribute.Position);
            int stride = mesh.GetVertexBufferStride(stream);
            int positionOffset = mesh.GetVertexAttributeOffset(VertexAttribute.Position);
            uint indexBits = mesh.indexFormat == IndexFormat.UInt16 ? 16u : 32u;

            var outside = renderer.bounds.max + Vector3.one;
            ProbeRay[] rays = {
                new(center + normal * 0.125f, 0.001f, -normal, 0.25f),
                new(center - normal * 0.125f, 0.001f, normal, 0.25f),
                new(outside, 0.001f, Vector3.right, 0.5f),
                new(center, 0.001f, Vector3.zero, 0.25f)
            };
            // A translated instance lies outside the original renderer bounds.
            // Its hit must disappear when only that instance is omitted; a
            // shorter ray must miss it even when the instance is present.
            var translation = Vector3.one * (renderer.bounds.size.magnitude * 4f + 100f);
            if (compareScene)
            {
                var translatedCenter = center + translation;
                rays = new ProbeRay[] {
                    rays[0], rays[1],
                    new(translatedCenter + normal * 0.125f, 0.001f, -normal, 0.25f),
                    new(translatedCenter + normal * 0.125f, 0.001f, -normal, 0.05f),
                    rays[3]
                };
                expected = new uint[] { 1, 1, includeSecond ? 1u : 0u, 0, 2 };
            }
            else expected = new uint[] { 1, 1, 0, 2 };
            vertex = mesh.GetVertexBuffer(stream);
            try
            {
                index = mesh.GetIndexBuffer();
                output = new ComputeBuffer(rays.Length, sizeof(uint), ComputeBufferType.Structured);
                var sentinel = new Il2CppStructArray<uint>(rays.Length);
                for (int i = 0; i < sentinel.Length; i++) sentinel[i] = uint.MaxValue;
                output.SetData(new Il2CppSystem.Array(sentinel.Pointer));
                var request = new MeshRequest
                {
                    Vertex = vertex.GetNativeBufferPtr(),
                    Index = index.GetNativeBufferPtr(),
                    Output = output.GetNativeBufferPtr(),
                    PositionOffset = (ulong)desc.baseVertex * (uint)stride + (uint)positionOffset,
                    IndexOffset = (ulong)desc.indexStart * (indexBits / 8),
                    PositionStride = (uint)stride,
                    VertexCount = (uint)(mesh.vertexCount - desc.baseVertex),
                    IndexCount = (uint)desc.indexCount,
                    IndexBits = indexBits,
                    M00 = matrix.m00, M01 = matrix.m01, M02 = matrix.m02, M03 = matrix.m03,
                    M10 = matrix.m10, M11 = matrix.m11, M12 = matrix.m12, M13 = matrix.m13,
                    M20 = matrix.m20, M21 = matrix.m21, M22 = matrix.m22, M23 = matrix.m23
                };
                readback = DelegateSupport.ConvertDelegate<Il2CppSystem.Action<AsyncGPUReadbackRequest>>(
                    new Action<AsyncGPUReadbackRequest>(Accept));
                fixed (ProbeRay* rayInputs = rays)
                {
                    ulong ticket;
                    if (compareScene && !legacyWrapper)
                    {
                        var translated = request;
                        translated.M03 += translation.x;
                        translated.M13 += translation.y;
                        translated.M23 += translation.z;
                        MeshRequest[] meshes = includeSecond ? new[] { request, translated } : new[] { request };
                        var queueScene = Export<QueueScene>("ALRAY_QueueScene");
                        fixed (MeshRequest* inputs = meshes)
                            ticket = queueScene(inputs, (uint)meshes.Length, rayInputs, (uint)rays.Length);
                    }
                    else ticket = queue!(ref request, rayInputs, (uint)rays.Length);
                    if (ticket == 0)
                        throw new InvalidOperationException("The native ray probe rejected the mesh. " + NativeStatus());
                }
            }
            catch
            {
                ReleaseBuffers();
                throw;
            }
            result = $"Queued rays for {renderer.name}, submesh {submesh}, {desc.indexCount / 3:N0} triangles.";
            if (compareScene) result += $" Translated instance: {includeSecond}; legacy wrapper: {legacyWrapper}.";
            readbackDone = false;
            IssueEvent(output);
        }

        internal void TraceMapGeometry()
        {
            if (!NativeStatus().Contains("initialized=1", StringComparison.Ordinal) || output is not null)
                throw new InvalidOperationException("Warm up the ray probe and retire its previous request first.");
            expected = new uint[] { 1, 1, 0, 2 };
            try
            {
                output = new ComputeBuffer(expected.Length, sizeof(uint), ComputeBufferType.Structured);
                var sentinel = new Il2CppStructArray<uint>(expected.Length);
                for (int i = 0; i < sentinel.Length; i++) sentinel[i] = uint.MaxValue;
                output.SetData(new Il2CppSystem.Array(sentinel.Pointer));
                sceneCasters = new SceneCasters();
                var meshes = sceneCasters.Capture(output.GetNativeBufferPtr());
                var rays = sceneCasters.ValidationRays();
                readback = DelegateSupport.ConvertDelegate<Il2CppSystem.Action<AsyncGPUReadbackRequest>>(
                    new Action<AsyncGPUReadbackRequest>(Accept));
                var queueScene = Export<QueueScene>("ALRAY_QueueScene");
                fixed (MeshRequest* inputs = meshes)
                fixed (ProbeRay* rayInputs = rays)
                    if (queueScene(inputs, (uint)meshes.Length, rayInputs, (uint)rays.Length) == 0)
                        throw new InvalidOperationException("The native ray probe rejected the map geometry. " + NativeStatus());
            }
            catch
            {
                ReleaseBuffers();
                throw;
            }
            result = "Queued map geometry rays against " + sceneCasters.Summary + ".";
            readbackDone = false;
            IssueEvent(output);
        }

        internal void TraceDepth(uint testMask, bool scene = false, bool includeCharacter = false)
        {
            if (!NativeStatus().Contains("initialized=1", StringComparison.Ordinal) || visibility is not null)
                throw new InvalidOperationException("Warm up the depth ray probe or retire its previous request.");
            if (Time.timeScale != 0f)
                throw new InvalidOperationException("Pause scaled animation before capturing a frozen visibility image.");
            var camera = Camera.main;
            var depth = Shader.GetGlobalTexture("_CameraDepthTexture");
            if (!camera || !depth || depth.width != camera.pixelWidth || depth.height != camera.pixelHeight)
                throw new InvalidOperationException("The main camera has not published matching depth.");
            var (ids, directions) = MapDirectional.VisibilityInputs(camera);
            if (ids.Length == 0) throw new InvalidOperationException("No authored map directionals were bound.");
            var surface = scene ? default : FindSurface();
            var depthTexture = depth.TryCast<RenderTexture>();
            var depthPtr = depthTexture ? depthTexture!.GetNativeDepthBufferPtr() : IntPtr.Zero;
            if (depthPtr == IntPtr.Zero) depthPtr = depth.GetNativeTexturePtr();
            if (depthPtr == IntPtr.Zero) throw new InvalidOperationException("Unity camera depth has no native resource.");
            var captureView = camera.worldToCameraMatrix;
            var captureProjection = camera.projectionMatrix;
            var inverse = (GL.GetGPUProjectionMatrix(captureProjection, true) * captureView).inverse;

            var target = new RenderTexture(depth.width, depth.height, 0)
            {
                graphicsFormat = GraphicsFormat.R32G32_UInt,
                enableRandomWrite = true,
                name = "AL frozen directional visibility"
            };
            try
            {
                if (!target.Create()) throw new InvalidOperationException("Could not allocate the uint2 visibility target.");
                MeshRequest[] requests;
                if (scene && retainedScene != 0)
                {
                    if (Export<SceneReady>("ALRAY_SceneReady")(retainedScene) != 1)
                        throw new InvalidOperationException("The retained scene build has not completed.");
                    requests = Array.Empty<MeshRequest>();
                }
                else if (scene)
                {
                    sceneCasters = new SceneCasters();
                    requests = sceneCasters.Capture(target.GetNativeTexturePtr(), includeCharacter);
                }
                else
                {
                    var (mesh, renderer, submesh, _, _) = surface;
                    int stream = mesh.GetVertexAttributeStream(VertexAttribute.Position);
                    vertex = mesh.GetVertexBuffer(stream);
                    index = mesh.GetIndexBuffer();
                    requests = new[] { DescribeMesh(mesh, renderer, submesh, vertex, index, target.GetNativeTexturePtr()) };
                }
                var frame = new DepthFrame
                {
                    Width = (uint)target.width, Height = (uint)target.height,
                    LightCount = (uint)ids.Length, TestMask = testMask
                };
                for (int row = 0; row < 4; row++)
                    for (int col = 0; col < 4; col++)
                        frame.Inverse[row * 4 + col] = inverse[row, col];
                for (int light = 0; light < directions.Length; light++)
                {
                    var direction = directions[light];
                    frame.Directions[light * 4] = direction.x;
                    frame.Directions[light * 4 + 1] = direction.y;
                    frame.Directions[light * 4 + 2] = direction.z;
                }
                var summary = Export<ReadDepthSummary>("ALRAY_ReadDepthSummary");
                ulong ticket;
                if (scene && retainedScene != 0)
                {
                    ticket = Export<QueueRetainedDepth>("ALRAY_QueueRetainedDepth")(
                        retainedScene, target.GetNativeTexturePtr(), depthPtr, ref frame, 1);
                }
                else if (scene)
                {
                    var queueScene = Export<QueueDepthScene>("ALRAY_QueueDepthScene");
                    fixed (MeshRequest* inputs = requests)
                        ticket = queueScene(inputs, (uint)requests.Length, depthPtr, ref frame);
                }
                else ticket = queueDepth!(ref requests[0], depthPtr, ref frame);
                if (ticket == 0)
                    throw new InvalidOperationException("Native depth ray request was rejected. " + NativeStatus());
                completeDepth = () =>
                {
                    int state = summary(ticket, out uint valid, out uint blocked);
                    if (state == 0) return;
                    readbackDone = true;
                    completeDepth = null;
                    if (state < 0 || !camera || Time.timeScale != 0f ||
                        !camera.worldToCameraMatrix.Equals(captureView) ||
                        !camera.projectionMatrix.Equals(captureProjection))
                    {
                        result += $" Frozen depth verification rejected: native result={state}, " +
                            $"paused={Time.timeScale == 0f}, camera={!!camera}, " +
                            $"view matches={camera && camera.worldToCameraMatrix.Equals(captureView)}, " +
                            $"projection matches={camera && camera.projectionMatrix.Equals(captureProjection)}.";
                        return;
                    }
                    if (valid > 0) MapDirectional.PublishVisibility(camera, ids, directions, target);
                    result += $" Native readback: {blocked:N0} occluded pixels out of {valid:N0} valid depth pixels.";
                    if (NativeLibrary.TryGetExport(module, "ALRAY_ReadTimings", out var timingExport))
                    {
                        var timings = Marshal.GetDelegateForFunctionPointer<ReadTimings>(timingExport);
                        int timingState = timings(ticket, out double buildMs, out double traceMs, out double copyMs);
                        result += timingState == 1
                            ? $" One-shot GPU diagnostic: AS {buildMs:F3} ms, trace {traceMs:F3} ms, output copy {copyMs:F3} ms (not whole-frame cost)."
                            : $" GPU diagnostic timings unavailable ({timingState}).";
                    }
                };
            }
            catch
            {
                ReleaseBuffers();
                target.Release();
                Object.Destroy(target);
                throw;
            }
            visibility = target;
            readbackDone = false;
            string casters = scene ? sceneCasters!.Summary : surface.Renderer.name;
            result = $"Queued {ids.Length} directional rays per receiver against {casters}, test mask {testMask}.";
            IssueEvent();
        }

        internal void CompleteDepth() => completeDepth?.Invoke();

        internal void IssueEvent(ComputeBuffer? withReadback = null)
        {
            var command = new CommandBuffer();
            try
            {
                command.IssuePluginEvent(callback, eventId);
                if (withReadback is not null) command.RequestAsyncReadback(withReadback, readback);
                Graphics.ExecuteCommandBuffer(command);
            }
            finally
            {
                command.Release();
            }
        }

        private void Accept(AsyncGPUReadbackRequest request)
        {
            readbackDone = true;
            result += " Same-command " + Verify(request);
        }

        internal string ReadLater()
        {
            if (!readbackDone || output is null) return Status;
            var request = AsyncGPUReadback.Request(output);
            request.WaitForCompletion();
            return "Later " + Verify(request) + " " + NativeStatus();
        }

        private string Verify(AsyncGPUReadbackRequest request)
        {
            if (request.hasError || request.layerDataSize != expected.Length * sizeof(uint))
                return "invalid ray output.";
            var pointer = request.GetDataRaw(0);
            if (pointer == IntPtr.Zero) return "ray output was unavailable.";
            var values = new ReadOnlySpan<uint>((void*)pointer, expected.Length);
            return $"ray output [{string.Join(", ", values.ToArray())}] " +
                (values.SequenceEqual(expected) ? "matches the expected results." : $"differs from expected [{string.Join(", ", expected)}].");
        }

        internal void Retire()
        {
            if (!readbackDone || output is null) return;
            if (canUnload() == 0) IssueEvent();
            else ReleaseBuffers();
        }

        internal void RetireDepth(bool keepScene = false)
        {
            if (!keepScene) ReleaseRetainedScene();
            int idle = retainedScene != 0 ? Export<CanUnload>("ALRAY_RequestsIdle")() : canUnload();
            if (idle == 0)
            {
                IssueEvent();
                return;
            }
            if (!keepScene) ReleaseBuffers();
            if (visibility is null) return;
            visibility.Release();
            Object.Destroy(visibility);
            visibility = null;
            completeDepth = null;
        }

        private void ReleaseBuffers()
        {
            sceneCasters?.Dispose();
            sceneCasters = null;
            output?.Release();
            output = null;
            index?.Dispose();
            index = null;
            vertex?.Dispose();
            vertex = null;
        }

        private string NativeStatus()
        {
            byte* bytes = stackalloc byte[1024];
            var length = getStatus(bytes, 1024);
            return Encoding.UTF8.GetString(new ReadOnlySpan<byte>(bytes, (int)length));
        }

        private T Export<T>(string name) where T : Delegate =>
            Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(module, name));
    }

    private static (Mesh Mesh, MeshRenderer Renderer, int Submesh, Vector3 Center, Vector3 Normal) FindSurface()
    {
        int map = LayerMask.GetMask("Map");
        foreach (var renderer in Object.FindObjectsOfType<MeshRenderer>())
        {
            if (!renderer.enabled || renderer.forceRenderingOff || (map & (1 << renderer.gameObject.layer)) == 0)
                continue;
            var mesh = renderer.GetComponent<MeshFilter>()?.sharedMesh;
            if (!mesh || !mesh!.isReadable || !mesh.HasVertexAttribute(VertexAttribute.Position) ||
                mesh.GetVertexAttributeFormat(VertexAttribute.Position) != VertexAttributeFormat.Float32 ||
                mesh.GetVertexAttributeDimension(VertexAttribute.Position) != 3) continue;
            var materials = renderer.sharedMaterials;
            var matrix = renderer.transform.localToWorldMatrix;
            for (int submesh = 0; submesh < mesh.subMeshCount && submesh < materials.Length; submesh++)
            {
                var material = materials[submesh];
                if (!material || material!.renderQueue >= (int)RenderQueue.AlphaTest ||
                    material.IsKeywordEnabled("_ALPHATEST_ON") || mesh.GetTopology(submesh) != MeshTopology.Triangles)
                    continue;
                var desc = mesh.GetSubMesh(submesh);
                int[] indices = mesh.GetIndices(submesh);
                if (desc.baseVertex < 0 || desc.indexStart < 0 || indices.Length != desc.indexCount ||
                    indices.Length % 3 != 0 || indices.Any(i => i < desc.baseVertex || i >= mesh.vertexCount))
                    continue;
                var positions = mesh.vertices;
                for (int i = 0; i < indices.Length; i += 3)
                {
                    var a = matrix.MultiplyPoint3x4(positions[indices[i]]);
                    var b = matrix.MultiplyPoint3x4(positions[indices[i + 1]]);
                    var c = matrix.MultiplyPoint3x4(positions[indices[i + 2]]);
                    var normal = Vector3.Cross(b - a, c - a);
                    if (normal.sqrMagnitude > 0.01f)
                        return (mesh, renderer, submesh, (a + b + c) / 3f, normal.normalized);
                }
            }
        }
        throw new InvalidOperationException("No CPU-verifiable opaque map surface was available for the GPU ray probe.");
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MeshRequest
    {
        public IntPtr Vertex, Index, Output;
        public ulong PositionOffset, IndexOffset;
        public uint PositionStride, VertexCount, IndexCount, IndexBits;
        public float M00, M01, M02, M03, M10, M11, M12, M13, M20, M21, M22, M23;
        public ulong Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct ProbeRay(Vector3 origin, float tMin, Vector3 direction, float tMax)
    {
        private readonly float ox = origin.x, oy = origin.y, oz = origin.z, near = tMin;
        private readonly float dx = direction.x, dy = direction.y, dz = direction.z, far = tMax;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DepthFrame
    {
        public fixed float Inverse[16], Directions[128];
        public uint Width, Height, LightCount, TestMask;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void Register(IntPtr registry);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void Unload();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SetShader(byte* bytes, uint length);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate ulong QueueMesh(ref MeshRequest mesh, ProbeRay* rays, uint count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate ulong QueueScene(MeshRequest* meshes, uint meshCount, ProbeRay* rays, uint count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate ulong QueueDepth(ref MeshRequest mesh, IntPtr depth, ref DepthFrame frame);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate ulong QueueDepthScene(MeshRequest* meshes, uint count, IntPtr depth, ref DepthFrame frame);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ReadDepthSummary(ulong ticket, out uint valid, out uint blocked);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int ReadTimings(ulong ticket, out double buildMs, out double traceMs, out double copyMs);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr GetCallback();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetEventId();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate uint GetStatus(byte* bytes, uint capacity);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int CanUnload();
}
