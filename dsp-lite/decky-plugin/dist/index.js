// Ally Audio — panel Decky. Zależności: tylko globalny SP_REACT (SP_DFL w tej wersji
// Decky nie istnieje). Hooki wyłącznie wewnątrz komponentów, zgodnie z regułami Reacta.
// Decky nie wystawia window.DECKY_API; kontrakt to wewnetrzne API loadera,
// dokladnie takie, jakiego uzywa boiler-fingerprint-unlock:
//   internal.connect(<wersja>, '<nazwa pluginu>').callable('<metoda>')
const PLUGIN_NAME = "Ally Audio";

function connectInternal() {
  const internal = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
  if (internal && internal.connect) {
    try { return internal.connect(2, PLUGIN_NAME); }
    catch (e) { return internal.connect(1, PLUGIN_NAME); }
  }
  return null;
}

const S = {
  pl: {
    title: "Ally Audio", state: "Stan",
    enhancement: "Ulepszenie audio", enhancementDesc: "Tuning Dolby dla głośników. Wyłączone = dźwięk bez przetwarzania.",
    profile: "Profil", voicing: "Brzmienie",
    mic: "Ulepszenie mikrofonu", micDesc: "Tłumienie szumu i automatyczna regulacja wzmocnienia (WebRTC).",
    on: "włączone", off: "wyłączone", enable: "Włącz", disable: "Wyłącz",
    refresh: "Odśwież", error: "Brak połączenia z backendem", loading: "Wczytywanie…",
    profiles: { game: "Gra", dynamic: "Dynamiczny", movie: "Film", music: "Muzyka", voice: "Głos" },
    voicings: { balanced: "Zbalansowane", detailed: "Szczegółowe", warm: "Ciepłe" },
  },
  en: {
    title: "Ally Audio", state: "Status",
    enhancement: "Audio enhancement", enhancementDesc: "Dolby tuning for the speakers. Off = unprocessed sound.",
    profile: "Profile", voicing: "Voicing",
    mic: "Microphone enhancement", micDesc: "Noise suppression and automatic gain control (WebRTC).",
    on: "on", off: "off", enable: "Enable", disable: "Disable",
    refresh: "Refresh", error: "No connection to the backend", loading: "Loading…",
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
  error: { padding: "7px 12px", color: "#ff8a8a", fontSize: "12px" },
};

// Komponent panelu: tu i tylko tu wolno używać hooków.
function Panel(props) {
  const React = SP_REACT;
  const { useState, useEffect, useCallback } = React;
  const t = props.t;
  const h = React.createElement;

  const [state, setState] = useState({ enabled: false, preset: "movie/balanced", mic: "off" });
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const backend = props.backend;
  const run = useCallback((promise) => {
    setBusy(true);
    Promise.resolve(promise)
      .then((next) => { if (next) setState(next); setFailed(false); })
      .catch(() => setFailed(true))
      .then(() => setBusy(false));
  }, []);

  useEffect(() => {
    let alive = true;
    const tick = () => Promise.resolve()
      .then(() => backend.get_state())
      .then((next) => { if (alive && next) { setState(next); setFailed(false); } })
      .catch(() => { if (alive) setFailed(true); });
    tick();
    const id = setInterval(tick, 5000);
    return () => { alive = false; clearInterval(id); };
  }, []);

  const [profile, voicing] = String(state.preset || "movie/balanced").split("/");

  const text = (label, desc) => h("div", { style: css.text },
    h("span", { style: css.label }, label),
    desc ? h("span", { style: css.desc }, desc) : null);

  const toggle = (isOn, onClick) => h("button", { style: css.button, disabled: busy, onClick },
    h("span", { style: css.dot(isOn) }), isOn ? t.disable : t.enable);

  return h("div", { style: css.section },
    h("div", { style: css.header, "data-ally-audio": "header" }, t.title),
    h("div", { style: css.row },
      text(t.state),
      h("span", { style: { fontSize: "13px", opacity: 0.85 } },
        h("span", { style: css.dot(!!state.enabled) }),
        (state.enabled ? t.on : t.off) + " · " + (t.profiles[profile] || profile) + " / " + (t.voicings[voicing] || voicing))),
    h("div", { style: css.row },
      text(t.enhancement, t.enhancementDesc),
      toggle(!!state.enabled, () => run(backend.set_enabled(!state.enabled)))),
    h("div", { style: css.row },
      text(t.profile),
      h("select", {
        style: css.select, value: profile, disabled: busy, "data-ally-audio": "profile",
        onChange: (e) => run(backend.set_preset(e.target.value, voicing)),
      }, Object.keys(t.profiles).map((k) => h("option", { key: k, value: k }, t.profiles[k])))),
    h("div", { style: css.row },
      text(t.voicing),
      h("select", {
        style: css.select, value: voicing, disabled: busy, "data-ally-audio": "voicing",
        onChange: (e) => run(backend.set_preset(profile, e.target.value)),
      }, Object.keys(t.voicings).map((k) => h("option", { key: k, value: k }, t.voicings[k])))),
    h("div", { style: css.row },
      text(t.mic, t.micDesc),
      toggle(state.mic === "on", () => run(backend.set_mic(state.mic !== "on")))),
    h("div", { style: css.row },
      h("span", null),
      h("button", { style: css.button, disabled: busy }, t.refresh)),
    failed ? h("div", { style: css.error }, t.error) : null,
  );
}

export default () => {
  const t = S[lang()];
  const React = SP_REACT;
  const api = connectInternal();
  const backend = api
    ? {
        get_state: api.callable("get_state"),
        set_enabled: api.callable("set_enabled"),
        set_preset: api.callable("set_preset"),
        set_mic: api.callable("set_mic"),
      }
    : null;
  return {
    name: t.title,
    titleView: React.createElement("div", null, t.title),
    content: React.createElement(Panel, { t, backend }),
    icon: React.createElement("div", null, "♪"),
    onDismount() {},
  };
};
