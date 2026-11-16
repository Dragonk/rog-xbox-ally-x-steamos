// Ally Audio — panel Decky bez zależności: tylko globalny SP_REACT + własne elementy
// (SP_DFL nie istnieje w tej wersji Decky). Język: PL/EN z locale Steam.
const api = window.DECKY_API || window.api || {};
const invoke = (name, args) => {
  if (api.callable) return api.callable(name)(...(args || []));
  if (api.callPluginMethod) return api.callPluginMethod(name, args || []);
  return Promise.reject(new Error("backend api unavailable"));
};
const backend = {
  state: () => invoke("get_state"),
  setEnabled: (v) => invoke("set_enabled", [v]),
  setPreset: (p, v) => invoke("set_preset", [p, v]),
  setMic: (v) => invoke("set_mic", [v]),
};

const S = {
  pl: {
    title: "Ally Audio", state: "Stan",
    enhancement: "Ulepszenie audio", enhancementDesc: "Tuning Dolby dla głośników. Wyłączone = dźwięk bez przetwarzania.",
    profile: "Profil", voicing: "Brzmienie",
    mic: "Ulepszenie mikrofonu", micDesc: "Tłumienie szumu i automatyczna regulacja wzmocnienia (WebRTC).",
    on: "włączone", off: "wyłączone", enable: "Włącz", disable: "Wyłącz",
    refresh: "Odśwież", error: "Brak połączenia z backendem",
    profiles: { game: "Gra", dynamic: "Dynamiczny", movie: "Film", music: "Muzyka", voice: "Głos" },
    voicings: { balanced: "Zbalansowane", detailed: "Szczegółowe", warm: "Ciepłe" },
  },
  en: {
    title: "Ally Audio", state: "Status",
    enhancement: "Audio enhancement", enhancementDesc: "Dolby tuning for the speakers. Off = unprocessed sound.",
    profile: "Profile", voicing: "Voicing",
    mic: "Microphone enhancement", micDesc: "Noise suppression and automatic gain control (WebRTC).",
    on: "on", off: "off", enable: "Enable", disable: "Disable",
    refresh: "Refresh", error: "No connection to the backend",
    profiles: { game: "Game", dynamic: "Dynamic", movie: "Movie", music: "Music", voice: "Voice" },
    voicings: { balanced: "Balanced", detailed: "Detailed", warm: "Warm" },
  },
};

function lang() {
  try { return (navigator.language || "en").toLowerCase().startsWith("pl") ? "pl" : "en"; }
  catch (e) { return "en"; }
}

const css = {
  section: { padding: "2px 0 10px" },
  header: { fontSize: "12px", fontWeight: 600, textTransform: "uppercase", opacity: 0.6, padding: "6px 12px" },
  row: { display: "flex", alignItems: "center", justifyContent: "space-between", gap: "10px", padding: "7px 12px" },
  text: { display: "flex", flexDirection: "column", minWidth: 0 },
  label: { fontSize: "14px" },
  desc: { fontSize: "11px", opacity: 0.6, marginTop: "2px" },
  button: { padding: "6px 14px", borderRadius: "4px", background: "rgba(255,255,255,0.14)", color: "inherit", border: "none", cursor: "pointer", fontSize: "13px", whiteSpace: "nowrap" },
  select: { background: "rgba(255,255,255,0.10)", color: "inherit", border: "1px solid rgba(255,255,255,0.2)", borderRadius: "4px", padding: "5px 8px", fontSize: "13px" },
  dot: (on) => ({ display: "inline-block", width: "9px", height: "9px", borderRadius: "50%", marginRight: "8px", background: on ? "#1a9fff" : "rgba(255,255,255,0.3)" }),
};

export default () => {
  const t = S[lang()];
  const React = SP_REACT;
  const h = React.createElement;
  const { useState, useEffect, useCallback } = React;

  const [state, setState] = useState({ enabled: false, preset: "movie/balanced", mic: "off" });
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const apply = useCallback(async (fn) => {
    setBusy(true);
    try { setState(await fn()); setFailed(false); } catch (e) { setFailed(true); }
    setBusy(false);
  }, []);

  const refresh = useCallback(() => apply(() => backend.state()), [apply]);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 5000);
    return () => clearInterval(id);
  }, [refresh]);

  const [profile, voicing] = (state.preset || "movie/balanced").split("/");

  const text = (label, desc) => h("div", { style: css.text },
    h("span", { style: css.label }, label),
    desc ? h("span", { style: css.desc }, desc) : null);

  const toggle = (isOn, onClick) => h("button", {
    style: css.button, disabled: busy, onClick,
  }, h("span", { style: css.dot(isOn) }), isOn ? t.disable : t.enable);

  const Content = () => h("div", { style: css.section },
    h("div", { style: css.header }, t.title),
    h("div", { style: css.row },
      text(t.state),
      h("span", { style: { fontSize: "13px", opacity: 0.85 } },
        h("span", { style: css.dot(!!state.enabled) }),
        (state.enabled ? t.on : t.off) + " · " + (t.profiles[profile] || profile) + " / " + (t.voicings[voicing] || voicing))),

    h("div", { style: css.row },
      text(t.enhancement, t.enhancementDesc),
      toggle(!!state.enabled, () => apply(() => backend.setEnabled(!state.enabled)))),

    h("div", { style: css.row },
      text(t.profile),
      h("select", {
        style: css.select, value: profile, disabled: busy,
        onChange: (e) => apply(() => backend.setPreset(e.target.value, voicing)),
      }, Object.keys(t.profiles).map((k) => h("option", { key: k, value: k }, t.profiles[k])))),

    h("div", { style: css.row },
      text(t.voicing),
      h("select", {
        style: css.select, value: voicing, disabled: busy,
        onChange: (e) => apply(() => backend.setPreset(profile, e.target.value)),
      }, Object.keys(t.voicings).map((k) => h("option", { key: k, value: k }, t.voicings[k])))),

    h("div", { style: css.row },
      text(t.mic, t.micDesc),
      toggle(state.mic === "on", () => apply(() => backend.setMic(state.mic !== "on")))),

    h("div", { style: css.row },
      h("span", null),
      h("button", { style: css.button, disabled: busy, onClick: refresh }, t.refresh)),

    failed ? h("div", { style: { ...css.row, color: "#ff8a8a", fontSize: "12px" } }, t.error) : null,
  );

  return {
    name: t.title,
    titleView: h("div", null, t.title),
    content: h(Content),
    icon: h("div", null, "♪"),
    onDismount() {},
  };
};
