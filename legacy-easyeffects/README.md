# LEGACY — EasyEffects-based audio plugin

> **This is the old audio approach and it is no longer recommended.**
> It drives **EasyEffects** (a Flatpak application) as the DSP host, which adds a second
> audio application to the path, duplicates volume handling and requires EasyEffects to be
> running for the tuning to apply.
>
> **Use [`../dsp-lite/`](../dsp-lite/README.md) instead.** It runs the same official Dolby
> tuning on native PipeWire with no EasyEffects, keeps the volume keys acting after the
> DSP, adds microphone enhancement and ships a single Plasma tray applet.
>
> This directory is kept for history and for users who explicitly want the EasyEffects
> variant. Nothing here receives fixes.

## What is in here

| Path | Content |
|---|---|
| `main.py`, `plugin.json`, `package.json` | Decky Loader plugin (the old `ROG Ally Audio`) |
| `runtime/` | EasyEffects session controller and its four user units |
| `presets/` | four EasyEffects presets generated from the ASUS tuning |
| `scripts/`, `tests/` | packaging and tests for the old plugin |
| `assets/` | thumbnail |
| `install-ROG-Ally-Audio-*.sh` | old one-shot installer (KDE tray runtime) |
| `.github/` | CI/release workflows for the old plugin (inactive here, GitHub only reads `/.github`) |

## Installing the legacy variant (not recommended)

1. Install EasyEffects as a Flatpak: `flatpak install flathub com.github.wwmm.easyeffects`
2. Run `install-ROG-Ally-Audio-0.1.11-auto-kde-tray.sh` from this directory.
3. Keep `dsp-lite` disabled while using it — two DSPs in one path invalidates any listening
   test and will sound wrong.

To remove it later: disable the plugin in Decky Loader, then
`systemctl --user disable --now decky-rog-ally-audio-*`.
