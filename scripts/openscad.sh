#!/usr/bin/env bash
# Configures and builds OpenSCAD (headless, no GL) for wasm32-emscripten
# against the libraries in /work/prefix, then copies the module to /repo/dist.
# Runs inside the build image (see ../build.sh).
set -euo pipefail

JOBS=${JOBS:-3}
PREFIX=/work/prefix
BUILD=/work/build-openscad
# The tag's version (YYYY.MM[-PPP]), from build.sh; without it OpenSCAD's CMake
# falls back to today's date. lib3mf is not built: only OFF is exported, and
# OpenSCAD then compiles its dummy 3MF import/export.
: "${OPENSCAD_VERSION:?set by build.sh}"
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:/emsdk/upstream/emscripten/cache/sysroot/lib/pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_LIBDIR

# OpenSCAD's CMake (WASM_BUILD_TYPE=web) already links with MODULARIZE,
# EXPORT_ES6, EXPORT_NAME=OpenSCAD and exports FS + callMain. The extra link
# flags below widen ENVIRONMENT to node (so tests can run it under vitest) and
# stop main() running when the module is created. They go in
# CMAKE_CXX_STANDARD_LIBRARIES, the end of the link line, so they come after
# OpenSCAD's own -sENVIRONMENT=web,worker (the last -s setting wins);
# CMAKE_EXE_LINKER_FLAGS comes before it. -lexpat: static fontconfig needs it,
# and OpenSCAD reads fontconfig's non-static pkg-config Libs, which omit it.
EXTRA_LINK="-sENVIRONMENT=web,worker,node -sINVOKE_RUN=0 -L$PREFIX/lib -lexpat"

# OpenSCAD's CMake links the emsdk zlib port as $cache/sysroot/lib/libz.a, where
# older emscripten kept it; current emscripten has it in lib/wasm32-emscripten/.
SYSROOT_LIB=/emsdk/upstream/emscripten/cache/sysroot/lib
[ -e "$SYSROOT_LIB/libz.a" ] || ln -s wasm32-emscripten/libz.a "$SYSROOT_LIB/libz.a"

if [ ! -f "$BUILD/build.ninja" ]; then
  emcmake cmake -S /repo/src-openscad -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DWASM_BUILD_TYPE=web \
    -DEXPERIMENTAL=ON \
    -DENABLE_TESTS=OFF \
    -DUSE_CCACHE=OFF \
    -DOFFLINE_DOCS=OFF \
    -DOPENSCAD_VERSION="$OPENSCAD_VERSION" \
    -DCMAKE_REQUIRE_FIND_PACKAGE_Lib3MF=OFF \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
    -DBoost_ROOT="$PREFIX" \
    -DCMAKE_CXX_STANDARD_LIBRARIES="$EXTRA_LINK"
fi
cmake --build "$BUILD" -j"$JOBS" --target OpenSCADExe

mkdir -p /repo/dist
cp "$BUILD/openscad.js" "$BUILD/openscad.wasm" /repo/dist/
echo "== built: $(ls -l /repo/dist)"
