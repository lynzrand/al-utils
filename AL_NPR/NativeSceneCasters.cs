extern alias unity;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;
using Object = unity::UnityEngine.Object;

namespace AL_NPR;

public static unsafe partial class NativeMapRayProbe
{
    // Frozen diagnostic collection, independent of camera visibility. The GPU
    // audit reads original buffers once per mesh; tracing uses those same buffers.
    // Queue/keyword filtering excludes known alpha materials but does not prove
    // texture opacity or account for shader-specific discard and deformation.
    private sealed class SceneCasters : IDisposable
    {
        private readonly Dictionary<int, (GraphicsBuffer Vertex, GraphicsBuffer Index, VisibilityMeshBuffers Audit)> meshes = new();
        private readonly Dictionary<string, int> omitted = new();
        private readonly List<Mesh> bakedMeshes = new();
        private int submeshes, offscreen, skinnedSubmeshes;
        private long triangles;
        private Bounds bounds;
        private bool hasBounds;
        private (Vector3 Center, Vector3 Normal)? sample;
        internal string Summary => $"{submeshes} submeshes treated as opaque ({skinnedSubmeshes} baked character submeshes), {triangles:N0} triangles, " +
            $"{offscreen} offscreen submeshes; omitted [{string.Join(", ", omitted.Select(x => $"{x.Key}={x.Value}"))}]";

        internal MeshRequest[] Capture(IntPtr output, bool includeCharacter = false)
        {
            if (includeCharacter && Time.timeScale != 0f)
                throw new InvalidOperationException("Pause animation before baking diagnostic character casters.");
            int map = LayerMask.GetMask("Map");
            if (map == 0) throw new InvalidOperationException("The Map GameObject layer is unavailable.");
            var requests = new List<MeshRequest>();
            foreach (var renderer in Object.FindObjectsOfType<Renderer>())
            {
                if (!renderer.enabled || renderer.forceRenderingOff ||
                    renderer.shadowCastingMode == ShadowCastingMode.Off) continue;
                var skin = renderer.TryCast<SkinnedMeshRenderer>();
                bool character = includeCharacter && skin && (renderer.renderingLayerMask & 4) != 0;
                if (!character && (map & (1 << renderer.gameObject.layer)) == 0) continue;
                if (skin && !character) { Omit("skinned renderers"); continue; }
                var rigid = renderer.TryCast<MeshRenderer>();
                var mesh = character ? skin!.sharedMesh : rigid ? rigid!.GetComponent<MeshFilter>()?.sharedMesh : null;
                if (!mesh) { Omit("unsupported renderers"); continue; }
                if (character)
                {
                    var baked = new Mesh();
                    bakedMeshes.Add(baked);
                    skin!.BakeMesh(baked, false);
                    baked.UploadMeshData(false);
                    mesh = baked;
                }
                var materials = renderer.sharedMaterials;
                for (int submesh = 0; submesh < mesh!.subMeshCount; submesh++)
                {
                    var material = submesh < materials.Length ? materials[submesh] : null;
                    // Body materials use the alpha-test queue even for solid
                    // skin. Include them as an explicit opaque approximation
                    // for this frozen self-shadow experiment; hair and cloth
                    // cutouts still require material-aware ray intersections.
                    bool body = character && material && material!.shader &&
                        material.shader.name.StartsWith("AL/skin_body", StringComparison.Ordinal);
                    if (!material || !body && material!.renderQueue >= (int)RenderQueue.AlphaTest ||
                        material!.IsKeywordEnabled("_ALPHATEST_ON"))
                    { Omit("alpha or missing-material submeshes"); continue; }
                    if (mesh.GetTopology(submesh) != MeshTopology.Triangles)
                    { Omit("non-triangle submeshes"); continue; }
                    var desc = mesh.GetSubMesh(submesh);
                    if (desc.indexCount == 0) continue;
                    try
                    {
                        if (desc.baseVertex < 0 || desc.baseVertex >= mesh.vertexCount ||
                            desc.indexStart < 0 || desc.indexCount < 0 || desc.indexCount % 3 != 0)
                            throw new InvalidDataException("Invalid submesh range");
                        if (!meshes.TryGetValue(mesh.GetInstanceID(), out var buffers))
                        {
                            var audit = VisibilityMeshBuffers.Read(mesh);
                            var vertex = mesh.GetVertexBuffer(mesh.GetVertexAttributeStream(VertexAttribute.Position));
                            try
                            {
                                var index = mesh.GetIndexBuffer();
                                buffers = (vertex, index, audit);
                                meshes.Add(mesh.GetInstanceID(), buffers);
                            }
                            catch { vertex.Dispose(); throw; }
                        }
                        int[] indices = buffers.Audit.GetIndices(desc);
                        foreach (int i in indices)
                        {
                            if (i < desc.baseVertex || i >= mesh.vertexCount)
                                throw new InvalidDataException("Index exceeds rebased vertex domain");
                            var p = buffers.Audit.Positions[i];
                            if (!float.IsFinite(p.x) || !float.IsFinite(p.y) || !float.IsFinite(p.z))
                                throw new InvalidDataException("Nonfinite vertex position");
                        }
                        requests.Add(DescribeMesh(mesh, renderer, submesh, buffers.Vertex, buffers.Index, output));
                        if (hasBounds) bounds.Encapsulate(renderer.bounds);
                        else { bounds = renderer.bounds; hasBounds = true; }
                        if (sample is null)
                        {
                            var matrix = renderer.transform.localToWorldMatrix;
                            for (int i = 0; i < indices.Length; i += 3)
                            {
                                var a = matrix.MultiplyPoint3x4(buffers.Audit.Positions[indices[i]]);
                                var b = matrix.MultiplyPoint3x4(buffers.Audit.Positions[indices[i + 1]]);
                                var c = matrix.MultiplyPoint3x4(buffers.Audit.Positions[indices[i + 2]]);
                                var normal = Vector3.Cross(b - a, c - a);
                                if (normal.sqrMagnitude <= 0.01f) continue;
                                sample = ((a + b + c) / 3f, normal.normalized);
                                break;
                            }
                        }
                        submeshes++;
                        if (character) skinnedSubmeshes++;
                        triangles += desc.indexCount / 3;
                        if (!renderer.isVisible) offscreen++;
                    }
                    catch (Exception error) when (error is InvalidDataException or NotSupportedException or OverflowException)
                    { Omit(error.Message); }
                    if (requests.Count > 4096)
                        throw new InvalidOperationException("Opaque scene exceeds native 4096-submesh limit; no partial scene submitted.");
                }
            }
            if (requests.Count == 0) throw new InvalidOperationException("No audited opaque map submeshes. " + Summary);
            return requests.ToArray();
        }

