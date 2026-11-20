@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0\..\.."
if not exist artifacts\npr\unity-ray-probe mkdir artifacts\npr\unity-ray-probe
set "cmake_location=-S AL_NPR\shaders -B artifacts\npr\unity-ray-probe"
if exist artifacts\npr\unity-ray-probe\CMakeCache.txt set "cmake_location=artifacts\npr\unity-ray-probe"
cmake %cmake_location% -G "NMake Makefiles" -DSHADER_TARGET=dxil
if errorlevel 1 goto failed
cmake --build artifacts\npr\unity-ray-probe --target UnityRayProbe UnityDepthRayVisibility
if errorlevel 1 goto failed
cl /nologo /utf-8 /std:c++17 /EHsc /O2 /W4 /WX /MD /LD /I"C:\Program Files\Unity 2022.3.22f1\Editor\Data\PluginAPI" AL_NPR\tools\unity_visibility_ray_probe.cpp /Foartifacts\npr\unity-ray-probe\unity_visibility_ray_probe.obj /Feartifacts\npr\unity-ray-probe\ALVisibilityRayProbe.dll /link d3d12.lib
if errorlevel 1 goto failed
cl /nologo /utf-8 /std:c++17 /EHsc /O2 /W4 /WX /MD /LD /DAL_DEPTH_RAYS /I"C:\Program Files\Unity 2022.3.22f1\Editor\Data\PluginAPI" AL_NPR\tools\unity_visibility_ray_probe.cpp /Foartifacts\npr\unity-ray-probe\unity_depth_ray_visibility.obj /Feartifacts\npr\unity-ray-probe\ALDepthVisibility.dll /link d3d12.lib
if errorlevel 1 goto failed
popd
exit /b 0
:failed
popd
exit /b 1
