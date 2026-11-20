import AmbientProbe;

// The face outline prepass uses Unity's smaller global buffer layout.
#if SKIN_FACE && SKIN_PREPASS
public cbuffer Globals : register(b0)
{
    public float4 _ScaledScreenParams : packoffset(c3);
    public float _AlphaToMaskAvailable : packoffset(c4.z);
    public float4 _MainLightPosition : packoffset(c5);
    public float4 _MainLightColor : packoffset(c6);
    public float3 _WorldSpaceCameraPos : packoffset(c21);
    public float4 _ProjectionParams : packoffset(c22);
    public float4 unity_OrthoParams : packoffset(c25);
    public float4 _ScaleBiasRt : packoffset(c27);
    public float4 unity_FogParams : packoffset(c60);
    public float4 unity_FogColor : packoffset(c61);
    public float4 unity_MatrixV0 : packoffset(c66);
    public float4 unity_MatrixV1 : packoffset(c67);
    public float4 unity_MatrixV2 : packoffset(c68);
};
#define SKIN_DRAW_SLOT b1
#else
public cbuffer Globals : register(b0)
{
    public float4 _ScaledScreenParams : packoffset(c3);
    public float2 _GlobalMipBias : packoffset(c4);
    public float _AlphaToMaskAvailable : packoffset(c4.z);
    public float4 _MainLightPosition : packoffset(c5);
    public float4 _MainLightColor : packoffset(c6);
    public float4 _FPParams0 : packoffset(c15);
    public float4 _FPParams1 : packoffset(c16);
    public float4 _FPParams2 : packoffset(c17);
    public float4 _TimeParameters : packoffset(c23);
    public float3 _WorldSpaceCameraPos : packoffset(c25);
    public float4 _ProjectionParams : packoffset(c26);
    public float4 unity_OrthoParams : packoffset(c29);
    public float4 _ScaleBiasRt : packoffset(c31);
    public float4 unity_FogParams : packoffset(c64);
    public float4 unity_FogColor : packoffset(c65);
    public float4 unity_MatrixV0 : packoffset(c70);
    public float4 unity_MatrixV1 : packoffset(c71);
    public float4 unity_MatrixV2 : packoffset(c72);
};
#define SKIN_DRAW_SLOT b4
#endif

public cbuffer UnityPerDraw : register(SKIN_DRAW_SLOT)
{
    public float4 objectToWorld0 : packoffset(c0);
    public float4 objectToWorld1 : packoffset(c1);
    public float4 objectToWorld2 : packoffset(c2);
    public float4 worldToObject0 : packoffset(c4);
    public float4 worldToObject1 : packoffset(c5);
    public float4 worldToObject2 : packoffset(c6);
    public float4 renderingLayer : packoffset(c10);
    public float4 lightData : packoffset(c11);
    public float4 specCubeHDR : packoffset(c15);
    public SHCoefficients probe : packoffset(c25);
};
