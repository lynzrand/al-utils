extern alias unity;
using BepInEx;
using BepInEx.Unity.IL2CPP;
using Il2CppInterop.Runtime.Attributes;
using System.Reflection;
using unity::UnityEngine;

namespace AL_DevRepl;

[BepInPlugin("local.al.dev-repl", "AL Dev REPL", "0.1.0")]
[BepInProcess("AmanatsuLocation.exe")]
public sealed class Plugin : BasePlugin
{
    private UnityRepl? repl;

    public override void Load()
    {
        var nextLaunch = Path.Combine(Paths.PluginPath, "AL_DevRepl", "EnableNextLaunch");
        if (!File.Exists(nextLaunch) && !Environment.GetCommandLineArgs().Contains("--al-repl"))
            return;

        File.Delete(nextLaunch);
        var compiler = Assembly.LoadFrom(Path.Combine(Paths.PluginPath, "RuntimeUnityEditor", "mcs.dll"));
        repl = AddComponent<UnityRepl>();
        var pipe = $"al-dev-repl-{Environment.ProcessId}";
        repl.Initialize(pipe, compiler, message => Log.LogWarning(message));
        Log.LogInfo($"Development REPL available at {pipe} for this launch.");
    }

    public override bool Unload()
    {
        if (repl)
        {
            repl!.Stop();
            unity::UnityEngine.Object.Destroy(repl);
        }
        return true;
    }
}

public sealed class UnityRepl : MonoBehaviour
{
    public UnityRepl(IntPtr pointer) : base(pointer) { }

    private ReplPipe? pipe;
    private Evaluator? evaluator;

    [HideFromIl2Cpp]
    internal void Initialize(string name, Assembly compiler, Action<string> report)
    {
        evaluator = new Evaluator(compiler);
        pipe = new ReplPipe(name, report);
    }

    public void Update()
    {
        pipe?.RunPending(code => code.Trim() == ":ping"
            ? new Reply(true, $"Unity {Application.unityVersion} main thread is responsive.")
            : evaluator!.Run(code));
    }

    public void OnDestroy() => Stop();

    internal void Stop()
    {
        pipe?.Dispose();
        pipe = null;
    }
}
