@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0\..\.."
if not exist artifacts\npr\unity-ray-probe mkdir artifacts\npr\unity-ray-probe
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe" -T cs_6_5 -E Main -WX -Ges -Gis -Fo artifacts\npr\unity-ray-probe\UnityRayProbe.dxil AL_NPR\shaders\UnityRayProbe.hlsl
if errorlevel 1 goto failed
cl /nologo /utf-8 /std:c++17 /EHsc /O2 /W4 /WX /MD /LD /I"C:\Program Files\Unity 2022.3.22f1\Editor\Data\PluginAPI" AL_NPR\tools\unity_visibility_ray_probe.cpp /Foartifacts\npr\unity-ray-probe\unity_visibility_ray_probe.obj /Feartifacts\npr\unity-ray-probe\ALVisibilityRayProbe.dll /link d3d12.lib
if errorlevel 1 goto failed
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe" -T cs_6_5 -E Main -WX -Ges -Gis -Fo artifacts\npr\unity-ray-probe\UnityDepthRayVisibility.dxil AL_NPR\shaders\UnityDepthRayVisibility.hlsl
if errorlevel 1 goto failed
cl /nologo /utf-8 /std:c++17 /EHsc /O2 /W4 /WX /MD /LD /DAL_DEPTH_RAYS /I"C:\Program Files\Unity 2022.3.22f1\Editor\Data\PluginAPI" AL_NPR\tools\unity_visibility_ray_probe.cpp /Foartifacts\npr\unity-ray-probe\unity_depth_ray_visibility.obj /Feartifacts\npr\unity-ray-probe\ALDepthVisibility.dll /link d3d12.lib
if errorlevel 1 goto failed
popd
exit /b 0
:failed
popd
exit /b 1
