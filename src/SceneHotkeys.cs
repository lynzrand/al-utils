extern alias unity;
using AL.H;
using Il2CppInterop.Runtime.Attributes;
using unity::UnityEngine;
using UnityEngine.UI;
using Input = UnityEngine.Input;

namespace AL_PovX;

public sealed class SceneHotkeys : MonoBehaviour
{
    public SceneHotkeys(IntPtr pointer) : base(pointer) { }

    private readonly RepeatGate repeat = new();
    private IntPtr scenePointer;
    private bool failed;
    private Settings S { [HideFromIl2Cpp] get => Plugin.Instance.Settings; }

    public void Start() => Plugin.Instance.Log.LogInfo("Scene hotkeys ready: hold Space to repeat Stronger; D/F toggle male/female gauge locks.");

    public void Update()
    {
        try
        {
            var scene = HScene._instance;
            var pointer = scene ? scene.Pointer : IntPtr.Zero;
            if (pointer != scenePointer)
            {
                scenePointer = pointer;
                failed = false;
                ResetRepeat();
            }
            if (failed || !scene || !scene.Loaded || scene.IsDisposed || scene.IsEnded ||
                !Application.isFocused || Time.timeScale == 0 || PovController.IsTyping())
            {
                ResetRepeat();
                return;
            }

            if (Input.GetKeyDown(S.MaleLock.Value)) ToggleLock(scene, CharaIndex.Male1);
            if (Input.GetKeyDown(S.FemaleLock.Value)) ToggleLock(scene, CharaIndex.Female1);

            var option = scene.Option;
            var selected = option?._buttonAttack;
            var button = selected?._selectable?.TryCast<Button>();
            bool usable = button != null && button && button.isActiveAndEnabled &&
                button.gameObject.activeInHierarchy && button.IsInteractable();
            if (repeat.Tick(usable && Input.GetKey(S.Stronger.Value), Time.unscaledTime, S.RepeatInterval.Value))
                button!.onClick.Invoke();
        }
        catch (Exception error)
        {
            failed = true;
            ResetRepeat();
            Plugin.Instance.Log.LogError($"Scene hotkeys disabled until the next scene after an error: {error}");
        }
    }

    [HideFromIl2Cpp]
    private static void ToggleLock(HScene scene, CharaIndex character)
    {
        var gauge = scene.GaugeController;
        var locks = gauge?._togglesLock;
        int index = (int)character;
        if (locks == null || index >= locks.Length) return;
        var toggle = locks[index]?._toggle;
        if (toggle == null || !toggle || !toggle.isActiveAndEnabled || !toggle.gameObject.activeInHierarchy || !toggle.IsInteractable()) return;
        // Use the native UI event so the model and lock icon stay synchronized.
        toggle.isOn = !toggle.isOn;
        Plugin.Instance.Log.LogInfo($"{character} gauge lock: {(toggle.isOn ? "on" : "off")}");
    }

    private void ResetRepeat() => repeat.Tick(false, 0, 0);
    public void OnDisable() => ResetRepeat();
    public void OnApplicationFocus(bool focused) { if (!focused) ResetRepeat(); }
}
