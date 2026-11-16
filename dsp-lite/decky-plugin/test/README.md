# Panel render test

Validates the panel outside the device: loads `../dist/index.js` with a real React,
stubs `SP_REACT`, `navigator` (Polish locale) and the Decky backend, then renders the
panel to static HTML. It fails on invalid hook calls — the class of bug that shows up in
Decky as "Minified React error #321".

```bash
npm i react@18 react-dom@18
node test/render.mjs
```

Expected: HTML length > 0 and every Polish label present.
