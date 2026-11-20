@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b %errorlevel%
pushd "%~dp0\..\.."
if not exist artifacts\npr\unity-visibility-interop mkdir artifacts\npr\unity-visibility-interop
set "cmake_location=-S AL_NPR\shaders -B artifacts\npr\unity-visibility-interop"
if exist artifacts\npr\unity-visibility-interop\CMakeCache.txt set "cmake_location=artifacts\npr\unity-visibility-interop"
cmake %cmake_location% -G "NMake Makefiles" -DSHADER_TARGET=dxil
if errorlevel 1 goto failed
cmake --build artifacts\npr\unity-visibility-interop --target UnityInteropWrite
if errorlevel 1 goto failed
cl /nologo /utf-8 /std:c++17 /EHsc /O2 /W4 /WX /MD /LD /I"C:\Program Files\Unity 2022.3.22f1\Editor\Data\PluginAPI" AL_NPR\tools\unity_visibility_interop.cpp /Foartifacts\npr\unity-visibility-interop\unity_visibility_interop.obj /Feartifacts\npr\unity-visibility-interop\ALVisibilityInterop.dll /link d3d12.lib
if errorlevel 1 goto failed
popd
exit /b 0
:failed
popd
exit /b 1
