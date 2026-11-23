#!/usr/bin/env bash
# Copies the license files of OpenSCAD and of every library linked into the
# module into licenses/ (committed), after a build has fetched the sources.
set -euo pipefail
cd "$(dirname "$0")/.."

out=licenses
rm -rf "$out" && mkdir -p "$out"

copy_from() { # name dir [extra files...]
  local name=$1 dir=$2; shift 2
  mkdir -p "$out/$name"
  local found=0
  for f in "$dir"/COPYING* "$dir"/LICEN[CS]E* "$dir"/Copyright "$@"; do
    [ -f "$f" ] || continue
    cp "$f" "$out/$name/"
    found=1
  done
  [ $found = 1 ] || { echo "no license file found for $name in $dir" >&2; exit 1; }
}

cp src-openscad/COPYING COPYING
copy_from openscad src-openscad
copy_from manifold src-openscad/submodules/manifold
copy_from clipper2 src-openscad/submodules/Clipper2
for d in work/deps-src/*/; do
  base=$(basename "$d")
  name=${base%-*}
  case $name in
    freetype) copy_from "$name" "$d" "$d/docs/FTL.TXT" "$d/docs/GPLv2.TXT" ;;
    *) copy_from "$name" "$d" ;;
  esac
done
zlib_dir=$(ls -d work/emcache/ports/zlib/zlib-* 2>/dev/null | head -1 || true)
[ -n "$zlib_dir" ] && copy_from zlib "$zlib_dir" "$zlib_dir/README"
emscripten_license=$(docker run --rm openscad-wasm-cubby-build:emsdk-6.0.13 cat /emsdk/upstream/emscripten/LICENSE)
mkdir -p "$out/emscripten" && printf '%s\n' "$emscripten_license" > "$out/emscripten/LICENSE"
find "$out" -type f | sort
