extern alias unity;
using System.Runtime.InteropServices;
using unity::UnityEngine;

namespace AL_NPR;

public static unsafe partial class NativeMapRayProbe
{
    // Frozen snapshot only: animation and transforms must remain unchanged
    // through every query. ClearDepth releases the handle and its buffers.
    public static string PrepareDepthScene(bool includeCharacter = false)
    {
        if (depthSession is null) throw new InvalidOperationException("Warm up the depth ray probe first.");
        depthSession.PrepareScene(includeCharacter);
        return DepthStatus();
    }

    public static string ClearDepthQuery()
    {
        MapDirectional.ClearVisibility();
        depthSession?.RetireDepth(true);
        return DepthStatus();
    }

    private sealed partial class Session
    {
        private ulong retainedScene;

        internal void PrepareScene(bool includeCharacter)
        {
            if (Time.timeScale != 0f || retainedScene != 0 || visibility is not null || canUnload() == 0)
                throw new InvalidOperationException("Pause animation and clear the previous depth probe first.");
            var casters = new SceneCasters();
            try
            {
                var meshes = casters.Capture(IntPtr.Zero, includeCharacter);
                fixed (MeshRequest* inputs = meshes)
                    retainedScene = Export<CreateScene>("ALRAY_CreateScene")(inputs, (uint)meshes.Length);
                if (retainedScene == 0)
                    throw new InvalidOperationException("Native scene build rejected. " + NativeStatus());
                sceneCasters = casters;
                result = "Queued retained scene: " + casters.Summary;
                IssueEvent();
            }
            catch
            {
                if (retainedScene == 0) casters.Dispose();
                throw;
            }
        }

        private void ReleaseRetainedScene()
        {
            if (retainedScene == 0) return;
            Export<ReleaseScene>("ALRAY_ReleaseScene")(retainedScene);
            retainedScene = 0;
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate ulong CreateScene(MeshRequest* meshes, uint count);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int SceneReady(ulong handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int ReleaseScene(ulong handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate ulong QueueRetainedDepth(ulong handle, IntPtr output, IntPtr depth, ref DepthFrame frame, uint diagnostic);
    }
}
