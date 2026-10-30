# Building the engine

One command, rerunnable:

```bash
bash build/build.sh release       # or: assertions (Emscripten ASSERTIONS=1, the upstream default)
```

It needs Docker (Docker Desktop on Windows works, from Git Bash) and about 60 GB of free disk for
Docker's data. Output: `build/out/<variant>-<core commit>-<patch-set hash>/`, holding the web root
(`soffice.js`, `soffice.wasm`, `soffice.data`, `soffice.data.js.metadata`, plus `qt_soffice.html` and
`qtloader.js`, which we do not use) and `build-info.json` (inputs, timings, peak memory, disk, file
sizes and hashes). Logs go to `build/logs/`.

## What it does

1. **Toolchain image** (`build/Dockerfile`), tagged by a hash of its inputs and only rebuilt when they
   change (Docker Desktop garbage-collects BuildKit's cache, so the tag is what makes reruns cheap):
   - Ubuntu 24.04 with LibreOffice's build dependencies;
   - emsdk 3.1.65, plus `build/patches/emscripten/` (allotropia's four commits on 3.1.65);
   - Qt 5.15.2 for WebAssembly: allotropia's `qtbase` at the pinned commit, `-feature-thread`,
     `SUPPORT_LONGJMP=wasm`, no tests or examples. About 3 minutes.
2. **LibreOffice core** (`build/in-container.sh`) in the `mage-office-core` Docker volume, with the
   downloaded third-party tarballs cached in `mage-office-tarballs`:
   - fetches the pinned commit (shallow) once;
   - applies `build/patches/core/*.patch` (when the patch set changes, it reverts only the files the
     previous set touched, so make rebuilds little);
   - runs `autogen.sh` with `build/autogen.input` (re-run only when that file changes);
   - `make build` with the variant's `EMSCRIPTEN_ASSERTIONS`; a variant or patch change relinks;
   - copies the emscripten web root out with `build-info.json`.
3. **Packaging** (separate): `node build/package-engine.mjs build/out/<id>` writes
   `dist/engine/<id>/` (each file raw and as `.br`, Brotli quality 11), `NOTICE.md`, and the manifest
   `dist/engine/engine.json` that the editor loads.

All inputs are pinned in `build/pins.env`: base image, emsdk version, qtbase commit, LibreOffice core
commit. The third-party tarballs are pinned by LibreOffice's own `download.lst` (name and sha256).

## Patches

| Patch | What |
|---|---|
| `emscripten/0001-allotropia-fixed-3.1.65.patch` | allotropia's `fixed-3.1.65` branch over 3.1.65: asynchronous `_emscripten_run_callback_on_thread`, pthread worker names, embind leak-warning changes |
| `core/0001-emscripten-link-knobs.patch` | `EMSCRIPTEN_ASSERTIONS`, `EMSCRIPTEN_INITIAL_MEMORY`, `EMSCRIPTEN_MAXIMUM_MEMORY` (growable memory) as make variables |
| `core/0002-xlsx-unnamed-font-inherits-default.patch` | .xlsx fonts with no `<name>`/`<sz>` take the workbook default font's (Excel's behaviour), not "Cambria" |
| `core/0003-xlsx-undeclared-paper-size-stays-undeclared.patch` | a sheet with no paper size is exported with none (Excel then uses the printer's), not as Letter |
| `core/0004-emscripten-keep-pthread-exports.patch` | keeps the exports the engine's worker threads need at link time |

To write a new core patch: change the files in a LibreOffice checkout at `CORE_COMMIT` and save
`git diff` (paths relative to the core root) as the next numbered file. A sparse checkout of just the
module is enough (`git sparse-checkout set --no-cone /sc/source/filter/`, with `MSYS_NO_PATHCONV=1` in
Git Bash).

## Measurements

On the build PC (28 cores, 32 GB, Docker Desktop on WSL2), 2026-10-27:

| Step | Time | Peak memory | Disk |
|---|---:|---:|---:|
| Toolchain image (apt, emsdk, Qt qtbase) | about 5 min (Qt about 3) | — | 4 GB image |
| LibreOffice clean build: compile | about 22 min (CPU about 21 cores busy) | 5.3 GB | 7.5 GB build tree |
| Link `soffice` (release, ASSERTIONS off, -O3) | about 5 min | — | — |
| A patch to one module, then relink | 8–10 min | — | — |
| Packaging (Brotli 11) | about 7 min | — | — |

| Build | soffice.wasm | soffice.data | Brotli total |
|---|---:|---:|---:|
| allotropia CDN (May 2025, for comparison) | 161.7 MB | 99.5 MB | 52.5 MB |
| ours, ASSERTIONS on | 150.0 MB | 89.5 MB | — |
| ours, release, growable memory | 148.1 MB | 89.5 MB | 51.0 MB |

The build also links a few executables we do not ship (`vcldemo`, `unoidl-read`…), a few minutes per
relink.
