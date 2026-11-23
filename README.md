# openscad-wasm-cubby

OpenSCAD compiled to WebAssembly from OpenSCAD's own source, for CubbyCAD's
OpenSCAD script parts.

This repository holds only build scripts. It does not use the `openscad-wasm`
npm package or the openscad/openscad-wasm project's scripts or patches. The
OpenSCAD source is OpenSCAD's own release tag, built with OpenSCAD's own
`CMakeLists.txt` Emscripten support (`WASM_BUILD_TYPE=web`).

## What it builds

- OpenSCAD `openscad-2026.11-RC1` (commit `2127234b37d77786a7b5b49b4493b37606c96cd5`),
  pinned in `build.sh`, with the Manifold geometry backend (`--backend=manifold`).
- Output in `dist/`:
  - `openscad.js`: ES module, default export the Emscripten factory `OpenSCAD`
    (`MODULARIZE`, `EXPORT_ES6`); the instance exposes `callMain` and `FS`.
  - `openscad.wasm`
  - `version.json`: OpenSCAD version, tag, commit, Emscripten version, build time.
- Headless: no GUI, no OpenGL (`NULLGL`), no Cairo. Text needs fonts, and none
  are bundled.

## Building

Needs Docker and git. Everything else (Emscripten SDK 6.0.13, meson, ninja,
autotools) is in the build image (`Dockerfile`).

```bash
./build.sh            # JOBS=4 by default for the dependencies
```

`build.sh` clones the pinned OpenSCAD tag into `src-openscad/` (with its
submodules: manifold, Clipper2, ...), builds the image, builds the third-party
libraries into `work/prefix` (`scripts/deps.sh`, one stamp per library in
`work/stamps`), then OpenSCAD (`scripts/openscad.sh`). `work/`, `src-openscad/`
and `dist/` are not committed.

In CubbyCAD: `npm run stage:openscad-wasm` copies `dist/` into
`public/wasm/openscad/`.

## Local patches and build notes

`patches/<name>-<version>-*.patch` are applied to a dependency's source right
after it is downloaded. Each starts with a note on why. Only glib needs any:

- `glib-2.84.1-emscripten-size_t.patch`: Meson reports emcc as compiler id
  `emscripten`, so glib skipped its check of which type `size_t` is and made
  `gsize` an `unsigned int`; Emscripten's `size_t` is `unsigned long`, and
  `glib/gconvert.c` then fails with incompatible pointer types. The patch runs
  the check for emcc too.
- `glib-2.84.1-emscripten-no-threads.patch`: Meson adds `-pthread` for
  `dependency('threads')` on Emscripten, and OpenSCAD's module is
  single-threaded (objects built with atomics can't link into it); glib uses
  Emscripten's single-threaded pthread stubs instead. It also skips two
  header-only checks (`pthread_getname_np`, `posix_spawn`) for functions
  Emscripten's libc declares but doesn't implement.

Other notes:

- libffi is 3.5.x: glib needs it for GObject (OpenSCAD itself only uses
  `glib-2.0`), and the 3.4 wasm32 port calls Emscripten internals that current
  Emscripten no longer has.
- lib3mf is not built (only OFF is exported); OpenSCAD compiles its dummy 3MF
  import / export.
- OpenSCAD's CMake links the zlib port as `cache/sysroot/lib/libz.a`, an older
  Emscripten layout; `scripts/openscad.sh` adds a symlink in the build's own
  Emscripten cache.

The OpenSCAD source itself is not patched. `scripts/openscad.sh` adds
`-sENVIRONMENT=web,worker,node -sINVOKE_RUN=0` at the end of the link line
(so the module also loads under Node for tests, and `main()` runs only through
`callMain`).

## Licenses

OpenSCAD is GPL-2.0-or-later (`COPYING`). The built module also contains the
libraries listed in `licenses/` (copied from their sources by
`scripts/collect-licenses.sh`), among them CGAL (GPL-3.0-or-later / LGPL
parts), GMP and MPFR (LGPL-3.0-or-later), Manifold (Apache-2.0), Clipper2
(BSL-1.0), Boost (BSL-1.0), Eigen (MPL-2.0), glib (LGPL-2.1-or-later),
FreeType (FTL), HarfBuzz (MIT), fontconfig (MIT), expat (MIT), libffi (MIT),
PCRE2 (BSD-3-Clause), libzip (BSD-3-Clause), libxml2 (MIT),
double-conversion (BSD-3-Clause), zlib and the Emscripten runtime (MIT /
University of Illinois) under their own licenses. Taken together
the module is distributed under the GPL-3.0-or-later (compatible with the
AGPL-3.0-or-later CubbyCAD is under). The build scripts in this repository are
GPL-2.0-or-later, like OpenSCAD.

Anyone given the module can get its complete corresponding source: this
repository plus the pinned upstream sources it downloads.
