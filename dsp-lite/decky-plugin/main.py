"""Backend for the Ally Audio Decky plugin.

All audio work happens in ~/ally-dsp-fix (dsp.sh / mic.sh); this backend only
calls those scripts, so the plugin holds no audio state of its own and cannot
overwrite user settings.
"""
import asyncio
import json
import os
import subprocess

import decky

FIX = "/home/deck/ally-dsp-fix"
DSP = os.path.join(FIX, "dsp.sh")
MIC = os.path.join(FIX, "mic.sh")


def _run(cmd):
    env = dict(os.environ)
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/1000")
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=90, env=env)
    except Exception as exc:  # noqa: BLE001
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))


class Plugin:
    async def get_state(self):
        out = await asyncio.to_thread(_run, [DSP, "json"])
        try:
            return json.loads(out.stdout.strip())
        except Exception:  # noqa: BLE001
            return {"enabled": False, "active": 0, "preset": "", "mic": "off", "lang": "en"}

    async def set_enabled(self, enabled: bool):
        await asyncio.to_thread(_run, [DSP, "on" if enabled else "off"])
        return await self.get_state()

    async def set_preset(self, profile: str, voicing: str):
        await asyncio.to_thread(_run, [DSP, "preset", str(profile), str(voicing)])
        return await self.get_state()

    async def set_mic(self, enabled: bool):
        await asyncio.to_thread(_run, [MIC, "on" if enabled else "off"])
        return await self.get_state()

    async def _main(self):
        decky.logger.info("Ally Audio backend started")

    async def _unload(self):
        pass

    async def _unmount(self):
        pass
