extern alias unity;
using System.Text;
using System.Text.Json;
using UnityEngine.Rendering.Universal;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;
using unity::UnityEngine.SceneManagement;
using Object = unity::UnityEngine.Object;

namespace AL_NPR;

// This is an on-demand snapshot of the current pose. It enumerates active
// casters independently of the camera and reports gaps in the opaque subset.
public static class VisibilitySnapshot
{
    private const uint MapRenderingLayer = 2;
    private const int ReceiverLimit = 4096;

    public static string Save(string path)
    {
        var mapLayer = (uint)LayerMask.GetMask("Map");
        if (mapLayer == 0) throw new InvalidOperationException("The Map GameObject layer is unavailable.");

        var capture = new Capture(mapLayer);
        foreach (var renderer in Object.FindObjectsOfType<Renderer>())
            capture.Add(renderer);
        foreach (var light in Object.FindObjectsOfType<Light>().OrderBy(light => light.GetInstanceID()))
            capture.Add(light);
        return capture.Write(path, SceneManager.GetActiveScene().name);
    }

    private readonly record struct Masks(uint GameObjectLayer, uint RenderingLayers);
    private readonly record struct Receiver(Vector3 Position, Vector3 Normal, Masks Masks);
    private readonly record struct MapLight(string Name, int InstanceId, Vector3 Direction, Vector3 Position,
        uint Type, uint Culling, uint LightingLayers, uint ShadowLayers, string StockShadows);

    private sealed class Capture(uint mapLayer)
    {
        private readonly List<Vector3> vertices = new();
        private readonly Dictionary<Masks, List<uint>> triangles = new();
        private readonly List<Receiver> receivers = new();
        private readonly List<MapLight> lights = new();
        private readonly Dictionary<int, VisibilityMeshBuffers> gpuMeshes = new();
        private readonly Dictionary<string, int> omitted = new();
        private readonly List<string> omissionExamples = new();
        private int casters, offscreen, skinned, gpuCasters, skippedSubmeshes;

        public void Add(Renderer renderer)
        {
            if (!renderer.enabled || renderer.forceRenderingOff ||
                renderer.shadowCastingMode == ShadowCastingMode.Off)
                return;

            var skin = renderer.TryCast<SkinnedMeshRenderer>();
            var mesh = skin ? skin!.sharedMesh : renderer.GetComponent<MeshFilter>()?.sharedMesh;
            if (!mesh)
            {
                Omit("no supported mesh", renderer);
                return;
            }

            Mesh? baked = null;
            try
            {
                if (skin)
                {
                    baked = new Mesh();
                    skin!.BakeMesh(baked, false);
                    mesh = baked;
                }
                AddMesh(renderer, mesh!, skin != null);
            }
            catch (Exception error)
            {
                Omit(error is InvalidDataException or NotSupportedException ? error.Message : error.GetType().Name,
                    renderer);
            }
            finally
            {
                if (baked) Object.Destroy(baked);
            }
        }

        private void AddMesh(Renderer renderer, Mesh mesh, bool isSkinned)
        {
            var materials = renderer.sharedMaterials;
            var submeshes = new List<int>();
            int vertexCount = mesh.vertexCount;
            for (int submesh = 0; submesh < mesh.subMeshCount; submesh++)
            {
                var material = submesh < materials.Length ? materials[submesh] : null;
                if (!material || material!.renderQueue >= (int)RenderQueue.AlphaTest ||
                    material.IsKeywordEnabled("_ALPHATEST_ON") || mesh.GetTopology(submesh) != MeshTopology.Triangles)
                {
                    skippedSubmeshes++;
                    continue;
                }
                if (mesh.GetIndexCount(submesh) > 0) submeshes.Add(submesh);
            }
            if (submeshes.Count == 0) return;

            VisibilityMeshBuffers? gpu = null;
            if (!mesh.isReadable)
            {
                int id = mesh.GetInstanceID();
                if (!gpuMeshes.TryGetValue(id, out gpu))
                    gpuMeshes.Add(id, gpu = VisibilityMeshBuffers.Read(mesh));
            }

            var accepted = new List<int[]>(submeshes.Count);
            foreach (int submesh in submeshes)
            {
                int[] indices = gpu is null ? mesh.GetIndices(submesh) : gpu.GetIndices(mesh.GetSubMesh(submesh));
                if (indices.Length % 3 != 0 || indices.Any(index => (uint)index >= (uint)vertexCount))
                    throw new InvalidDataException("Invalid triangle indices.");
                accepted.Add(indices);
            }

            var transform = renderer.transform.localToWorldMatrix;
            Vector3[] local = gpu is null ? mesh.vertices : gpu.Positions;
            if (local.Length != vertexCount) throw new InvalidDataException("Vertex count changed during capture.");
            var world = new Vector3[local.Length];
            for (int index = 0; index < world.Length; index++)
            {
                var v = local[index];
                world[index] = new Vector3(
                    transform.m00 * v.x + transform.m01 * v.y + transform.m02 * v.z + transform.m03,
                    transform.m10 * v.x + transform.m11 * v.y + transform.m12 * v.z + transform.m13,
                    transform.m20 * v.x + transform.m21 * v.y + transform.m22 * v.z + transform.m23);
                if (!Finite(world[index])) throw new InvalidDataException("Non-finite world-space vertex.");
            }

            var masks = new Masks(1u << renderer.gameObject.layer, renderer.renderingLayerMask);
            if (!triangles.TryGetValue(masks, out var list)) triangles.Add(masks, list = new List<uint>());
            uint offset = (uint)vertices.Count;
            vertices.AddRange(world);
            bool sampleReceiver = (masks.GameObjectLayer & mapLayer) != 0 && renderer.isVisible &&
                renderer.receiveShadows && renderer.shadowCastingMode != ShadowCastingMode.ShadowsOnly;
            foreach (var indices in accepted)
            {
                foreach (int index in indices) list.Add(offset + (uint)index);
                if (sampleReceiver) AddReceivers(world, indices, masks);
            }
            casters++;
            if (!renderer.isVisible) offscreen++;
            if (isSkinned) skinned++;
            if (gpu is not null) gpuCasters++;
        }

