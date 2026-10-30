# open-office-engine-source

The corresponding source for an office engine that runs in the browser: LibreOffice compiled to
WebAssembly, with Qt 5 for WebAssembly and the Emscripten runtime.

**This is not Apache OpenOffice** and is not made by or affiliated with The Apache Software Foundation,
The Document Foundation, The Qt Company or allotropia. It is one build of LibreOffice, published to
meet the licences of the code in it.

## What is here

| Path | What it is |
|---|---|
| `build/` | The pinned toolchain (`Dockerfile`, `pins.env`), the build (`build.sh`, `in-container.sh`, `autogen.input`), packaging (`package-engine.mjs`) and every patch we apply (`patches/`) |
| `engine-scripts/` | The scripts that run inside the engine's worker (`office-thread.js`, `zeta.js` with its licence) |
| `docs/BUILDING.md` | How to rebuild the engine, and what each patch does |
| `docs/LICENSING.md` | What is in the engine and under which licence |
| `docs/ENGINE-NOTICE.md` | The notice that ships with the engine |

The full source trees are too large for Git. Each engine build has a [release](../../releases) named
after its build id, holding the LibreOffice core tree with the patches applied, qtbase, Emscripten and
the third-party tarballs the build used, plus `SHA256SUMS`.

## Rebuilding

```bash
bash build/build.sh release
node build/package-engine.mjs build/out/<build id>
```

This needs Docker and about 60 GB of free disk. See `docs/BUILDING.md`.

## Licence

The engine as a combined work is distributed under the GNU General Public License version 3 or later
(`LICENSE`), because Qt's WebAssembly platform plugin is GPL-3.0. Each component keeps its own licence,
listed in `docs/LICENSING.md`. Our changes to LibreOffice files stay under the Mozilla Public License
2.0, like the files they change.
