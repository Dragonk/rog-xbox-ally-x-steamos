import { renderToStaticMarkup } from 'react-dom/server';
import React from 'react';
globalThis.SP_REACT = React;
Object.defineProperty(globalThis, 'navigator', { value: { language: 'pl-PL' }, configurable: true });
globalThis.window = { DECKY_API: { callable: () => async () => ({ enabled: true, preset: 'movie/balanced', mic: 'on' }) } };
const mod = await import('./panel.mjs');
const def = mod.default();
const html = renderToStaticMarkup(def.content);
console.log('render: OK, HTML', html.length, 'znakow');
for (const s of ['Ally Audio','Ulepszenie audio','Profil','Brzmienie','Ulepszenie mikrofonu','Włącz']) {
  console.log(`  "${s}":`, html.includes(s));
}
console.log('  selecty:', (html.match(/<select/g) || []).length, '| przyciski:', (html.match(/<button/g) || []).length);
console.log('  titleView OK:', renderToStaticMarkup(def.titleView).includes('Ally Audio'));
console.log('  icon OK:', renderToStaticMarkup(def.icon).length > 0);
