#!/usr/bin/env bash
# Builds OpenSCAD's third-party dependencies for wasm32-emscripten into
# /work/prefix. Runs inside the build image (see ../Dockerfile, ../build.sh).
# Each library is built once; a stamp file in /work/stamps skips it next time.
set -euo pipefail

JOBS=${JOBS:-4}
WORK=/work
PREFIX=$WORK/prefix
SRC=$WORK/deps-src
STAMPS=$WORK/stamps
CROSS=/repo/cross/emscripten.meson
mkdir -p "$PREFIX" "$SRC" "$STAMPS"

SYSROOT_PC=/emsdk/upstream/emscripten/cache/sysroot/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:$SYSROOT_PC
export PKG_CONFIG_PATH=$PKG_CONFIG_LIBDIR
export CFLAGS="-O2 -fexceptions"
export CXXFLAGS="-O2 -fexceptions"
export LDFLAGS="-fexceptions"

# name|version|url
DEPS=(
  "zlib|port|-"
  "boost|1.86.0|https://github.com/boostorg/boost/releases/download/boost-1.86.0/boost-1.86.0-cmake.tar.xz"
  "eigen|3.4.0|https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz"
  "gmp|6.3.0|https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz"
  "mpfr|4.2.1|https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.xz"
  "cgal|6.0.1|https://github.com/CGAL/cgal/releases/download/v6.0.1/CGAL-6.0.1-library.tar.xz"
  "double-conversion|3.3.0|https://github.com/google/double-conversion/archive/refs/tags/v3.3.0.tar.gz"
  "freetype|2.13.3|https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-3.tar.gz"
  "harfbuzz|10.1.0|https://github.com/harfbuzz/harfbuzz/releases/download/10.1.0/harfbuzz-10.1.0.tar.xz"
  "expat|2.6.4|https://github.com/libexpat/libexpat/releases/download/R_2_6_4/expat-2.6.4.tar.xz"
  "fontconfig|2.15.0|https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.15.0.tar.xz"
  "libffi|3.5.2|https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz"
  "pcre2|10.44|https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.bz2"
  "glib|2.84.1|https://download.gnome.org/sources/glib/2.84/glib-2.84.1.tar.xz"
  "libzip|1.11.2|https://github.com/nih-at/libzip/releases/download/v1.11.2/libzip-1.11.2.tar.xz"
  "libxml2|2.13.5|https://download.gnome.org/sources/libxml2/2.13/libxml2-2.13.5.tar.xz"
)

