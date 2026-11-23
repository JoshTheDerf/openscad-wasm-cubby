#!/usr/bin/env bash
# Builds OpenSCAD to WebAssembly from OpenSCAD's own source.
# Output: dist/openscad.js (ES module, factory `OpenSCAD`), dist/openscad.wasm,
# dist/version.json. See README.md.
set -euo pipefail
cd "$(dirname "$0")"

OPENSCAD_TAG=openscad-2026.11-RC1
OPENSCAD_COMMIT=2127234b37d77786a7b5b49b4493b37606c96cd5
IMAGE=openscad-wasm-cubby-build:emsdk-6.0.13

if [ ! -d src-openscad ]; then
  git clone --depth 1 --branch "$OPENSCAD_TAG" --recurse-submodules --shallow-submodules \
    https://github.com/openscad/openscad.git src-openscad
fi
actual=$(git -C src-openscad rev-parse HEAD)
if [ "$actual" != "$OPENSCAD_COMMIT" ]; then
  echo "src-openscad is at $actual, expected $OPENSCAD_COMMIT ($OPENSCAD_TAG)" >&2
  exit 1
fi

docker build -t "$IMAGE" -f Dockerfile .
mkdir -p work/emcache
run() {
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
    -e JOBS="${JOBS:-}" -e OPENSCAD_VERSION="${OPENSCAD_TAG#openscad-}" -v "$PWD:/repo" -v "$PWD/work:/work" \
    -v "$PWD/work/emcache:/emsdk/upstream/emscripten/cache" -w /work "$IMAGE" "$@"
}
# Seed the persistent emscripten cache with the image's own (prebuilt sysroot).
if [ ! -e work/emcache/sysroot ]; then
  docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/work/emcache:/seed" "$IMAGE" \
    cp -a /emsdk/upstream/emscripten/cache/. /seed/
fi
run bash /repo/scripts/deps.sh
run bash /repo/scripts/openscad.sh

cat > dist/version.json <<JSON
{
  "openscad": "${OPENSCAD_TAG#openscad-}",
  "tag": "$OPENSCAD_TAG",
  "commit": "$OPENSCAD_COMMIT",
  "emscripten": "6.0.13",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
ls -l dist
