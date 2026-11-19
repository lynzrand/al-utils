using BepInEx;
using Character;
using Cysharp.Threading.Tasks;

namespace AL_Performance;

internal static class BenchmarkScenes
{
    internal static void LoadStockScene(int map)
    {
        var defaults = Path.Combine(Paths.GameRootPath, "DefaultData", "0", "chara");
        var female = new HumanData();
        var player = new HumanData();
        if (!female.LoadCharaFile(Path.Combine(defaults, "female", "AL_F_00.png")) ||
            !player.LoadCharaFile(Path.Combine(defaults, "male", "AL_M_00.png")))
        {
            Plugin.Instance.Log.LogWarning("Could not load the two stock character cards for the scene benchmark.");
            return;
        }

        var scene = AL.FreeH.Instance;
        scene.FemaleData1.Value = female;
        scene.FemaleData2.Value = null;
        scene.PlayerData.Value = player;
        scene.FreeHProc(map).Forget();
    }
}
