#!/usr/bin/env bash
# One command to build the engine from source:
#   build/build.sh [variant]        variant: release (default) or assertions
# Builds the toolchain image, then LibreOffice core inside it, and copies the web root to
# build/out/<variant>-<core commit>/. Rerunnable: the image layers and the core workdir are cached
# (Docker image + named volumes), so a rerun only redoes what changed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pins.env
set -a; . "$here/pins.env"; set +a
variant="${1:-release}"
# Growable memory by default: 256 MB at start, up to 2 GB (docs/DECISIONS.md #13). MAKE_VARS="" builds
# the fixed 1 GiB of LibreOffice's own setting.
export MAKE_VARS="${MAKE_VARS-EMSCRIPTEN_INITIAL_MEMORY=256MB EMSCRIPTEN_MAXIMUM_MEMORY=2GB}"
# The tag names the toolchain inputs, so an unchanged toolchain is never rebuilt (BuildKit's cache
# alone is not enough: Docker Desktop garbage-collects it).
toolchain_hash=$( (cat "$here/pins.env" "$here/Dockerfile" "$here"/patches/emscripten/* "$here"/patches/qtbase/* \
  2>/dev/null || true) | sha256sum | cut -c1-12)
image="mage-office-toolchain:$toolchain_hash"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 8)}"

log_dir="$here/logs"
mkdir -p "$log_dir"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

echo "== toolchain image $image"
start=$(date +%s)
docker image inspect "$image" >/dev/null 2>&1 && [ "${REBUILD_IMAGE:-}" != 1 ] && echo "(exists)" || docker build \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg EMSDK_REPO="$EMSDK_REPO" --build-arg EMSDK_REF="$EMSDK_REF" \
  --build-arg EMSCRIPTEN_VERSION="$EMSCRIPTEN_VERSION" \
  --build-arg QTBASE_REPO="$QTBASE_REPO" --build-arg QTBASE_COMMIT="$QTBASE_COMMIT" \
  -t "$image" "$here" 2>&1 | tee "$log_dir/image-$stamp.log"
echo "image: $(( $(date +%s) - start )) s"

[ "${IMAGE_ONLY:-}" = 1 ] && exit 0

out_host="$here/out"
mkdir -p "$out_host"
# MSYS would rewrite the container paths below into Windows paths.
export MSYS_NO_PATHCONV=1
docker run --rm \
  -e CORE_REPO -e CORE_COMMIT -e VARIANT="$variant" -e JOBS="$jobs" -e MAKE_VARS="${MAKE_VARS:-}" \
  -e BASE_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$image")" \
  -v mage-office-core:/work \
  -v mage-office-tarballs:/cache \
  -v "$here/patches:/src/patches-core:ro" \
  -v "$here/in-container.sh:/src/in-container.sh:ro" \
  -v "$here/autogen.input:/src/autogen.input:ro" \
  -v "$out_host:/out" \
  "$image" bash /src/in-container.sh 2>&1 | tee "$log_dir/core-$variant-$stamp.log"