        private void AddReceivers(Vector3[] world, int[] indices, Masks masks)
        {
            // Triangle centers preserve a known receiver surface and normal.
            // These are sparse samples, not a reconstruction of the framebuffer.
            int step = Math.Max(1, indices.Length / 24) * 3;
            for (int index = 0; index < indices.Length && receivers.Count < ReceiverLimit; index += step)
            {
                var a = world[indices[index]];
                var b = world[indices[index + 1]];
                var c = world[indices[index + 2]];
                var normal = Vector3.Cross(b - a, c - a);
                float length = normal.magnitude;
                if (length <= 1e-7f || !float.IsFinite(length)) continue;
                receivers.Add(new Receiver((a + b + c) / 3f, normal / length, masks));
            }
        }

        public void Add(Light light)
        {
            if (!light.enabled || light.intensity <= 0 ||
                light.type is not (LightType.Directional or LightType.Point or LightType.Spot) ||
                ((uint)light.cullingMask & mapLayer) == 0 ||
                light.bakingOutput.lightmapBakeType == LightmapBakeType.Baked)
                return;
            var settings = light.GetComponent<UniversalAdditionalLightData>();
            if (!settings || (settings.renderingLayers & MapRenderingLayer) == 0) return;

            var direction = -light.transform.forward;
            var position = light.transform.position;
            if (!Finite(direction) || !Finite(position)) return;
            uint shadowLayers = settings.customShadowLayers ? settings.shadowRenderingLayers : settings.renderingLayers;
            lights.Add(new MapLight(light.name, light.GetInstanceID(), direction, position,
                light.type == LightType.Directional ? 0u : 1u, (uint)light.cullingMask,
                settings.renderingLayers, shadowLayers, light.shadows.ToString()));
        }

        private void Omit(string reason, Renderer renderer)
        {
            omitted[reason] = omitted.GetValueOrDefault(reason) + 1;
            if (omissionExamples.Count < 32) omissionExamples.Add($"{reason}: {renderer.name}");
        }

        public string Write(string path, string scene)
        {
            int indexCount = triangles.Values.Sum(group => group.Count);
            if (indexCount == 0 || receivers.Count == 0 || lights.Count == 0)
                throw new InvalidOperationException(
                    $"Snapshot is missing casters, receivers or map lights ({indexCount / 3}, {receivers.Count}, {lights.Count}).");

            using (var writer = new BinaryWriter(File.Open(path, FileMode.CreateNew)))
            {
                writer.Write(Encoding.ASCII.GetBytes("ALVIS001"));
                writer.Write(vertices.Count);
                writer.Write(indexCount);
                writer.Write(triangles.Count);
                writer.Write(receivers.Count);
                writer.Write(lights.Count);
                foreach (var vertex in vertices) WriteVector(writer, vertex);
                foreach (var group in triangles.Values)
                    foreach (uint index in group) writer.Write(index);
                int first = 0;
                foreach (var (masks, group) in triangles)
                {
                    writer.Write(first);
                    writer.Write(group.Count);
                    writer.Write(masks.GameObjectLayer);
                    writer.Write(masks.RenderingLayers);
                    first += group.Count;
                }
                foreach (var receiver in receivers)
                {
                    WriteVector(writer, receiver.Position);
                    writer.Write(1f);
                    WriteVector(writer, receiver.Normal);
                    writer.Write(0f);
                    writer.Write(receiver.Masks.GameObjectLayer);
                    writer.Write(receiver.Masks.RenderingLayers);
                    writer.Write(1u);
                    writer.Write(1u);
                }
                foreach (var light in lights)
                {
                    WriteVector(writer, light.Direction);
                    writer.Write(light.Type);
                    WriteVector(writer, light.Position);
                    writer.Write(1u);
                    writer.Write(light.Culling);
                    writer.Write(light.LightingLayers);
                    writer.Write(light.ShadowLayers);
                    // Measure visibility for every captured light, including
                    // lights whose stock shadow mode is None.
                    writer.Write(1u);
                }
            }

            var report = new
            {
                Scene = scene, Time.frameCount, Casters = casters, OffscreenCasters = offscreen, SkinnedCasters = skinned,
                GpuReadbackCasters = gpuCasters, GpuReadbackMeshes = gpuMeshes.Count,
                Vertices = vertices.Count, Triangles = indexCount / 3, Receivers = receivers.Count,
                SkippedSubmeshes = skippedSubmeshes, OmittedRenderers = omitted, OmissionExamples = omissionExamples,
                Lights = lights.Select((light, index) => new { Index = index, light.Name, light.InstanceId,
                    light.Type, light.Culling, light.LightingLayers, light.ShadowLayers, light.StockShadows })
            };
            File.WriteAllText(path + ".json", JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            return $"{scene}: {casters} casters ({offscreen} offscreen), {indexCount / 3} triangles, {receivers.Count} receivers, {lights.Count} lights";
        }
    }

    private static bool Finite(Vector3 v) => float.IsFinite(v.x) && float.IsFinite(v.y) && float.IsFinite(v.z);

    private static void WriteVector(BinaryWriter writer, Vector3 vector)
    {
        writer.Write(vector.x);
        writer.Write(vector.y);
        writer.Write(vector.z);
    }
}
