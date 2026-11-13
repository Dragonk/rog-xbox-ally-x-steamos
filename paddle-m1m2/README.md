# Rear buttons M1/M2 (paddles) for the ASUS ROG Xbox Ally X on SteamOS

Fix for the **ASUS ROG Xbox Ally X (RC73XA)** rear buttons (paddles M1/M2) on SteamOS, plus a guard that keeps them working across SteamOS updates.

## Background

The RC73XA paddle mapping landed in **InputPlumber >= 0.79**. Stock SteamOS 3.9.x ships **0.78.0**, so out of the box the rear buttons do nothing. The fix overlays a newer InputPlumber (0.83.1) on `/usr` as a **systemd-sysext** image stored in `/var`, built with the procedure from [pastaq/steamos_scripts](https://github.com/pastaq/steamos_scripts) (`update-inputplumber.sh` + `mask-inputplumber.sh`). The sysext survives SteamOS updates because `/var` is not part of the read-only OS image.

## Why the paddles died after the big SteamOS update (2026-11)

After the update, the paddles stopped working even though the sysext directory was still in `/var`. Three things had changed, all in one update:

1. **Scan directory changed.** The new systemd only scans `/etc/extensions`, `/run/extensions`, `/var/lib/extensions` and `/var/lib/extensions.mutable`. The old SteamOS location `/var/lib/extensions.systemd` is no longer scanned, so the extension was invisible to `systemd-sysext`.
2. **Release file path changed.** The extension-release file is now only found at the upstream path `usr/lib/extension-release.d/extension-release.inputplumber` inside the image. The Valve-patched path `usr/lib/extensions/systemd/extension-release.d/` no longer counts.
3. **`VERSION_ID` became mandatory.** The release file must contain `ID` and `VERSION_ID` matching the host `/etc/os-release` (for example `ID=steamos`, `VERSION_ID=3.9.5`). Without a matching `VERSION_ID` the image is reported as `incompatible` and ignored, which is exactly what `Extension 'inputplumber' does not contain VERSION_ID in release file but requested to match '3.9.5'` means.

Diagnosis of a dead state, from the device:

```bash
systemd-sysext status                      # extension missing from /usr?
/usr/bin/inputplumber --version            # 0.78.0 = stock, paddles dead
ls /var/lib/extensions /var/lib/extensions.systemd
systemctl show systemd-sysext.service -p ConditionResult,Conditions
sudo SYSTEMD_LOG_LEVEL=debug systemd-sysext merge   # exact rejection reason
```

## The guard

`paddle-m1m2-guard.sh` (`status` / `run` / `install` / `uninstall`) repairs the extension fully offline, because the golden copy lives in `/var`:

- relocates the sysext from the legacy `/var/lib/extensions.systemd` to `/var/lib/extensions` when needed,
- rewrites the extension-release files (in the sysext copy and, if present, the OpenGamepadUI copy under `~/.var/lib/extensions`) against the **current** host `os-release`, so a `VERSION_ID` bump after the next update self-heals,
- runs `systemd-sysext merge` and `systemctl daemon-reload` when the running version does not match the sysext,
- restarts `inputplumber` only when something changed or the service is down (it does not interrupt a running session without a reason),
- verifies `/usr/bin/inputplumber` reports the sysext version,
- logs a warning when the stock InputPlumber reaches 0.79+, because from that moment the sysext only shadows a newer stock and should be removed.

Timer: 2 minutes after boot, then every 6 hours (`Persistent=true`), same pattern as the fingerprint guard in this repo.

### Install

On a device that already has the sysext (created earlier with the pastaq scripts):

```bash
curl -LO https://github.com/Dragonk/rog-xbox-ally-x-steamos/raw/main/paddle-m1m2/paddle-m1m2-guard.sh
chmod +x paddle-m1m2-guard.sh
sudo ./paddle-m1m2-guard.sh install
sudo ./paddle-m1m2-guard.sh run
```

On a fresh device, first create the sysext with [pastaq/steamos_scripts](https://github.com/pastaq/steamos_scripts) `update-inputplumber.sh` (it still installs into the legacy layout), then run the guard: it relocates the image, fixes the release metadata and merges.

### Verify

```bash
systemd-sysext status               # inputplumber listed for /usr
/usr/bin/inputplumber --version     # 0.83.1
./paddle-m1m2-guard.sh status
```

Then test M1/M2 in a game (after a reboot if Steam had the controller open already).

### Remove / when Valve catches up

When stock InputPlumber reaches 0.79+ (tracked in [ValveSoftware/SteamOS#2838](https://github.com/ValveSoftware/SteamOS/issues/2838) and [#2269](https://github.com/ValveSoftware/SteamOS/issues/2269)), remove the overlay so it stops masking the newer stock:

```bash
sudo ./paddle-m1m2-guard.sh uninstall
sudo rm -rf /var/lib/extensions/inputplumber
sudo systemd-sysext unmerge || sudo reboot
sudo systemctl restart inputplumber.service
```

## Tested

Real device (RC73XA, SteamOS 3.9.5, BIOS RC73XA.319): the post-update incident (paddles dead, stock 0.78.0 running, sysext present but ignored) was diagnosed live and the repair sequence confirmed on the device on 2026-11-14. Guard logic is covered by end-to-end mock tests (17/17: healthy state, legacy relocation, stale/missing/quoted `VERSION_ID`, upstream release path creation, OpenGamepadUI copy fallback, missing sysext, failed merge, stock catch-up warning, inactive service, install/uninstall).

## Disclaimer

Independent community project. Not affiliated with ASUS, Republic of Gamers, Valve, or the InputPlumber project. License: MIT (repository root).
