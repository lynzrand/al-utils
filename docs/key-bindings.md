# Key bindings

Run the game once, close it, then edit
`BepInEx/config/com.al-povx.camera.cfg`. The legacy filename is retained for
upgrades from AL PoV X. Changes take effect on the next launch.

All plugin-owned actions accept Unity `KeyCode` names, including mouse buttons.
These are single-key bindings, not modifier combinations. `None` disables an
action. Avoid assigning competing actions to the same key.

```ini
[Hotkeys]
PoV Toggle Key = Comma
Character Cycle Key = Period
Camera Drag Key = Mouse1
Cursor Release Key = LeftControl
Zoom Key = Z
Recenter Key = Home
PoV Exit Key = Escape

[Scene Hotkeys]
Stronger Key = Space
Male Gauge Lock Key = D
Female Gauge Lock Key = F
Stronger Repeat Interval = 0.15
```

For example, set `PoV Toggle Key = F6` or `Male Gauge Lock Key = Alpha1`.
The config includes the accepted key names. Escape in the default controls
means the configured exit key; it remains available while typing.

Q/W/E/R body-part selection is owned by the game's regular camera. The POV
tracker observes those native selections; these four keys cannot currently
be remapped independently through this plugin's config.

Under `[Camera]`, `Follow Head Position = true` and
`Follow Head Rotation = true` follow the current animated head pose.
Under `[General]`, `Reset On Pose Change = true` resets look offsets and clears
target tracking when the new pose settles. Head/hair hiding remains enabled
until POV is exited or switched to another character.
