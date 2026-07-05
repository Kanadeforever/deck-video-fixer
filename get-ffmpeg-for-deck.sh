#!/usr/bin/env bash
# Download static FFmpeg/FFprobe binaries for Steam Deck/Linux x86_64
# and place them in ./bin so deck-video-fixer.sh can use them without touching SteamOS.
#
# Slow-region friendly measures, without extra dependencies:
# - reuses archives already placed in ./cache, including common names such as:
#     ffmpeg-static.tar.xz
#     ffmpeg-release-amd64-static.tar.xz
#     ffmpeg-master-latest-linux64-gpl.tar.xz
# - resumes interrupted downloads via ./cache/ffmpeg-static.tar.xz.part
# - retries transient network errors
# - supports curl or wget, whichever is already available
# - allows custom mirrors/CDN/proxy through environment variables

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
CACHE_DIR="$SCRIPT_DIR/cache"
TMP_DIR="$(mktemp -d)"
ARCH="$(uname -m)"

# Default sources: static Linux x86_64 FFmpeg archives containing ffmpeg and ffprobe.
# You can override them with:
#   FFMPEG_STATIC_URL="https://your.mirror/ffmpeg-master-latest-linux64-gpl.tar.xz" ./get-ffmpeg-for-deck.sh
# Or try several URLs, separated by spaces:
#   FFMPEG_STATIC_URLS="https://mirror/a.tar.xz https://mirror/b.tar.xz" ./get-ffmpeg-for-deck.sh
DEFAULT_URLS=(
  "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
  "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
)

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

msg() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

if [[ "$ARCH" != "x86_64" ]]; then
  err "This helper is for Steam Deck / x86_64 Linux only. Current arch: $ARCH"
  exit 1
fi

mkdir -p "$BIN_DIR" "$CACHE_DIR"
CANONICAL_ARCHIVE="$CACHE_DIR/ffmpeg-static.tar.xz"
ARCHIVE="$CANONICAL_ARCHIVE"
PARTIAL="$CACHE_DIR/ffmpeg-static.tar.xz.part"

if [[ -x "$BIN_DIR/ffmpeg" && -x "$BIN_DIR/ffprobe" ]]; then
  msg "Local FFmpeg already exists:"
  "$BIN_DIR/ffmpeg" -version | head -n 1 || true
  "$BIN_DIR/ffprobe" -version | head -n 1 || true
  msg
  msg "Nothing to download. To reinstall, delete ./bin/ffmpeg and ./bin/ffprobe first."
  exit 0
fi

# Build URL list. Space-separated on purpose, because URLs do not contain spaces.
URLS=()
if [[ -n "${FFMPEG_STATIC_URLS:-}" ]]; then
  # shellcheck disable=SC2206
  URLS=( ${FFMPEG_STATIC_URLS} )
elif [[ -n "${FFMPEG_STATIC_URL:-}" ]]; then
  URLS=( "$FFMPEG_STATIC_URL" )
else
  URLS=( "${DEFAULT_URLS[@]}" )
fi

show_network_hints() {
  cat <<'HINTS'
Network hints for slow regions:
  - Interrupted downloads will resume from ./cache/ffmpeg-static.tar.xz.part
  - To use a mirror/CDN URL:
      FFMPEG_STATIC_URL="https://example.com/ffmpeg-master-latest-linux64-gpl.tar.xz" ./get-ffmpeg-for-deck.sh
  - To use a proxy already available on your network:
      HTTPS_PROXY="http://127.0.0.1:7890" ./get-ffmpeg-for-deck.sh
  - If download is still painful, download the archive elsewhere and copy it to ./cache/.
    The script accepts common static-build names, including:
      cache/ffmpeg-static.tar.xz
      cache/ffmpeg-release-amd64-static.tar.xz
      cache/ffmpeg-master-latest-linux64-gpl.tar.xz
    It will also try other .tar.xz files in ./cache if they contain ffmpeg and ffprobe.

HINTS
}

archive_contains_binaries() {
  local file="$1"
  tar -tJf "$file" 2>/dev/null | awk '
    /(^|\/)ffmpeg$/ { has_ffmpeg=1 }
    /(^|\/)ffprobe$/ { has_ffprobe=1 }
    END { exit !(has_ffmpeg && has_ffprobe) }
  '
}

is_valid_archive() {
  local file="$1"
  [[ -s "$file" ]] || return 1
  archive_contains_binaries "$file"
}

