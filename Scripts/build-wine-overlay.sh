#!/usr/bin/env bash
# Build OneClick's Wine runtime: upstream's published from-source runtime (WINE_BASE_* in versions.env) with
# the unix-side modules touched by Scripts/patches/wine rebuilt from the same CrossOver source and swapped in.
#
# Why an overlay and not a full rebuild: a full x86_64 build needs x86_64 gnutls/gstreamer, which came from an
# x86_64 Homebrew under Rosetta — and Homebrew no longer installs on anything but Apple Silicon. The patched
# files only need Apple's frameworks + FreeType, so they cross-compile natively (arm64 host → x86_64 target,
# no Rosetta for the toolchain, which current Command Line Tools no longer ship for x86_64 anyway).
#
# Inputs are pinned by SHA-256 in versions.env and the build fails closed on any mismatch.
#
# usage: Scripts/build-wine-overlay.sh [work-dir]      → dist/wine.tar.xz + dist/wine.tar.xz.sha256
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a; . "$ROOT/versions.env"; set +a
WORK="${1:-$ROOT/.wine-overlay-build}"
CACHE="$WORK/cache"
mkdir -p "$CACHE" "$ROOT/dist"

TAG="wine-cx-${CROSSOVER_VERSION}-${WINE_OVERLAY_SUFFIX}"
export SDKROOT="$(xcrun --sdk "macosx${WINE_OVERLAY_SDK_VERSION}" --show-sdk-path 2>/dev/null || true)"
[ -n "$SDKROOT" ] || { echo "ERROR: macOS ${WINE_OVERLAY_SDK_VERSION} SDK not installed" >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET="$WINE_OVERLAY_DEPLOYMENT_TARGET"
echo "==> $TAG  (SDK $SDKROOT, min macOS $MACOSX_DEPLOYMENT_TARGET)"

# fetch <url> <file> <sha256-or-empty>: download once into the cache, verify, fail closed.
fetch() {
  local url="$1" out="$CACHE/$2" want="$3"
  [ -f "$out" ] || curl -fL --retry 3 -o "$out.part" "$url" && { [ -f "$out" ] || mv "$out.part" "$out"; }
  local got; got="$(shasum -a 256 "$out" | awk '{print $1}')"
  if [ -z "$want" ]; then echo "    $2 sha256=$got (NOT PINNED — add it to versions.env)"
  elif [ "$got" != "$want" ]; then echo "ERROR: $2 sha256 $got != pinned $want" >&2; rm -f "$out"; exit 1
  else echo "    $2 verified"; fi
}

echo "==> Fetch pinned inputs"
fetch "https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CROSSOVER_VERSION}.tar.gz" \
      "crossover-sources-${CROSSOVER_VERSION}.tar.gz" "$CROSSOVER_SOURCES_SHA256"
fetch "https://github.com/${WINE_BASE_REPO}/releases/download/${WINE_BASE_TAG}/wine.tar.xz" \
      "base-${WINE_BASE_TAG}.tar.xz" "$WINE_BASE_SHA256"
fetch "https://github.com/mstorsjo/llvm-mingw/releases/download/${WINE_LLVM_MINGW_VERSION}/llvm-mingw-${WINE_LLVM_MINGW_VERSION}-ucrt-macos-universal.tar.xz" \
      "llvm-mingw-${WINE_LLVM_MINGW_VERSION}.tar.xz" "$WINE_LLVM_MINGW_SHA256"
fetch "https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.xz" "bison-${BISON_VERSION}.tar.xz" "$BISON_SHA256"
fetch "https://downloads.sourceforge.net/project/freetype/freetype2/${FREETYPE_VERSION}/freetype-${FREETYPE_VERSION}.tar.xz" \
      "freetype-${FREETYPE_VERSION}.tar.xz" "$FREETYPE_SHA256"

echo "==> Toolchain: llvm-mingw (PE cross compiler), bison (Wine needs >= 3)"
rm -rf "$WORK/llvm-mingw" "$WORK/tools" "$WORK/bison-src" && mkdir -p "$WORK/llvm-mingw" "$WORK/bison-src"
tar -xJf "$CACHE/llvm-mingw-${WINE_LLVM_MINGW_VERSION}.tar.xz" -C "$WORK/llvm-mingw" --strip-components=1
tar -xJf "$CACHE/bison-${BISON_VERSION}.tar.xz" -C "$WORK/bison-src" --strip-components=1
( cd "$WORK/bison-src" && ./configure --prefix="$WORK/tools" --disable-nls >/dev/null && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null )
export PATH="$WORK/tools/bin:$WORK/llvm-mingw/bin:$PATH"

echo "==> FreeType ${FREETYPE_VERSION} (x86_64; headers for win32u's font support — the runtime bundles its own dylib)"
rm -rf "$WORK/ft-src" "$WORK/freetype" && mkdir -p "$WORK/ft-src"
tar -xJf "$CACHE/freetype-${FREETYPE_VERSION}.tar.xz" -C "$WORK/ft-src" --strip-components=1
( cd "$WORK/ft-src" && ./configure --host=x86_64-apple-darwin --prefix="$WORK/freetype" CC="clang -arch x86_64" \
    CFLAGS="-O2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
    --with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no >/dev/null \
  && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null )

echo "==> Base runtime ${WINE_BASE_TAG}"
rm -rf "$WORK/runtime" && mkdir -p "$WORK/runtime"
tar -xJf "$CACHE/base-${WINE_BASE_TAG}.tar.xz" -C "$WORK/runtime"
# MoltenVK: link against the base's own bundled copy so Vulkan support is detected and the recorded soname
# (libMoltenVK.dylib) is exactly the base's.
mkdir -p "$WORK/mvk/lib" && cp "$WORK/runtime/lib/silo-bundled/libMoltenVK.dylib" "$WORK/mvk/lib/"

echo "==> CrossOver source + patches"
rm -rf "$WORK/src" && mkdir -p "$WORK/src"
tar -xzf "$CACHE/crossover-sources-${CROSSOVER_VERSION}.tar.gz" -C "$WORK/src"
WINE_SRC="$(find "$WORK/src" -maxdepth 3 -type d -name wine | head -1)"
[ -n "$WINE_SRC" ] || { echo "ERROR: wine source dir not found in tarball" >&2; exit 1; }
"$ROOT/Scripts/apply-wine-patches.sh" "$WINE_SRC"

echo "==> Native (arm64) Wine build tools"
rm -rf "$WORK/build-tools" && mkdir -p "$WORK/build-tools"
( cd "$WORK/build-tools" && "$WINE_SRC/configure" --without-x --without-freetype --disable-tests \
    --without-gnutls --without-gstreamer --without-sdl >configure.log && make -j"$(sysctl -n hw.ncpu)" __tooldeps__ >tools.log )

echo "==> x86_64 cross build of the patched modules (upstream's flags: -fvisibility=default -O2)"
rm -rf "$WORK/build64" && mkdir -p "$WORK/build64"
cd "$WORK/build64"
"$WINE_SRC/configure" --host=x86_64-apple-darwin --with-wine-tools="$WORK/build-tools" \
  --enable-archs=i386,x86_64 --disable-tests --without-x --with-freetype \
  --without-gstreamer --without-gnutls --without-sdl \
  CC="clang -arch x86_64" OBJC="clang -arch x86_64" \
  CFLAGS="-fvisibility=default -O2" OBJCFLAGS="-fvisibility=default -O2" CROSSCFLAGS="-fvisibility=default -O2" \
  LDFLAGS="-L$WORK/mvk/lib" \
  FREETYPE_CFLAGS="-I$WORK/freetype/include/freetype2" FREETYPE_LIBS="-L$WORK/freetype/lib -lfreetype" >configure.log
grep -q 'define SONAME_LIBVULKAN "libMoltenVK.dylib"' include/config.h || { echo "ERROR: Vulkan/MoltenVK not detected" >&2; exit 1; }
grep -q 'define SONAME_LIBFREETYPE "libfreetype.6.dylib"' include/config.h || { echo "ERROR: FreeType not detected" >&2; exit 1; }

# path-in-build-tree : path-in-runtime
MODULES=(
  "server/wineserver:bin/wineserver"
  "dlls/ntdll/ntdll.so:lib/wine/x86_64-unix/ntdll.so"
  "dlls/win32u/win32u.so:lib/wine/x86_64-unix/win32u.so"
  "dlls/winemac.drv/winemac.so:lib/wine/x86_64-unix/winemac.so"
  "dlls/winecoreaudio.drv/winecoreaudio.so:lib/wine/x86_64-unix/winecoreaudio.so"
)
targets=(); for m in "${MODULES[@]}"; do targets+=("${m%%:*}"); done
make -j"$(sysctl -n hw.ncpu)" "${targets[@]}" >make.log

echo "==> Swap the rebuilt modules into the base runtime"
for m in "${MODULES[@]}"; do
  built="$WORK/build64/${m%%:*}"; dest="$WORK/runtime/${m##*:}"
  [ -f "$dest" ] || { echo "ERROR: base runtime has no ${m##*:}" >&2; exit 1; }
  # Never ship a module that lost a symbol the base exported (another module may resolve it).
  missing="$(comm -23 <(nm -gU "$dest" | awk '{print $3}' | sort) <(nm -gU "$built" | awk '{print $3}' | sort) | head -5)"
  [ -z "$missing" ] || { echo "ERROR: ${m##*:} lost exports: $missing" >&2; exit 1; }
  install -m 755 "$built" "$dest"
  echo "    ${m##*:}"
done

INFO="$WORK/runtime/share/oneclick/build-info.txt"
mkdir -p "$(dirname "$INFO")"
{
  echo "OneClick Wine runtime $TAG"
  echo "Base: ${WINE_BASE_REPO} ${WINE_BASE_TAG} (sha256 ${WINE_BASE_SHA256})"
  echo "Source: crossover-sources-${CROSSOVER_VERSION}.tar.gz (LGPL-2.1-or-later), https://media.codeweavers.com/pub/crossover/source/"
  echo "Patches (Scripts/patches/wine, LGPL-2.1-or-later):"
  for p in "$ROOT"/Scripts/patches/wine/*.patch; do echo "  $(basename "$p")  $(shasum -a 256 "$p" | awk '{print $1}')"; done
  echo "Rebuilt modules:"
  for m in "${MODULES[@]}"; do echo "  ${m##*:}  $(shasum -a 256 "$WORK/runtime/${m##*:}" | awk '{print $1}')"; done
  echo "Toolchain: $(xcrun clang --version | head -1) (unix side); llvm-mingw ${WINE_LLVM_MINGW_VERSION}; SDK ${WINE_OVERLAY_SDK_VERSION}"
} > "$INFO"
cp "$ROOT/Scripts/patches/wine/"*.patch "$(dirname "$INFO")/"   # ship the patches with the binaries (LGPL)

echo "==> Package"
( cd "$WORK/runtime" && tar -cJf "$ROOT/dist/wine.tar.xz" . )
( cd "$ROOT/dist" && shasum -a 256 wine.tar.xz | awk '{print $1}' > wine.tar.xz.sha256 )
echo "Built dist/wine.tar.xz ($(du -h "$ROOT/dist/wine.tar.xz" | awk '{print $1}')) sha256 $(cat "$ROOT/dist/wine.tar.xz.sha256")"
echo "Release tag: $TAG"
