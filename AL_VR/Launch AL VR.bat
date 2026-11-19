@echo off
setlocal
pushd "%~dp0" || exit /b 1
if not exist AmanatsuLocation.exe (
    echo Place this launcher next to AmanatsuLocation.exe.
    popd
    exit /b 1
)
start "" ".\AmanatsuLocation.exe" -force-d3d11 --al-vr %*
set "launch_status=%errorlevel%"
popd
exit /b %launch_status%
