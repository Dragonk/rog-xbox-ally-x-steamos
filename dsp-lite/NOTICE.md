# Provenance and licensing notice

`presets/` and `lv2/` are **not** MIT-licensed like the rest of this repository, and they
are not authored here.

## presets/

Fifteen PipeWire filter-chain configurations (`chain.conf` + `ir.irs`) generated from the
official **ASUS "Dolby Atmos driver"** package for the ROG Xbox Ally X (RC73XA) — the same
OEM package that Windows installs for this device (version `V11.130.1340.46`, SHA-256
`b649614c0da2bea51096e47d503d753928446f8b275de55647772f29d19c2fd7`). The tuning values
originate from ASUS/Dolby; the conversion to PipeWire nodes is done by the MIT-licensed
converter `speaker-tuning-to-easyeffects`.

They are included here so that installation needs no manual step. If you are the rights
holder and want them removed, open an issue and they will be deleted — the `install.sh`
fallback then downloads the ASUS package and regenerates them locally instead.

## lv2/

`lsp-plugins-lv2.so` and its Turtle manifests come from the **LSP Plugins** project by
Vladimir Sadovnikov, licensed **LGPL-3.0** (`lv2/lsp-plugins.lv2/LICENSE.LGPL-3.0.txt`).
They are bundled unmodified because SteamOS ships `liblilv` but no LSP bundle.
