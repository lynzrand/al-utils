# Capture and replay tools

## PresentMon

Use the [PresentMon console](https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0) to collect external DXGI frame intervals. On the tested Windows account, running at normal desktop integrity allowed ETW. With full display tracking the console produced zero rows. Disable display and GPU tracking to collect DXGI presents on that setup.

```powershell
& $presentMon --process_name AmanatsuLocation.exe --output_file .\stock.csv --timed 15 --terminate_after_timed --no_console_stats --no_track_input --no_track_display --no_track_gpu --v1_metrics
python .\AL_Performance\tools\summarize-presentmon.py .\stock.csv --skip-seconds 2
```

## RenderDoc

The [preloader](../RenderDocPreloader/README.md) describes how to capture a game frame. To build the headless analyzer, open x64 Visual Studio Developer PowerShell and pass the directory containing portable `renderdoc.dll` and the matching source tree from the [RenderDoc release](https://github.com/baldurk/renderdoc/releases/tag/v1.47).

```powershell
$analyzer = .\AL_Performance\tools\build-renderdoc-timings.ps1 -RenderDocDirectory $runtime -RenderDocSourceDirectory $source | Select-Object -Last 1
& $analyzer .\stock.rdc .\exported-shaders
& $analyzer .\stock.rdc --replace 17239 .\replacement.dxbc
```

The first command on a capture reports medians from three GPU counter replays after one discarded replay. The optional directory receives compiled shader bytecode, disassembly and an event index. It contains up to twenty timed draw or dispatch events and deduplicates shaders by captured resource ID. A draw duration includes the entire graphics event. The shader listed for that event is the bound pixel shader.

`--replace` installs the specified bytecode only within replay. The selected draw or dispatch identifies the original shader object. Every pipeline using that object sees the replacement. The analyzer brackets the change with original and restored timings. For D3D12 it attributes events through captured pipeline bindings and resource relationships. It also compares the presented buffer, the first color output at the selected event, and the last write of the bound depth target when they are available as single-sample textures. The tool emits numeric texel comparisons and keeps texture data in memory. Matching bytes establish equivalence for the measured capture and output. Differences between the two original-shader runs expose replay variation.
