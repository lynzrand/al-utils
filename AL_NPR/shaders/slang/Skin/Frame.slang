// The face outline prepass uses Unity's smaller global buffer layout.
#if SKIN_FACE && SKIN_PREPASS
cbuffer Globals : register(b0)
{
    float4 _ScaledScreenParams : packoffset(c3);
    float _AlphaToMaskAvailable : packoffset(c4.z);
    float4 _MainLightPosition : packoffset(c5);
    float4 _MainLightColor : packoffset(c6);
    float3 _WorldSpaceCameraPos : packoffset(c21);
    float4 _ProjectionParams : packoffset(c22);
    float4 unity_OrthoParams : packoffset(c25);
    float4 _ScaleBiasRt : packoffset(c27);
    float4 unity_FogParams : packoffset(c60);
    float4 unity_FogColor : packoffset(c61);
    float4 unity_MatrixV0 : packoffset(c66);
    float4 unity_MatrixV1 : packoffset(c67);
    float4 unity_MatrixV2 : packoffset(c68);
};
#define SKIN_DRAW_SLOT b1
#else
cbuffer Globals : register(b0)
{
    float4 _ScaledScreenParams : packoffset(c3);
    float2 _GlobalMipBias : packoffset(c4);
    float _AlphaToMaskAvailable : packoffset(c4.z);
    float4 _MainLightPosition : packoffset(c5);
    float4 _MainLightColor : packoffset(c6);
    float4 _FPParams0 : packoffset(c15);
    float4 _FPParams1 : packoffset(c16);
    float4 _FPParams2 : packoffset(c17);
    float4 _TimeParameters : packoffset(c23);
    float3 _WorldSpaceCameraPos : packoffset(c25);
    float4 _ProjectionParams : packoffset(c26);
    float4 unity_OrthoParams : packoffset(c29);
    float4 _ScaleBiasRt : packoffset(c31);
    float4 unity_FogParams : packoffset(c64);
    float4 unity_FogColor : packoffset(c65);
    float4 unity_MatrixV0 : packoffset(c70);
    float4 unity_MatrixV1 : packoffset(c71);
    float4 unity_MatrixV2 : packoffset(c72);
};
#define SKIN_DRAW_SLOT b4
#endif

cbuffer UnityPerDraw : register(SKIN_DRAW_SLOT)
{
    float4 objectToWorld0 : packoffset(c0);
    float4 objectToWorld1 : packoffset(c1);
    float4 objectToWorld2 : packoffset(c2);
    float4 worldToObject0 : packoffset(c4);
    float4 worldToObject1 : packoffset(c5);
    float4 worldToObject2 : packoffset(c6);
    float4 renderingLayer : packoffset(c10);
    float4 lightData : packoffset(c11);
    float4 specCubeHDR : packoffset(c15);
    SHCoefficients probe : packoffset(c25);
};
