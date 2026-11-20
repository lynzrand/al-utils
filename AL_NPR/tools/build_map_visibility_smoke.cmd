@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0\..\.."
if not exist artifacts\npr\map-visibility mkdir artifacts\npr\map-visibility
cmake -S AL_NPR\shaders\slang -B artifacts\npr\map-visibility -G "NMake Makefiles" -DSHADER_TARGET=dxil
if errorlevel 1 goto failed
cmake --build artifacts\npr\map-visibility --target MapLightVisibilityAssembly
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
