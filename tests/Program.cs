using AL_PovX;

var gate = new RepeatGate();
void Check(bool expected, bool pressed, float time, string name)
{
    if (gate.Tick(pressed, time, 0.15f) != expected) throw new Exception(name);
}
Check(false, false, 0, "Idle must not click");
Check(true, true, 1, "Initial press must click immediately");
Check(false, true, 1.1f, "Held key must respect interval");
Check(true, true, 1.16f, "Held key must repeat");
Check(true, true, 8, "A stalled frame produces one click");
Check(false, true, 8, "No catch-up burst");
Check(false, false, 8.01f, "Release cancels repeat");
Check(true, true, 8.02f, "Repress is immediate");
Check(false, false, 8.03f, "Unavailable UI resets repeat");
Check(true, true, 8.04f, "Available UI can resume immediately");
Console.WriteLine("10 repeat-gate checks passed.");

// Regression: changing scene poses must recenter once after the transition,
// without resetting on every animation frame or leaking state across scenes.
var poses = new PoseChangeTracker();
void Pose(bool expected, long scene, int category, int pose, bool changed, bool transitioning, string name)
{
    if (poses.Observe(scene, category, pose, changed, transitioning) != expected) throw new Exception(name);
}
Pose(false, 1, 0, 0, false, false, "Initial pose is baseline");
Pose(false, 1, 0, 1, true, true, "Defer reset during transition");
Pose(false, 1, 0, 1, true, true, "No reset during another transition frame");
Pose(true, 1, 0, 1, true, false, "Reset when pose settles");
Pose(false, 1, 0, 1, true, false, "Sticky change flag must not repeat reset");
Pose(false, 1, 0, 1, false, true, "Ordinary animation transition is not a pose change");
Pose(false, 1, 0, 1, false, false, "Ordinary transition end does not reset");
Pose(true, 1, 0, 1, true, false, "Same-pose reselection resets");
Pose(true, 1, 1, 1, false, false, "Category change resets");
Pose(false, 1, 1, 2, false, true, "Queue pending reset");
Pose(false, 2, 0, 0, false, false, "New scene clears pending reset");
poses.Clear();
Pose(false, 2, 1, 1, true, false, "New POV session establishes fresh baseline");
Console.WriteLine("12 pose-change checks passed.");
