@echo off
setlocal
pushd "%~dp0"
if not exist "AmanatsuLocation.exe" (
  echo Extract this package beside AmanatsuLocation.exe first.
  goto :failed
)
set "toolsdir=BepInEx\cache\AL_NPR\python311"
if not exist "%toolsdir%\Scripts\python.exe" (
  py -3.11 -m venv "%toolsdir%"
  if errorlevel 1 goto :failed
)
"%toolsdir%\Scripts\python.exe" -m pip install --disable-pip-version-check "UnityPy==1.25.4" "lz4==4.4.5"
if errorlevel 1 goto :failed
"%toolsdir%\Scripts\python.exe" "BepInEx\plugins\AL_NPR\release_delta.py" "." "BepInEx\plugins\AL_NPR\lighting.patch"
if errorlevel 1 goto :failed
popd
pause
exit /b 0
:failed
echo Preparation failed. Check that 64-bit Python 3.11 and Amanatsu Location 1.0.4 are installed.
popd
pause
exit /b 1
