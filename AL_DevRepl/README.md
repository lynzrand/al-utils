# Amanatsu Location development REPL

The BepInEx IL2CPP plugin evaluates C# on Unity's main thread through a Windows named pipe restricted to the Windows account running the game. It uses the compiler already installed with Runtime Unity Editor. Variables persist for the current game process.

Build from the workspace and copy `AL_DevRepl/bin/Release/net6.0/AL_DevRepl.dll` into `BepInEx/plugins/AL_DevRepl/`. Create an empty `EnableNextLaunch` file beside the DLL to arm the next normal game launch. The plugin consumes the file at startup. You can also pass `--al-repl` when launching the game.

```powershell
dotnet build .\AL_DevRepl\AL_DevRepl.csproj -c Release
.\AL_DevRepl\Invoke.ps1 ':ping'
.\AL_DevRepl\Invoke.ps1 'SceneManager.GetActiveScene().name'
.\AL_DevRepl\Invoke.ps1 -File .\AL_DevRepl\InspectSkinLighting.csx
```

Pass `-GameProcessId` if more than one game copy is open. Use `Print(value)` to write intermediate results or `=` to force an expression. `:reset` clears compiler state. Commands can modify the live scene, so keep long computations out of the REPL. The skin probe reports scene data, including overlaps with reflection probe volumes. It takes no screenshots and does not assign materials or change lights. Establishing which resources Unity binds to a draw requires a graphics capture.