        internal ProbeRay[] ValidationRays()
        {
            if (sample is not { } surface)
                throw new InvalidOperationException("No nondegenerate captured triangle for scene validation.");
            var (center, normal) = surface;
            return new ProbeRay[] {
                new(center + normal * 0.125f, 0.001f, -normal, 0.25f),
                new(center - normal * 0.125f, 0.001f, normal, 0.25f),
                new(bounds.max + Vector3.one, 0.001f, Vector3.right, 0.5f),
                new(center, 0.001f, Vector3.zero, 0.25f)
            };
        }

        private void Omit(string reason) => omitted[reason] = omitted.GetValueOrDefault(reason) + 1;

        public void Dispose()
        {
            foreach (var buffers in meshes.Values) { buffers.Index.Dispose(); buffers.Vertex.Dispose(); }
            meshes.Clear();
            foreach (var mesh in bakedMeshes) if (mesh) Object.Destroy(mesh);
            bakedMeshes.Clear();
        }
    }

    private static MeshRequest DescribeMesh(Mesh mesh, Renderer renderer, int submesh,
        GraphicsBuffer vertex, GraphicsBuffer index, IntPtr output)
    {
        var desc = mesh.GetSubMesh(submesh);
        int stride = mesh.GetVertexBufferStride(mesh.GetVertexAttributeStream(VertexAttribute.Position));
        uint indexBits = mesh.indexFormat == IndexFormat.UInt16 ? 16u : 32u;
        var matrix = renderer.transform.localToWorldMatrix;
        return new MeshRequest
        {
            Vertex = vertex.GetNativeBufferPtr(), Index = index.GetNativeBufferPtr(), Output = output,
            PositionOffset = checked((ulong)desc.baseVertex * (uint)stride + (uint)mesh.GetVertexAttributeOffset(VertexAttribute.Position)),
            IndexOffset = checked((ulong)desc.indexStart * (indexBits / 8)), PositionStride = (uint)stride,
            VertexCount = checked((uint)(mesh.vertexCount - desc.baseVertex)), IndexCount = (uint)desc.indexCount,
            IndexBits = indexBits,
            M00 = matrix.m00, M01 = matrix.m01, M02 = matrix.m02, M03 = matrix.m03,
            M10 = matrix.m10, M11 = matrix.m11, M12 = matrix.m12, M13 = matrix.m13,
            M20 = matrix.m20, M21 = matrix.m21, M22 = matrix.m22, M23 = matrix.m23
        };
    }
}
