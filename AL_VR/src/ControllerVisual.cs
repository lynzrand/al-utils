extern alias unity;

using System.Runtime.InteropServices;
using UnityEngine;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;
using Object = unity::UnityEngine.Object;

namespace AL_VR;

internal sealed class ControllerVisual : IDisposable
{
    private Mesh? model, marker;
    private Material? body, laser;
    private uint? device;
    private bool modelPending, initialized;

    internal void Draw(OpenVrController input, bool panelOpen, bool moveCameraMode, Camera left, Camera right, Vector3 worldOrigin,
        Quaternion trackingToWorld, float scale, int layer)
    {
        if (!initialized)
        {
            initialized = true;
            var shader = Shader.Find("Universal Render Pipeline/Unlit");
            if (!shader)
                shader = Shader.Find("Unlit/Color");
            if (!shader)
            {
                Plugin.Instance.Log.LogWarning("AL SteamVR could not find an unlit shader for the controller and pointer.");
                return;
            }
            body = new Material(shader) { color = new Color(0.32f, 0.36f, 0.42f) };
            laser = new Material(shader) { color = new Color(0.16f, 0.9f, 1) };
            var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
            cube.SetActive(false);
            marker = cube.GetComponent<MeshFilter>().sharedMesh;
            Object.Destroy(cube);
        }
        if (!marker || !body || !laser)
            return;
        laser!.color = moveCameraMode ? new Color(1, 0.55f, 0.08f) : new Color(0.16f, 0.9f, 1);

        if (device != input.Device)
        {
            if (model) Object.Destroy(model);
            model = null;
            device = input.Device;
            modelPending = true;
        }
        if (modelPending)
        {
            int result = OpenVr.AlVrLoadControllerModel(input.Device, out var address);
            modelPending = result == 0;
            if (result > 0)
            {
                try { model = CopyMesh(Marshal.PtrToStructure<OpenVrRenderModel>(address)); }
                finally { OpenVr.AlVrFreeControllerModel(address); }
                if (model)
                    Plugin.Instance.Log.LogDebug($"AL SteamVR loaded the render model for controller {input.Device}.");
            }
        }

        var grip = input.GripPose;
        var gripPosition = worldOrigin + trackingToWorld * (grip.Position * scale);
        var gripRotation = trackingToWorld * grip.Rotation;
        var bodyScale = model ? Vector3.one : new Vector3(0.045f, 0.045f, 0.11f);
        DrawInEyes(model ? model! : marker!, Matrix4x4.TRS(gripPosition, gripRotation, bodyScale * scale), body!, layer, left, right);

        {
            var aim = input.AimPose;
            var aimPosition = worldOrigin + trackingToWorld * (aim.Position * scale);
            var aimRotation = trackingToWorld * aim.Rotation;
            var direction = aimRotation * Vector3.forward;
            float distance = panelOpen && input.PointsAtPanel ? input.RayLength * scale : 5 * scale;
            if (!(panelOpen && input.PointsAtPanel) &&
                Physics.Raycast(aimPosition, direction, out RaycastHit hit, distance, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore))
                distance = hit.distance;
            var rayCenter = aimPosition + direction * (distance * 0.5f);
            var rayScale = new Vector3(0.003f * scale, 0.003f * scale, distance);
            DrawInEyes(marker!, Matrix4x4.TRS(rayCenter, aimRotation, rayScale), laser!, layer, left, right);
            DrawInEyes(marker!, Matrix4x4.TRS(aimPosition + direction * distance, aimRotation, Vector3.one * (0.01f * scale)), laser!, layer, left, right);
        }
    }

    private static void DrawInEyes(Mesh mesh, Matrix4x4 pose, Material material, int layer, Camera left, Camera right)
    {
        Graphics.DrawMesh(mesh, pose, material, layer, left, 0, null, ShadowCastingMode.Off, false);
        Graphics.DrawMesh(mesh, pose, material, layer, right, 0, null, ShadowCastingMode.Off, false);
    }

    private static Mesh? CopyMesh(OpenVrRenderModel model)
    {
        if (model.Vertices == IntPtr.Zero || model.Indices == IntPtr.Zero ||
            model.VertexCount is 0 or > 65535 || model.TriangleCount is 0 or > 262144)
            return null;

        // Each OpenVR vertex contains eight floats. Reflect Z for Unity and
        // reverse the triangle winding to keep the outside faces visible.
        var data = new float[model.VertexCount * 8];
        Marshal.Copy(model.Vertices, data, 0, data.Length);
        var positions = new Vector3[model.VertexCount];
        for (int vertex = 0; vertex < positions.Length; ++vertex)
        {
            int offset = vertex * 8;
            positions[vertex] = new Vector3(data[offset], data[offset + 1], -data[offset + 2]);
        }

        var nativeIndices = new short[model.TriangleCount * 3];
        Marshal.Copy(model.Indices, nativeIndices, 0, nativeIndices.Length);
        var indices = new int[nativeIndices.Length];
        for (int index = 0; index < indices.Length; index += 3)
        {
            indices[index] = (ushort)nativeIndices[index];
            indices[index + 1] = (ushort)nativeIndices[index + 2];
            indices[index + 2] = (ushort)nativeIndices[index + 1];
        }
        if (indices.Any(index => index >= positions.Length))
            return null;

        return new Mesh { name = "AL SteamVR Controller", vertices = positions, triangles = indices };
    }

    public void Dispose()
    {
        if (model) Object.Destroy(model);
        if (body) Object.Destroy(body);
        if (laser) Object.Destroy(laser);
    }
}
