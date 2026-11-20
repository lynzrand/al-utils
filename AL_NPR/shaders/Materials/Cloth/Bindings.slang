// Select the Unity interface before compiling any fabric or lighting module.
#ifdef CLOTH_CUTOUT_LAYOUT
__exported import Materials.ClothAlpha.MaterialProperties;
#else
__exported import Materials.Cloth.MaterialProperties;
#endif

#ifdef CLOTH_DEPTH_PASS
__exported import Materials.Cloth.DepthBindings;
#else
__exported import Materials.Cloth.ColorBindings;
#endif
