import { definePlugin, callable } from "@decky/api";
import { PanelSection, PanelSectionRow, ToggleField, DropdownItem, ButtonItem, Field, staticClasses } from "@decky/ui";
import { useEffect, useState } from "react";

const getState = callable<[], State>("get_state");
const setEnabled = callable<[boolean], State>("set_enabled");
const setPreset = callable<[string, string], State>("set_preset");
const setMic = callable<[boolean], State>("set_mic");

type State = { enabled: boolean; active: number; preset: string; mic: string; lang?: string };

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
    profiles: { game: "Gra", dynamic: "Dynamiczny", movie: "Film", music: "Muzyka", voice: "Głos" } as Record<string, string>,
    voicings: { balanced: "Zbalansowane", detailed: "Szczegółowe", warm: "Ciepłe" } as Record<string, string>,
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
    profiles: { game: "Game", dynamic: "Dynamic", movie: "Movie", music: "Music", voice: "Voice" } as Record<string, string>,
    voicings: { balanced: "Balanced", detailed: "Detailed", warm: "Warm" } as Record<string, string>,
  },
};

const t = (navigator.language || "en").toLowerCase().startsWith("pl") ? S.pl : S.en;

function Content() {
  const [state, setState] = useState<State | null>(null);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const refresh = () => {
    setBusy(true);
    getState()
      .then((next) => { setState(next); setFailed(false); })
      .catch(() => setFailed(true))
      .finally(() => setBusy(false));
  };

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 5000);
    return () => clearInterval(id);
  }, []);

  const act = (p: Promise<State>) => {
    setBusy(true);
    p.then((next) => { setState(next); setFailed(false); })
      .catch(() => setFailed(true))
      .finally(() => setBusy(false));
  };

  const [profile, voicing] = ((state && state.preset) || "movie/balanced").split("/");

  return (
    <PanelSection title={t.title}>
      <PanelSectionRow>
        <Field label={t.state}>
          {state === null
            ? "…"
            : (state.enabled ? t.on : t.off) + " · " + (t.profiles[profile] || profile) + " / " + (t.voicings[voicing] || voicing)}
        </Field>
      </PanelSectionRow>
      <PanelSectionRow>
        <ToggleField
          label={t.enhancement}
          description={t.enhancementDesc}
          checked={!!(state && state.enabled)}
          disabled={busy}
          onChange={(value: boolean) => act(setEnabled(value))}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <DropdownItem
          label={t.profile}
          rgOptions={Object.keys(t.profiles).map((k) => ({ data: k, label: t.profiles[k] }))}
          selectedOption={profile}
          disabled={busy}
          onChange={(option: { data: string }) => act(setPreset(option.data, voicing))}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <DropdownItem
          label={t.voicing}
          rgOptions={Object.keys(t.voicings).map((k) => ({ data: k, label: t.voicings[k] }))}
          selectedOption={voicing}
          disabled={busy}
          onChange={(option: { data: string }) => act(setPreset(profile, option.data))}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <ToggleField
          label={t.mic}
          description={t.micDesc}
          checked={!!state && state.mic === "on"}
          disabled={busy}
          onChange={(value: boolean) => act(setMic(value))}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={refresh} disabled={busy}>{t.refresh}</ButtonItem>
      </PanelSectionRow>
      {failed ? (
        <PanelSectionRow>
          <Field label={t.error}>{""}</Field>
        </PanelSectionRow>
      ) : null}
    </PanelSection>
  );
}

export default definePlugin(() => ({
  name: t.title,
  titleView: <div className={staticClasses.Title}>{t.title}</div>,
  content: <Content />,
  icon: (
    <svg width="1em" height="1em" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M4 9h3l4-3v12l-4-3H4z" />
      <path d="M15 8.5a4.5 4.5 0 0 1 0 7v-1.8a2.7 2.7 0 0 0 0-3.4z" />
      <path d="M18.5 6a8 8 0 0 1 0 12v-1.8a6.2 6.2 0 0 0 0-8.4z" />
      <path d="M11.6 4.2h1.4v2h-1.4z" transform="rotate(45 12.3 5.2)" />
    </svg>
  ),
  onDismount() {},
}));
