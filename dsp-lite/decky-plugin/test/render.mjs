import { renderToStaticMarkup } from 'react-dom/server';
import React from 'react';
globalThis.SP_REACT = React;
Object.defineProperty(globalThis, 'navigator', { value: { language: 'pl-PL' }, configurable: true });
const state = { enabled: true, preset: 'movie/balanced', mic: 'on' };
let connectVersion = null, calls = [];
globalThis.window = {
  __DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit: {
    connect: (v, name) => {
      connectVersion = v; calls.push(['connect', v, name]);
      return { callable: (m) => async (...a) => { calls.push([m, ...a]); return state; } };
    },
  },
};
const mod = await import('./panel.mjs');
const def = mod.default();
const html = renderToStaticMarkup(def.content);
console.log('connect wywolany:', JSON.stringify(calls[0]));
console.log('render OK:', html.length, 'znakow');
console.log('brak bledu backendu:', !html.includes('Brak połączenia'));
console.log('pokazuje stan wlaczony:', html.includes('włączone'));
console.log('profil Film:', html.includes('Film'));
