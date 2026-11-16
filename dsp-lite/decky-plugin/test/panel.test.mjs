import React from 'react';
import TestRenderer, { act } from 'react-test-renderer';
import * as jsxRuntime from 'react/jsx-runtime';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const lang = process.env.TEST_LANG || 'pl-PL';
const FAIL = process.env.FAIL === '1';
const HERE = dirname(fileURLToPath(import.meta.url));
const BUNDLE = process.env.BUNDLE || join(HERE, '..', 'dist', 'index.js');
const g = globalThis;
Object.defineProperty(g, 'navigator', { value: { language: lang }, configurable: true });
g.SP_REACT = React;
g.SP_JSX = jsxRuntime;
g.window = g;

// Decky's real @decky/ui only loads inside the Steam client (webpack chunk), so the
// component boundary is stubbed here; everything else is the real shipped bundle.
const mk = (tag) => {
  const C = (props) => React.createElement('div', { 'data-c': tag }, props.children ?? null);
  C.displayName = tag;
  return C;
};
g.DFL = {
  PanelSection: mk('PanelSection'), PanelSectionRow: mk('PanelSectionRow'), ToggleField: mk('ToggleField'),
  DropdownItem: mk('DropdownItem'), ButtonItem: mk('ButtonItem'), Field: mk('Field'),
  staticClasses: { Title: 'DialogHeader' },
};

let state = { enabled: true, active: 1, preset: 'movie/balanced', mic: 'off' };
const calls = [];
const connectArgs = [];
g.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit = {
  connect: (v, name) => {
    connectArgs.push([v, name]);
    return {
      _version: v,
      callable: (fn) => async (...args) => {
        calls.push(fn + '(' + args.join(',') + ')');
        if (FAIL) throw new Error('backend down');
        if (fn === 'set_enabled') state = { ...state, enabled: args[0] };
        if (fn === 'set_preset') state = { ...state, preset: args[0] + '/' + args[1] };
        if (fn === 'set_mic') state = { ...state, mic: args[0] ? 'on' : 'off' };
        return state;
      },
    };
  },
};

const src = fs.readFileSync(BUNDLE, 'utf8')
  .replace(/export \{ index as default \};?/, 'return index;')
  .replace(/\/\/# sourceMappingURL=.*$/, '');
const exported = new Function(src)();
const plugin = typeof exported === 'function' ? exported() : exported;

const results = [];
const check = (name, ok, extra = '') => results.push((ok ? 'PASS ' : 'FAIL ') + name + (extra ? ' :: ' + extra : ''));
const flush = async () => { await act(async () => { await new Promise((r) => setTimeout(r, 20)); }); };

let tree;
await act(async () => { tree = TestRenderer.create(plugin.content); });
await flush();

const nodes = (type) => tree.root.findAll((n) => n.type && n.type.displayName === type, { deep: true });
const label = (n) => n.props.label || '';
const allText = tree.root.findAll(() => true).map((n) => {
  const p = n.props || {};
  const parts = [p.label, p.description, p.title, typeof p.children === 'string' ? p.children : null];
  if (Array.isArray(p.rgOptions)) parts.push(p.rgOptions.map((o) => o.label).join(' '));
  return parts.filter(Boolean).join(' ');
}).join(' ');

check('plugin factory returns a definition object', typeof plugin === 'object' && !!plugin.name && !!plugin.content);
check('plugin connects with API v2 as "Ally Audio"', connectArgs.length === 1 && connectArgs[0][0] === 2 && connectArgs[0][1] === 'Ally Audio', JSON.stringify(connectArgs));

const toggles = nodes('ToggleField');
const drops = nodes('DropdownItem');
check('two toggles + two dropdowns rendered', toggles.length === 2 && drops.length === 2, `toggles=${toggles.length} drops=${drops.length}`);

const tEnh = toggles.find((n) => /audio/i.test(label(n)));
const tMic = toggles.find((n) => /mikrofon|microphone/i.test(label(n)));
const dProf = drops.find((n) => /profil/i.test(label(n)));
const dVoic = drops.find((n) => /brzmienie|voicing/i.test(label(n)));
check('controls findable by localized label', !!tEnh && !!tMic && !!dProf && !!dVoic);

if (!FAIL) {
  check('get_state fetched on mount', calls.includes('get_state()'), calls.join(' '));
  check('toggle reflects backend state', tEnh && tEnh.props.checked === true);
  check('profile dropdown reflects movie', dProf && dProf.props.selectedOption === 'movie');
  check('voicing dropdown reflects balanced', dVoic && dVoic.props.selectedOption === 'balanced');
  check('5 profiles offered', dProf && dProf.props.rgOptions.length === 5, dProf && dProf.props.rgOptions.map((o) => o.data).join(','));
  check('3 voicings offered', dVoic && dVoic.props.rgOptions.length === 3);

  await act(async () => { await tEnh.props.onChange(false); });
  await flush();
  check('enhancement toggle calls set_enabled(false)', calls.includes('set_enabled(false)'), calls.join(' '));
  check('toggle re-renders from backend answer', nodes('ToggleField').find((n) => /audio/i.test(label(n))).props.checked === false);

  await act(async () => { await dProf.props.onChange({ data: 'music' }); });
  await flush();
  check('profile change calls set_preset(music,balanced)', calls.includes('set_preset(music,balanced)'), calls.join(' '));
  check('dropdown re-renders from backend answer', nodes('DropdownItem').find((n) => /profil/i.test(label(n))).props.selectedOption === 'music');

  await act(async () => { await nodes('ToggleField').find((n) => /mikrofon|microphone/i.test(label(n))).props.onChange(true); });
  await flush();
  check('mic toggle calls set_mic(true)', calls.includes('set_mic(true)'), calls.join(' '));
} else {
  const errText = lang.startsWith('pl') ? 'Brak połączenia z backendem' : 'No connection to the backend';
  check('backend failure surfaces an error row', allText.includes(errText), 'expected "' + errText + '"');
}

const expect = lang.startsWith('pl')
  ? ['Ulepszenie audio', 'Profil', 'Brzmienie', 'Ulepszenie mikrofonu', 'Film', 'Zbalansowane', 'Odśwież']
  : ['Audio enhancement', 'Profile', 'Voicing', 'Microphone enhancement', 'Movie', 'Balanced', 'Refresh'];
for (const word of expect) check('localized "' + word + '"', allText.includes(word));
check('no leftover globals from the old broken build', !/sp_dfl|DECKY_API/.test(allText));
check('no leftover legacy wording', !/wyłącz mikrofon|enable microphone/i.test(allText));

console.log(results.join('\n'));
const failed = results.filter((r) => r.startsWith('FAIL'));
console.log('\n' + (failed.length === 0 ? 'ALL PASS (' + results.length + ')' : failed.length + ' FAILED of ' + results.length));
process.exit(failed.length === 0 ? 0 : 1);
