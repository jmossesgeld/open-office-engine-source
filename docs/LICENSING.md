# Licensing of the engine

What each piece of the engine is licensed under, checked against the source headers it is built from.

| Piece | Where it comes from | Licence | How it is combined |
|---|---|---|---|
| LibreOffice core | `LibreOffice/core`, branch `distro/allotropia/zeta-24-2`, commit in `build/pins.env` | MPL-2.0 for most files; some files LGPL-3.0-or-later or dual MPL/LGPL (mostly inherited from OpenOffice.org: Apache-2.0 headers with an MPL notice) | statically linked into `soffice.wasm` |
| Our patches to LibreOffice | `build/patches/core/*.patch` | MPL-2.0 (they modify MPL files) | as above |
| Qt 5.15.2 (`qtbase` only) | `allotropia/qtbase`, branch `5.15.2+wasm`, commit in `build/pins.env` | Most of qtbase: LGPL-3.0 / GPL-2.0 / GPL-3.0 / commercial. The WebAssembly platform plugin (`src/plugins/platforms/wasm/`): GPL-3.0 or commercial | statically linked into `soffice.wasm` |
| Bundled third-party libraries (`external/`: boost, ICU, libxml2, cairo, harfbuzz, freetype, fontconfig, zlib, libpng, libjpeg-turbo, openssl, expat, the libwpd/libwps family and others) | LibreOffice's pinned tarballs | Their own permissive or LGPL licences, listed in LibreOffice's `readlicense_oo/license/license.xml` | statically linked |
| Fonts in `soffice.data` | LibreOffice's bundled fonts (Liberation, Carlito, Caladea, DejaVu, Noto, Linux Libertine/Biolinum, OpenSymbol and others) | SIL OFL 1.1, Apache-2.0, GPL with font exception, per font | data files |
| Emscripten runtime | `emscripten-core/emscripten` 3.1.65 plus allotropia's four commits (`build/patches/emscripten/`) | MIT / University of Illinois NCSA | generated into `soffice.js` and linked libc/libc++ |
| zetajs 1.2.0 | npm `zetajs` | MIT | separate script run in the engine's worker |
| `office-thread.js` | ours | MIT | separate script run in the engine's worker |

Because the Qt WebAssembly plugin is GPL-3.0, `soffice.wasm` as a whole is distributed under the GPL
version 3 or later. MPL-2.0 permits that combination (MPL §3.3, "secondary licence"), and LGPL-3.0 code
may be combined into a GPL-3.0 work. Each component keeps its own licence.
