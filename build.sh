#!/usr/bin/env bash
# Build a headless Ghidra image that actually decompiles on arm64.
#
# Two stages, because the release zip has no arm64 decompiler:
#   1. base image  - JDK + the official Ghidra release
#   2. natives     - build Ghidra's C++ decompiler from the matching source tag
#                    and layer it in at os/linux_arm_64/decompile
#
# Everything happens in containers; the host needs only docker and git.
#
#   ./build.sh                          # GHIDRA_VER=12.1.3 -> ghidra:arm64
#   GHIDRA_VER=12.2 ./build.sh          # a different release
#   SRC=/fast/disk/ghidra-src ./build.sh
#   IMAGE=registry.example/ghidra:test ./build.sh
set -euo pipefail

GHIDRA_VER="${GHIDRA_VER:-12.1.3}"
GHIDRA_TAG="${GHIDRA_TAG:-Ghidra_${GHIDRA_VER}_build}"
IMAGE="${IMAGE:-ghidra:arm64}"
SRC="${SRC:-${TMPDIR:-/tmp}/ghidra-src-${GHIDRA_VER}}"
HERE="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) echo "==> warning: host is $(uname -m). The decompiler is built for the host, so the" >&2
     echo "    resulting image will only run on $(uname -m), not on arm64." >&2 ;;
esac

echo "==> base image (JDK + Ghidra ${GHIDRA_VER})"
docker build --build-arg "GHIDRA_VER=${GHIDRA_VER}" -t "ghidra-headless:${GHIDRA_VER}" "$HERE"

echo "==> sparse-fetch decompiler source at ${GHIDRA_TAG} into ${SRC}"
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git init -q "$SRC"
  git -C "$SRC" remote add origin https://github.com/NationalSecurityAgency/ghidra.git
  git -C "$SRC" config core.sparseCheckout true
  echo "Ghidra/Features/Decompiler/src/decompile/" > "$SRC/.git/info/sparse-checkout"
fi
git -C "$SRC" fetch -q --depth 1 origin "$GHIDRA_TAG"
git -C "$SRC" checkout -q FETCH_HEAD

echo "==> build the native decompiler for this architecture"
# ARCH_TYPE= is the point: the Makefile only knows x86_64 (-m64) and otherwise
# falls through to -m32, which no arm64 compiler accepts. A command-line
# assignment overrides it even though it is set inside an ifeq.
docker run --rm -v "$SRC:/src" -w /src/Ghidra/Features/Decompiler/src/decompile/cpp debian:13 bash -c '
  apt-get update -qq >/dev/null
  apt-get install -y -qq --no-install-recommends g++ make bison flex zlib1g-dev >/dev/null 2>&1
  make ARCH_TYPE= -j"$(nproc)" ghidra_opt'
cp "$SRC/Ghidra/Features/Decompiler/src/decompile/cpp/ghidra_opt" "$HERE/decompile"

echo "==> final image ${IMAGE}"
docker build --build-arg "GHIDRA_VER=${GHIDRA_VER}" -t "$IMAGE" -f "$HERE/Dockerfile.natives" "$HERE"
echo "==> done: ${IMAGE}"
