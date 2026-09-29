namespace AL_PovX;

internal sealed class PoseChangeTracker
{
    private bool initialized, pending, wasChanged;
    private long scene;
    private int category, pose;

    internal bool Observe(long sceneId, int categoryId, int poseId, bool changed, bool transitioning)
    {
        if (!initialized || scene != sceneId)
        {
            initialized = true;
            scene = sceneId;
            category = categoryId;
            pose = poseId;
            wasChanged = changed;
            pending = false;
            return false;
        }
        pending |= category != categoryId || pose != poseId || (changed && !wasChanged);
        category = categoryId;
        pose = poseId;
        wasChanged = changed;
        if (!pending || transitioning) return false;
        pending = false;
        return true;
    }

    internal void Clear() { initialized = pending = wasChanged = false; }
}
