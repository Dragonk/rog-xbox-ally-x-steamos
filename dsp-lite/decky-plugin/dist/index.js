const manifest = {"name":"Ally Audio"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const callable = api.callable;
const definePlugin = (fn) => {
    return (...args) => {
        return fn(...args);
    };
};

const getState = callable("get_state");
const setEnabled = callable("set_enabled");
const setPreset = callable("set_preset");
const setMic = callable("set_mic");
const S = {
    pl: {
        title: "Ally Audio",
        state: "Stan",
        enhancement: "Ulepszenie audio",
        enhancementDesc: "Tuning Dolby dla głośników. Wyłączone = dźwięk bez przetwarzania.",
        profile: "Profil",
        voicing: "Brzmienie",
        mic: "Ulepszenie mikrofonu",
        micDesc: "Tłumienie szumu i automatyczna regulacja wzmocnienia (WebRTC).",
        on: "włączone",
        off: "wyłączone",
        refresh: "Odśwież",
        error: "Brak połączenia z backendem",
        profiles: { game: "Gra", dynamic: "Dynamiczny", movie: "Film", music: "Muzyka", voice: "Głos" },
        voicings: { balanced: "Zbalansowane", detailed: "Szczegółowe", warm: "Ciepłe" },
    },
    en: {
        title: "Ally Audio",
        state: "Status",
        enhancement: "Audio enhancement",
        enhancementDesc: "Dolby tuning for the speakers. Off = unprocessed sound.",
        profile: "Profile",
        voicing: "Voicing",
        mic: "Microphone enhancement",
        micDesc: "Noise suppression and automatic gain control (WebRTC).",
        on: "on",
        off: "off",
        refresh: "Refresh",
        error: "No connection to the backend",
        profiles: { game: "Game", dynamic: "Dynamic", movie: "Movie", music: "Music", voice: "Voice" },
        voicings: { balanced: "Balanced", detailed: "Detailed", warm: "Warm" },
    },
};
const t = (navigator.language || "en").toLowerCase().startsWith("pl") ? S.pl : S.en;
function Content() {
    const [state, setState] = SP_REACT.useState(null);
    const [busy, setBusy] = SP_REACT.useState(false);
    const [failed, setFailed] = SP_REACT.useState(false);
    const refresh = () => {
        setBusy(true);
        getState()
            .then((next) => { setState(next); setFailed(false); })
            .catch(() => setFailed(true))
            .finally(() => setBusy(false));
    };
    SP_REACT.useEffect(() => {
        refresh();
        const id = setInterval(refresh, 5000);
        return () => clearInterval(id);
    }, []);
    const act = (p) => {
        setBusy(true);
        p.then((next) => { setState(next); setFailed(false); })
            .catch(() => setFailed(true))
            .finally(() => setBusy(false));
    };
    const [profile, voicing] = ((state && state.preset) || "movie/balanced").split("/");
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t.title, children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.Field, { label: t.state, children: state === null
                        ? "…"
                        : (state.enabled ? t.on : t.off) + " · " + (t.profiles[profile] || profile) + " / " + (t.voicings[voicing] || voicing) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t.enhancement, description: t.enhancementDesc, checked: !!(state && state.enabled), disabled: busy, onChange: (value) => act(setEnabled(value)) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.DropdownItem, { label: t.profile, rgOptions: Object.keys(t.profiles).map((k) => ({ data: k, label: t.profiles[k] })), selectedOption: profile, disabled: busy, onChange: (option) => act(setPreset(option.data, voicing)) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.DropdownItem, { label: t.voicing, rgOptions: Object.keys(t.voicings).map((k) => ({ data: k, label: t.voicings[k] })), selectedOption: voicing, disabled: busy, onChange: (option) => act(setPreset(profile, option.data)) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t.mic, description: t.micDesc, checked: !!state && state.mic === "on", disabled: busy, onChange: (value) => act(setMic(value)) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: refresh, disabled: busy, children: t.refresh }) }), failed ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.Field, { label: t.error, children: "" }) })) : null] }));
}
var index = definePlugin(() => ({
    name: t.title,
    titleView: SP_JSX.jsx("div", { className: DFL.staticClasses.Title, children: t.title }),
    content: SP_JSX.jsx(Content, {}),
    icon: (SP_JSX.jsxs("svg", { width: "1em", height: "1em", viewBox: "0 0 24 24", fill: "currentColor", "aria-hidden": "true", children: [SP_JSX.jsx("path", { d: "M4 9h3l4-3v12l-4-3H4z" }), SP_JSX.jsx("path", { d: "M15 8.5a4.5 4.5 0 0 1 0 7v-1.8a2.7 2.7 0 0 0 0-3.4z" }), SP_JSX.jsx("path", { d: "M18.5 6a8 8 0 0 1 0 12v-1.8a6.2 6.2 0 0 0 0-8.4z" }), SP_JSX.jsx("path", { d: "M11.6 4.2h1.4v2h-1.4z", transform: "rotate(45 12.3 5.2)" })] })),
    onDismount() { },
}));

export { index as default };
//# sourceMappingURL=index.js.map
