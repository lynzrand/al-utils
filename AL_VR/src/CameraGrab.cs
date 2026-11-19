extern alias unity;
using unity::UnityEngine;

namespace AL_VR;

// Keep the grabbed world point under the hand while translating and yawing the
// tracking origin. Headset pitch/roll remain untouched to preserve a level world.
internal sealed class CameraGrab
{
    internal Vector3 Offset { get; private set; }
    internal float Yaw { get; private set; }
    private uint? device;
    private Vector3 grabbedPoint;
    private float handYaw, initialYaw;

    internal Quaternion Rotation(Quaternion basis) => Quaternion.Euler(0, Yaw, 0) * basis;

    internal void Update(uint hand, bool held, bool clicked, Vector3 position, Quaternion rotation,
        Vector3 anchor, Vector3 trackingOrigin, Quaternion basis, float scale)
    {
        if (!held) { Release(); return; }
        if (device != hand)
        {
            Release();
            if (!clicked) return;
            device = hand;
            initialYaw = Yaw;
            handYaw = Heading(rotation);
            grabbedPoint = anchor + Offset + Rotation(basis) * ((position - trackingOrigin) * scale);
        }
        Yaw = initialYaw - Mathf.DeltaAngle(handYaw, Heading(rotation));
        Offset = grabbedPoint - anchor - Rotation(basis) * ((position - trackingOrigin) * scale);
    }

    private static float Heading(Quaternion rotation)
    {
        var forward = rotation * Vector3.forward;
        if (forward.x * forward.x + forward.z * forward.z > 0.001f)
            return Mathf.Atan2(forward.x, forward.z) * Mathf.Rad2Deg;
        var right = rotation * Vector3.right;
        return Mathf.Atan2(right.x, right.z) * Mathf.Rad2Deg - 90;
    }

    internal void Release() => device = null;
    internal void Reset() { Release(); Offset = Vector3.zero; Yaw = 0; }
}
