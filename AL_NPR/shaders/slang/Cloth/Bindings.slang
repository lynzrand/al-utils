// Select the Unity interface before compiling any fabric or lighting module.
#ifdef CLOTH_CUTOUT_LAYOUT
__exported import ClothAlpha.MaterialProperties;
#else
__exported import Cloth.MaterialProperties;
#endif

#ifdef CLOTH_DEPTH_PASS
__exported import Cloth.DepthBindings;
#else
__exported import Cloth.ColorBindings;
#endif
