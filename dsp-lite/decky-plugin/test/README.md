# Panel test

`panel.test.mjs` loads the **shipped** bundle (`../dist/index.js`), instantiates the
plugin definition the way Decky Loader does, mounts the panel with React and drives
the controls. It asserts:

- the plugin connects to the loader API with version 2 and the name `Ally Audio`;
- one toggle per feature (audio enhancement, microphone enhancement) and one
  dropdown per setting (profile, voicing) are rendered;
- `get_state` is fetched on mount and the controls mirror the backend answer;
- toggling enhancement calls `set_enabled(false)`, changing the profile calls
  `set_preset("music", "balanced")`, toggling the mic calls `set_mic(true)`;
- every label is localized for `pl-PL` and `en-US`;
- with a failing backend the panel shows the "no connection" row.

`@decky/ui` can only be imported inside the Steam client (it hooks into Steam's
webpack container), so the component boundary (`DFL`) is stubbed; the shipped
bundle, the loader API contract and the whole data flow are the real ones.
Because the panel uses Decky's own `PanelSection` / `ToggleField` / `DropdownItem`,
gamepad focus comes from Decky's focus system instead of custom markup.

```bash
npm install          # once, in dsp-lite/decky-plugin
npm run build        # src/ -> dist/index.js
npm test             # 24 assertions, PL + EN
TEST_LANG=en-US FAIL=1 node test/panel.test.mjs   # error path
```

Expected output ends with `ALL PASS (24)`.
