#!/usr/bin/env bash
# Runs inside the toolchain image (see build.sh). Fetches LibreOffice core at the pinned commit into
# the mage-office-core volume, applies build/patches/core/*.patch, configures once, builds, and
# copies the emscripten web root to /out/<variant>-<core>-<patches>/ with build-info.json.
set -euo pipefail
. /opt/emsdk/emsdk_env.sh >/dev/null 2>&1

core=/work/core
variant="${VARIANT:-release}"
jobs="${JOBS:-8}"
t0=$(date +%s)
phase() { echo; echo "== $(date -u +%H:%M:%S) $*"; }

case "$variant" in
  release)    assertions=0 ;;
  assertions) assertions=1 ;;
  *) echo "unknown variant $variant" >&2; exit 2 ;;
esac

phase "source $CORE_COMMIT"
if [ ! -d "$core/.git" ]; then
  git init -q "$core"
  git -C "$core" remote add origin "$CORE_REPO"
fi
if [ "$(git -C "$core" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$CORE_COMMIT" ]; then
  git -C "$core" fetch -q --depth 1 origin "$CORE_COMMIT"
  git -C "$core" checkout -q -f FETCH_HEAD
  rm -f /work/.patches-applied
fi

phase "patches"
patch_list=$(ls /src/patches-core/core/*.patch 2>/dev/null || true)
patch_hash=$(cat $patch_list /dev/null | sha256sum | cut -c1-12)
if [ "$(cat /work/.patches-applied 2>/dev/null || true)" != "$patch_hash" ]; then
  # Revert whatever an earlier patch set changed, then apply the new set. Files that come out with the
  # same content get their old timestamps back, so make recompiles only what really changed.
  keep=/work/.patch-mtimes
  rm -rf "$keep"; mkdir -p "$keep"
  for f in $(git -C "$core" diff --name-only); do mkdir -p "$keep/$(dirname "$f")"; cp -p "$core/$f" "$keep/$f"; done
  git -C "$core" diff --name-only | xargs -r git -C "$core" checkout -q --
  for p in $patch_list; do echo "apply $(basename "$p")"; git -C "$core" apply --whitespace=nowarn "$p"; done
  for f in $(git -C "$core" diff --name-only); do
    if [ -f "$keep/$f" ] && cmp -s "$keep/$f" "$core/$f"; then touch -r "$keep/$f" "$core/$f"; fi
  done
  echo "$patch_hash" > /work/.patches-applied
fi
git -C "$core" diff --stat | tail -1

phase "configure"
export QT5DIR=/opt/qt5
mkdir -p /cache/tarballs
config_hash=$(cat /src/autogen.input | sha256sum | cut -c1-12)
if [ "$(cat /work/.configured 2>/dev/null || true)" != "$config_hash" ] || [ ! -f "$core/config_host.mk" ]; then
  cp /src/autogen.input "$core/autogen.input"
  (cd "$core" && ./autogen.sh)
  echo "$config_hash" > /work/.configured
fi
t_conf=$(date +%s)

# Extra make variables for experiments (e.g. MAKE_VARS="EMSCRIPTEN_INITIAL_MEMORY=256MB
# EMSCRIPTEN_MAXIMUM_MEMORY=2GB"); they change only the final link and are part of the build id.
read -r -a make_vars <<< "${MAKE_VARS:-}"
link_key="$variant-$patch_hash-${MAKE_VARS:-}"
phase "build ($variant, ASSERTIONS=$assertions, ${MAKE_VARS:-default memory}, -j$jobs)"
# The final link is the only thing the variant changes: drop it when the link inputs differ from last time.
link_marker=/work/.linked-variant
if [ "$(cat "$link_marker" 2>/dev/null || true)" != "$link_key" ]; then
  rm -f "$core"/workdir/LinkTarget/Executable/soffice_bin* "$core"/instdir/program/soffice.* 2>/dev/null || true
fi
(cd "$core" && /usr/bin/time -v make build PARALLELISM="$jobs" EMSCRIPTEN_ASSERTIONS="$assertions" "${make_vars[@]}") 2> /work/time.txt || {
  tail -60 /work/time.txt; exit 1; }
echo "$link_key" > "$link_marker"
t_build=$(date +%s)
grep -E 'Maximum resident|Elapsed' /work/time.txt || true

phase "collect"
web="$core/workdir/installation/LibreOffice/emscripten"
id="$variant-${CORE_COMMIT:0:10}-$patch_hash"
[ -n "${MAKE_VARS:-}" ] && id="$id-$(printf '%s' "$MAKE_VARS" | sha256sum | cut -c1-6)"
dest="/out/$id"
rm -rf "$dest.tmp"; mkdir -p "$dest.tmp"
cp -a "$web"/. "$dest.tmp"/
{
  echo "{"
  echo "  \"id\": \"$id\","
  echo "  \"variant\": \"$variant\","
  echo "  \"coreCommit\": \"$CORE_COMMIT\","
  echo "  \"patchSetHash\": \"$patch_hash\","
  echo "  \"makeVars\": \"${MAKE_VARS:-}\","
  echo "  \"patches\": [$(for p in $patch_list; do printf '"%s",' "$(basename "$p")"; done | sed 's/,$//')],"
  echo "  \"emscripten\": \"$(emcc --version | head -1)\","
  echo "  \"imageId\": \"${BASE_IMAGE_ID:-}\","
  echo "  \"builtAtUTC\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"seconds\": {\"configure\": $((t_conf - t0)), \"build\": $((t_build - t_conf))},"
  echo "  \"maxRssKiB\": $(grep 'Maximum resident' /work/time.txt | awk '{print $NF}'),"
  echo "  \"diskKiB\": {\"core\": $(du -sk "$core" | cut -f1), \"tarballs\": $(du -sk /cache | cut -f1)},"
  echo "  \"files\": {"
  first=1
  for f in "$dest.tmp"/*; do
    [ $first = 1 ] || echo ","
    first=0
    printf '    "%s": {"bytes": %s, "sha256": "%s"}' "$(basename "$f")" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)"
  done
  echo
  echo "  }"
  echo "}"
} > "$dest.tmp/build-info.json"
rm -rf "$dest"; mv "$dest.tmp" "$dest"
cat "$dest/build-info.json"
phase "done in $(( $(date +%s) - t0 )) s -> $dest"
