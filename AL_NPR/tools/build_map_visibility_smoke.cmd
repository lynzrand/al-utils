@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0\..\.."
if not exist artifacts\npr\map-visibility mkdir artifacts\npr\map-visibility
"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe" -T cs_6_5 -E Main -WX -Ges -Gis -Fo artifacts\npr\map-visibility\MapLightVisibility.dxil -Fc artifacts\npr\map-visibility\MapLightVisibility.asm AL_NPR\shaders\MapLightVisibility.hlsl
if errorlevel 1 goto failed
cl /nologo /std:c++17 /EHsc /O2 /W4 /WX /MD AL_NPR\tools\map_visibility_smoke.cpp /Foartifacts\npr\map-visibility\map_visibility_smoke.obj /Feartifacts\npr\map-visibility\map_visibility_smoke.exe /link d3d12.lib dxgi.lib
if errorlevel 1 goto failed
cl /nologo /std:c++17 /EHsc /W4 /WX /MD /LD AL_NPR\tools\dxr_device_probe.cpp /Foartifacts\npr\map-visibility\dxr_device_probe.obj /Feartifacts\npr\map-visibility\dxr_device_probe.dll
if errorlevel 1 goto failed
popd
exit /b 0
:failed
popd
exit /b 1
