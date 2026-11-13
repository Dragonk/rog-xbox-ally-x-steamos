# Fingerprint reader (FocalTech FT9769) on SteamOS — ASUS ROG Xbox Ally X

Scripts that make the power-button fingerprint sensor of the **ASUS ROG Xbox Ally X (RC73XA)** work on **SteamOS**, plus a systemd guard that keeps it working across SteamOS updates.

Real-device tested: RC73XA, SteamOS 3.9.5, BIOS RC73XA.319, kernel 7.2.7-valve2.

## How it works (no patched libs, no compiling)

- The sensor is a **FOCAL FT9769 ESS** on USB `2808:a78a` (same chip family as the original ROG Ally, different mounting variant). It is wired to the **power button**.
- The upstream libfprint driver `focaltech_moc` supports `2808:a78a` from libfprint 1.94.100 — and the libfprint in the SteamOS repository already recognizes this ID, so a plain `fprintd` install from the SteamOS repos is all that is needed.
- `sudo` and `polkit` authentication get an `auth sufficient pam_fprintd.so` entry: the fingerprint is offered first, the password always remains as fallback.
- The KDE lock screen offers the finger through the stock `kde-fingerprint` PAM service.
- A Decky plugin ([FlightDan/FingerprintUnlock-SteamOS](https://github.com/FlightDan/FingerprintUnlock-SteamOS)) adds an unlock toggle in Gaming Mode.

## Scripts

| Script | Purpose |
| --- | --- |
| `fingerprint-ft9769-setup.sh` | One-shot setup. Commands: `install` (fprintd from SteamOS repos + sensor detection test), `enroll` (finger enrollment + 2× verify + PAM hooks + Decky plugin), `plugin`, `status`, `uninstall`. |
| `fingerprint-guard-ft9769.sh` | Update-surviving guard: a systemd service + timer that verifies the whole stack and repairs it from the SteamOS repos after every SteamOS update. Commands: `status` (no root), `run`, `install`, `uninstall`. |
| `fingerprint-diag.sh` | Read-only diagnostics: DMI, USB, sysfs, dmesg, pacman state, PAM files, enrolled fingers, guard log. Changes nothing. |

## Quick start

In KDE Desktop Mode Konsole (or SSH as `deck`):

```bash
curl -LO https://github.com/Dragonk/rog-xbox-ally-x-steamos/raw/main/fingerprint-ft9769/fingerprint-ft9769-setup.sh
curl -LO https://github.com/Dragonk/rog-xbox-ally-x-steamos/raw/main/fingerprint-ft9769/fingerprint-guard-ft9769.sh
chmod +x fingerprint-ft9769-setup.sh fingerprint-guard-ft9769.sh

sudo ./fingerprint-ft9769-setup.sh install    # fprintd from SteamOS repos + detection test
sudo ./fingerprint-ft9769-setup.sh enroll     # enroll (sensor = power button) + PAM + Decky plugin
sudo ./fingerprint-guard-ft9769.sh install    # guard: 2 min after boot, then every 6 h
```

## Why a guard? What survives a SteamOS update

SteamOS atomically replaces `/usr`: `fprintd`, `libfprint`, `pam_fprintd.so` and the `kde-fingerprint` PAM service disappear on every major update, while the pacman database in `/var` still claims they are installed. The guard detects exactly this state and reinstalls cleanly from the SteamOS repositories — no golden copies, no compiling.

| Item | Location | Survives update |
| --- | --- | --- |
| Enrolled fingerprints | `/var/lib/fprint` | yes |
| pacman database + keyring | `/var`, `/etc` | yes |
| PAM entries (sudo, polkit override) | `/etc/pam.d` | yes |
| Decky plugin | `/home/deck/homebrew/plugins` | yes |
| Guard scripts + log | `/home/deck/fingerprint-guard` | yes |
| fprintd, libfprint, pam_fprintd.so, kde-fingerprint | `/usr` | no — reinstalled from repos by the guard |

SteamOS quirks handled by the scripts:

- SteamOS does not initialize the pacman keyring (`pacman-key --init` + `--populate` are run automatically; a `SigLevel = Never` fallback config is derived from the system `pacman.conf`, preserving Valve's `DBPath`/`GPGDir`).
- SteamOS has no `/etc/pam.d/polkit-1` — the polkit PAM config lives in `/usr/lib/pam.d`. The scripts create a **persistent override** `/etc/pam.d/polkit-1` (copy + fingerprint entry) so polkit keeps offering the finger after updates too.
- The `fprintd` package has no `/usr/bin/fprintd` binary: the daemon is `/usr/lib/fprintd` (dbus-activated), the tools are `fprintd-list`/`fprintd-enroll`/`fprintd-verify`, and the PAM module lands in `/usr/lib64/security/` (SteamOS uses a lib64 layout).
- The guard's install cascade: plain `pacman -S` → keyring repair → `pacman -Sy` (refresh the sync DB, which drifts after a major update) → `SigLevel=Never`. PAM entries are only added when the module actually exists, so `sudo` on password is never blocked.
- If `/var/lib/fprint` ever loses the enrollment, the guard logs a warning with the re-enroll command; run `sudo ./fingerprint-ft9769-setup.sh enroll` again.

## Troubleshooting

Run `sudo ./fingerprint-diag.sh` (read-only) and check `/home/deck/fingerprint-guard/guard.log`. After a major SteamOS update you can also force an immediate check: `sudo /home/deck/fingerprint-guard/fingerprint-guard.sh run`.

## Device variants

The RC73XA exists in two mounting variants: **FOCAL FT9769 (2808:a78a)**, covered here and real-device tested, and **Egis (1c7a:0588)**, which is different hardware not covered by these scripts. Check with `lsusb` which one you have.

## Credits

- libfprint `focaltech_moc` driver and the upstream libfprint maintainers
- [FlightDan/FingerprintUnlock-SteamOS](https://github.com/FlightDan/FingerprintUnlock-SteamOS) for the Decky Gaming Mode plugin
