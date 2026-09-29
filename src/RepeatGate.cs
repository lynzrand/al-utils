namespace AL_PovX;

// One immediate click, then at most one per interval; never catch up after a stall.
internal sealed class RepeatGate
{
    private bool held;
    private float next;

    internal bool Tick(bool pressed, float now, float interval)
    {
        if (!pressed) { held = false; return false; }
        if (held && now < next) return false;
        held = true;
        next = now + interval;
        return true;
    }
}
