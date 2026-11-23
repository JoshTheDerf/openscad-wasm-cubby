# Build environment: the official Emscripten SDK image plus the host tools
# OpenSCAD and its dependencies need at build time (lexer, parser generator,
# meson, ninja, autotools, gperf).
FROM emscripten/emsdk:6.0.13
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      flex bison ninja-build python3-pip pkg-config autoconf automake libtool \
      gperf m4 xz-utils ca-certificates curl python3-packaging gettext \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && pip3 install --no-cache-dir --break-system-packages meson==1.6.1