find_cached_archive() {
  local candidate
  local -a preferred_names=(
    "ffmpeg-static.tar.xz"
    "ffmpeg-release-amd64-static.tar.xz"
    "ffmpeg-master-latest-linux64-gpl.tar.xz"
    "ffmpeg-master-latest-linux64-lgpl.tar.xz"
  )

  for name in "${preferred_names[@]}"; do
    candidate="$CACHE_DIR/$name"
    if [[ -f "$candidate" ]]; then
      msg "Found cached archive: $candidate"
      if is_valid_archive "$candidate"; then
        ARCHIVE="$candidate"
        msg "Cached archive looks valid and contains ffmpeg/ffprobe; reusing it."
        return 0
      fi
      msg "Cached archive is invalid or does not contain ffmpeg/ffprobe; moving it aside."
      mv -f "$candidate" "$candidate.bad.$(date +%s)"
    fi
  done

  # Accept common BtbN versioned names and any other manually copied .tar.xz archive
  # if it actually contains ffmpeg and ffprobe.
  while IFS= read -r -d '' candidate; do
    # Already handled preferred names above.
    case "$(basename "$candidate")" in
      ffmpeg-static.tar.xz|ffmpeg-release-amd64-static.tar.xz|ffmpeg-master-latest-linux64-gpl.tar.xz|ffmpeg-master-latest-linux64-lgpl.tar.xz)
        continue
        ;;
    esac
    msg "Found possible cached archive: $candidate"
    if is_valid_archive "$candidate"; then
      ARCHIVE="$candidate"
      msg "Cached archive looks valid and contains ffmpeg/ffprobe; reusing it."
      return 0
    fi
  done < <(find "$CACHE_DIR" -maxdepth 1 -type f -name '*.tar.xz' -print0 | sort -z)

  return 1
}

download_with_curl() {
  local url="$1"
  msg "Downloading with curl: $url"
  curl \
    --location \
    --fail \
    --continue-at - \
    --retry 8 \
    --retry-delay 3 \
    --retry-all-errors \
    --connect-timeout 20 \
    --speed-time 30 \
    --speed-limit 1024 \
    --progress-bar \
    --output "$PARTIAL" \
    "$url"
}

download_with_wget() {
  local url="$1"
  msg "Downloading with wget: $url"
  wget \
    --continue \
    --tries=8 \
    --timeout=30 \
    --read-timeout=30 \
    --output-document="$PARTIAL" \
    "$url"
}

download_archive() {
  if find_cached_archive; then
    return 0
  fi

  show_network_hints

  local url
  for url in "${URLS[@]}"; do
    ARCHIVE="$CANONICAL_ARCHIVE"
    msg "Trying source: $url"

    if command -v curl >/dev/null 2>&1; then
      if download_with_curl "$url"; then
        mv -f "$PARTIAL" "$ARCHIVE"
      else
        msg "curl failed for this source."
        continue
      fi
    elif command -v wget >/dev/null 2>&1; then
      if download_with_wget "$url"; then
        mv -f "$PARTIAL" "$ARCHIVE"
      else
        msg "wget failed for this source."
        continue
      fi
    else
      err "Neither curl nor wget was found."
      err "Download a Linux x86_64 static FFmpeg .tar.xz manually and place it in:"
      err "  $CACHE_DIR"
      err "For example:"
      err "  $CACHE_DIR/ffmpeg-master-latest-linux64-gpl.tar.xz"
      exit 1
    fi

    if is_valid_archive "$ARCHIVE"; then
      msg "Download complete and archive verified by tar."
      return 0
    fi

    msg "Downloaded file was not a valid FFmpeg .tar.xz archive. Keeping partial for resume/debug."
    mv -f "$ARCHIVE" "$PARTIAL"
  done

  err "All download sources failed."
  err "You can manually download a Linux x86_64 static FFmpeg archive containing ffmpeg/ffprobe, then copy it to:"
  err "  $CACHE_DIR/"
  err "Accepted examples:"
  err "  ffmpeg-static.tar.xz"
  err "  ffmpeg-release-amd64-static.tar.xz"
  err "  ffmpeg-master-latest-linux64-gpl.tar.xz"
  exit 1
}

extract_archive() {
  msg "Extracting from: $ARCHIVE"
  tar -xJf "$ARCHIVE" -C "$TMP_DIR"

  # Support both archive layouts:
  # - ffmpeg-*-amd64-static/ffmpeg and ffprobe
  # - ffmpeg-master-latest-linux64-gpl/bin/ffmpeg and bin/ffprobe
  # - */bin/ffmpeg and */bin/ffprobe
  local ffmpeg_path=""
  local ffprobe_path=""

  ffmpeg_path="$(find "$TMP_DIR" -type f -name ffmpeg -perm -u+x | head -n 1 || true)"
  ffprobe_path="$(find "$TMP_DIR" -type f -name ffprobe -perm -u+x | head -n 1 || true)"

  if [[ -z "$ffmpeg_path" || -z "$ffprobe_path" ]]; then
    # Some archives lose executable bit when repacked; search by name and chmod after copying.
    ffmpeg_path="$(find "$TMP_DIR" -type f -name ffmpeg | head -n 1 || true)"
    ffprobe_path="$(find "$TMP_DIR" -type f -name ffprobe | head -n 1 || true)"
  fi

  if [[ -z "$ffmpeg_path" || -z "$ffprobe_path" ]]; then
    err "Could not find ffmpeg/ffprobe in the archive."
    exit 1
  fi

  cp -f "$ffmpeg_path" "$BIN_DIR/ffmpeg"
  cp -f "$ffprobe_path" "$BIN_DIR/ffprobe"
  chmod +x "$BIN_DIR/ffmpeg" "$BIN_DIR/ffprobe"
}

download_archive
extract_archive

msg "Done. Installed:"
"$BIN_DIR/ffmpeg" -version | head -n 1
"$BIN_DIR/ffprobe" -version | head -n 1

msg
printf 'Now run:\n  %s/deck-video-fixer.sh\n' "$SCRIPT_DIR"
