# Ally DSP — PipeWire-native Dolby chain (no EasyEffects)

This is the audio stack that is actually running on the ROG Xbox Ally X (RC73XA) under
SteamOS 3.9.5. It replaces the EasyEffects-based runtime: nothing here depends on
EasyEffects, and the Dolby tuning comes from the official ASUS package.

## Why not a WirePlumber smart filter

Ally DSP normally installs the generated chain as `filter.smart = true`. On this stack
(PipeWire 1.6.8 / WirePlumber 0.5.18) that deployment measures as **passthrough**: the
1/3-octave transfer is 0.00 dB in every band while every indicator still reports success.
A second, independent failure mode: `LV2_PATH` contains a space (`…/Ally DSP/bin/lv2`),
and an unquoted `Environment=` line in a systemd drop-in makes systemd truncate it, so the
LV2 graph never loads (`can't load graph`) and PipeWire falls back to passthrough.

Both are visible in the logs, not in the UI. Measured on this device.

## Architecture

```
apps → allydsp_in (virtual sink, chain input)
     → convolver → para_equalizer (dialog) → mb_compressor (regulator) → limiter
     → allydsp_out → speakers
```

* default sink stays the **physical speaker**, so volume keys, the Steam OSD and mute act
  **after** the DSP. That matters: the Dolby leveler normalises level, so a volume change
  applied before the chain would be compensated and appear not to work.
* app streams are moved into the chain by `bin/streams.sh` (the same approach the old
  EasyEffects controller used), so apps still get the tuning.
* input of the chain is pinned to 100 %.

## Windows parity

From the official ASUS `Default_settings.json` / tuning XML for this codec:

| Module | Windows | Here |
|---|---|---|
| regulator (multiband compressor) | always on | on |
| bass enhancer | off | off |
| IEQ | off (`ieq-amount = 10`) | not forced |
| volume leveler | not enabled in this tuning | **off** (was wrongly on before) |
| default profile | `movie` | `movie/balanced` |

## One-command install

```bash
./install.sh
```

Nothing manual: the presets (`presets/`) and the LSP bundle (`lv2/`) ship in this
repository and are copied into `~/ally-dsp-fix` by the installer. After it finishes you have
a working chain, the Decky panel and the tray applet.

Provenance and licensing of those two directories: [`NOTICE.md`](NOTICE.md) — the presets
are generated from the official ASUS package (ASUS/Dolby tuning values), the LSP bundle is
LGPL-3.0.

## Decky panel

`decky-plugin/` is a standalone, dependency-free Decky plugin (`api_version: 1`, plain
ESM, no bundler): audio enhancement on/off, profile, voicing, microphone enhancement.
It holds no audio state of its own — every action calls `dsp.sh`, so it can never
overwrite the tuning.

## Files

| Path | Purpose |
|---|---|
| `bin/apply.sh` | regenerates `~/ally-dsp-fix/render.conf` from the plugin's `active/chain.conf`, restarts only when stale, re-links, keeps the default sink |
| `bin/dsp.sh` | `on / off / toggle / status / json / preset <profile> <voicing> / mic …` |
| `bin/mic.sh` | microphone: WebRTC noise suppression + AGC + high-pass (`module-echo-cancel`) |
| `bin/streams.sh` | moves new app streams into the chain |
| `bin/lv2ls` | liblilv-based `lv2ls` replacement (SteamOS ships liblilv, not the CLI) |
| `units/` | user units: apply path+timer, mic, streams; plus the `lv2ls` bind-mount unit |
| `plasma/org.deck.allydsp` | Plasma 6 applet: one tray icon for audio + microphone, PL/EN from locale |

## Usage

```bash
dsp on | off | toggle | status
dsp preset movie balanced
dsp mic on | off
```

## Verification

Measured with a null-sink rig proven bit-exact (960 000 samples, 0 differences):

* linear stage reproduces the official FIR with **max 0.01 dB** deviation
* chain processes: **+3.88 dB** at −20 dBFS (game/balanced, leveler on at the time)
* dynamic range across −60…0 dBFS: **18.7 dB** broadband
* CPU: **5.49 %** of one core, RSS 46 MB
* deployed-through-systemd test after the fix: **+2.89 dB** (null target) and **+9.34 dB**
  at −40 dBFS (movie/warm), i.e. the chain really processes

The full measurement report lives outside this repo; these numbers are the summary.
