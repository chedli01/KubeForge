#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
for program in curl sha256sum cygpath powershell.exe; do require "$program"; done

mkdir -p "$LOCAL_BIN"
if [[ -f "$LOCAL_BIN/helm.exe" ]] && \
   "$LOCAL_BIN/helm.exe" version --short | grep -Fq "$HELM_VERSION"; then
  log "Helm $HELM_VERSION is already installed in .tools/bin."
  exit 0
fi

log "Downloading Helm $HELM_VERSION for Windows amd64 into this project's .tools/bin..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ARCHIVE="$TMP_DIR/helm.zip"
curl --fail --location --show-error --silent \
  "https://get.helm.sh/helm-${HELM_VERSION}-windows-amd64.zip" -o "$ARCHIVE"

ACTUAL_SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$HELM_WINDOWS_SHA256" ]] || \
  fail "Helm checksum verification failed! Expected $HELM_WINDOWS_SHA256, got $ACTUAL_SHA"

# Windows has a built-in ZIP extractor (no need for a global package manager).
ARCHIVE_WIN="$(cygpath -w "$ARCHIVE")"
DEST_WIN="$(cygpath -w "$TMP_DIR/extracted")"
powershell.exe -NoProfile -NonInteractive -Command \
  "Expand-Archive -LiteralPath '$ARCHIVE_WIN' -DestinationPath '$DEST_WIN' -Force" >/dev/null

[[ -f "$TMP_DIR/extracted/windows-amd64/helm.exe" ]] || fail 'Helm binary is missing from the archive.'
cp "$TMP_DIR/extracted/windows-amd64/helm.exe" "$LOCAL_BIN/helm.exe"
"$LOCAL_BIN/helm.exe" version --short
log 'Helm is installed locally; bootstrap scripts put .tools/bin on PATH.'