fetch() { # name version url -> echoes source dir
  local name=$1 ver=$2 url=$3 dir=$SRC/$1-$2
  if [ ! -d "$dir" ]; then
    local tmp=$SRC/.dl-$name
    rm -rf "$tmp" && mkdir -p "$tmp"
    curl -fsSL "$url" -o "$tmp/archive"
    tar -xf "$tmp/archive" -C "$tmp"
    rm "$tmp/archive"
    mv "$tmp"/* "$dir"
    rm -rf "$tmp"
    # Local fixes, one documented .patch per problem (see ../patches/).
    local p
    for p in /repo/patches/"$name-$ver"-*.patch; do
      [ -e "$p" ] || continue
      patch -d "$dir" -p1 < "$p" >&2
    done
  fi
  echo "$dir"
}

cmake_dep() { # srcdir [cmake args...]
  local src=$1; shift
  rm -rf "$src/_build"
  emcmake cmake -S "$src" -B "$src/_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=OFF \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" "$@"
  cmake --build "$src/_build" -j"$JOBS"
  cmake --install "$src/_build"
}

meson_dep() { # srcdir [meson args...]
  local src=$1; shift
  rm -rf "$src/_build"
  meson setup "$src/_build" "$src" --cross-file "$CROSS" \
    --prefix="$PREFIX" --libdir=lib --buildtype=release \
    --default-library=static --wrap-mode=nofallback "$@"
  meson compile -C "$src/_build" -j "$JOBS"
  meson install -C "$src/_build"
}

auto_dep() { # srcdir [configure args...]
  local src=$1; shift
  (cd "$src" && emconfigure ./configure --prefix="$PREFIX" --host=wasm32-unknown-emscripten \
      --disable-shared --enable-static "$@" && emmake make -j"$JOBS" && emmake make install)
}

build_one() {
  local name=$1 ver=$2 dir=$3
  case $name in
    zlib) # The emsdk zlib port: OpenSCAD links the sysroot's libz.a by absolute
          # path, so every library uses that one copy.
          embuilder build zlib ;;
    # Boost.Container (pulled in as a dependency) picks its mutex by platform;
    # emscripten's libc has the pthread API (single-threaded stubs).
    # Only regex and program_options are compiled; OpenSCAD and CGAL also use
    # many header-only libraries, which Boost's CMake install leaves out when
    # BOOST_INCLUDE_LIBRARIES is set, so every library's headers are copied.
    boost) CXXFLAGS="$CXXFLAGS -DBOOST_HAS_PTHREADS" cmake_dep "$dir" \
             -DBOOST_INCLUDE_LIBRARIES="regex;program_options" \
             -DBOOST_ENABLE_MPI=OFF -DBOOST_ENABLE_PYTHON=OFF
           find "$dir/libs" -type d -path '*/include/boost' -prune -print | while read -r inc; do
             cp -rn "$inc" "$PREFIX/include/"
           done ;;
    eigen) cmake_dep "$dir" -DBUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF -DEIGEN_BUILD_PKGCONFIG=ON ;;
    gmp) (cd "$dir" && CC_FOR_BUILD=gcc emconfigure ./configure --prefix="$PREFIX" --host=none \
             --disable-assembly --enable-cxx --disable-shared --enable-static \
           && emmake make -j"$JOBS" && emmake make install) ;;
    mpfr) (cd "$dir" && emconfigure ./configure --prefix="$PREFIX" --host=none \
             --with-gmp="$PREFIX" --disable-shared --enable-static \
           && emmake make -j"$JOBS" && emmake make install) ;;
    cgal) cmake_dep "$dir" -DCGAL_DISABLE_GMP=OFF -DWITH_CGAL_Qt6=OFF -DWITH_demos=OFF -DWITH_examples=OFF ;;
    double-conversion) cmake_dep "$dir" -DBUILD_TESTING=OFF ;;
    freetype) cmake_dep "$dir" -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
                -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_REQUIRE_ZLIB=ON ;;
    harfbuzz) meson_dep "$dir" -Dtests=disabled -Ddocs=disabled -Dutilities=disabled \
                -Dbenchmark=disabled -Dintrospection=disabled -Dglib=disabled \
                -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dgraphite2=disabled \
                -Dfreetype=enabled -Dchafa=disabled ;;
    expat) cmake_dep "$dir" -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF \
             -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_DOCS=OFF -DEXPAT_SHARED_LIBS=OFF ;;
    fontconfig) meson_dep "$dir" -Ddoc=disabled -Dtests=disabled -Dtools=disabled \
                  -Dcache-build=disabled -Dnls=disabled ;;
    # libffi is only for glib's GObject (OpenSCAD uses plain glib-2.0), but
    # glib builds GObject and its tools regardless. 3.5.x: the 3.4 wasm32 port
    # calls emscripten internals ($generateFuncType, $uleb128Encode) that
    # current emscripten no longer has.
    libffi) auto_dep "$dir" --disable-docs --disable-multi-os-directory ;;
    pcre2) cmake_dep "$dir" -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF \
             -DPCRE2_SUPPORT_JIT=OFF ;;
    glib) # GIO's configure insists on res_query(); emscripten has no resolver.
          # OpenSCAD only uses GLib's string/unicode helpers, so a stub
          # libresolv that always fails is enough to configure and link.
          mkdir -p "$WORK/shims"
          printf '%s\n' '#include <errno.h>' \
            'int res_query(const char *d, int c, int t, unsigned char *a, int l) { (void)d; (void)c; (void)t; (void)a; (void)l; errno = ENOSYS; return -1; }' \
            > "$WORK/shims/resolv_stub.c"
          emcc -O2 -c "$WORK/shims/resolv_stub.c" -o "$WORK/shims/resolv_stub.o"
          emar rcs "$PREFIX/lib/libresolv.a" "$WORK/shims/resolv_stub.o"
          meson_dep "$dir" -Dtests=false -Dintrospection=disabled -Dnls=disabled \
            -Dlibmount=disabled -Dselinux=disabled -Dxattr=false -Dman-pages=disabled \
            -Ddocumentation=false -Dsysprof=disabled -Dglib_debug=disabled \
            -Dlibelf=disabled -Dglib_assert=false --wrap-mode=default \
            "-Dc_args=-O2 -fexceptions -Wno-error=incompatible-function-pointer-types" ;;
    libzip) cmake_dep "$dir" -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
              -DENABLE_OPENSSL=OFF -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF \
              -DENABLE_COMMONCRYPTO=OFF -DENABLE_WINDOWS_CRYPTO=OFF \
              -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF \
              -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF ;;
    libxml2) cmake_dep "$dir" -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_LZMA=OFF \
               -DLIBXML2_WITH_ICONV=OFF -DLIBXML2_WITH_ICU=OFF -DLIBXML2_WITH_HTTP=OFF \
               -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_THREADS=OFF ;;
    *) echo "unknown dep $name" >&2; exit 1 ;;
  esac
}

for entry in "${DEPS[@]}"; do
  IFS='|' read -r name ver url <<<"$entry"
  stamp=$STAMPS/$name-$ver
  if [ -f "$stamp" ]; then echo "== $name $ver (done)"; continue; fi
  echo "== $name $ver"
  dir=-
  [ "$url" = - ] || dir=$(fetch "$name" "$ver" "$url")
  build_one "$name" "$ver" "$dir"
  touch "$stamp"
done
echo "== deps done"
