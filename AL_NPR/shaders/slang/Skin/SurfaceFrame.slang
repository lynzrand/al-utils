// Reconstruct the normal of an animated height field on either side of the mesh.
public float3 sweatNormalWS(float3 positionWS, float3 normalWS, float height, float strength)
{
    float3 dx = ddx_coarse(positionWS);
    float3 dy = ddy_coarse(positionWS);
    float3 u = cross(dy, normalWS);
    float3 v = cross(normalWS, dx);
    float determinant = dot(dx, u);
    float3 gradient = mad(ddx_coarse(height), u, ddy_coarse(height) * v);
    return normalize(abs(determinant) * normalWS - (sign(determinant) * strength) * gradient);
}
