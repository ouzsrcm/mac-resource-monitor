#!/bin/bash
# Apple noterine bir dosya gönderir ve sonucun Accepted olmasını bekler.
# .app paketi verilirse geçici bir zip oluşturulur; bu zip dağıtılmaz.
# Gerekli ortam: NOTARY_KEY_P8_BASE64, NOTARY_KEY_ID, NOTARY_ISSUER_ID
# Kullanım: notarize.sh <dosya>
set -euo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "Kullanım: notarize.sh <dosya>" >&2
  exit 1
fi

TARGET=$1
if [[ ! -e "$TARGET" ]]; then
  echo "::error::Noterliğe gönderilecek dosya yok: $TARGET" >&2
  exit 1
fi

for var in NOTARY_KEY_P8_BASE64 NOTARY_KEY_ID NOTARY_ISSUER_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::$var tanımlı değil." >&2
    exit 1
  fi
done

umask 077
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
SAFE_NAME="$(basename "$TARGET" | tr -c 'A-Za-z0-9._-' '_')"
P8_PATH="$WORK/AuthKey-${SAFE_NAME}.p8"
SUBMIT_PATH="$TARGET"
NOTARY_ZIP=""
NOTARY_LOG="$WORK/notary-${SAFE_NAME}.txt"

cleanup() {
  rm -f "$P8_PATH"
  if [[ -n "$NOTARY_ZIP" ]]; then
    rm -f "$NOTARY_ZIP"
  fi
}
trap cleanup EXIT

printf '%s' "$NOTARY_KEY_P8_BASE64" | base64 --decode > "$P8_PATH"
if [[ ! -s "$P8_PATH" ]]; then
  echo "::error::Noterlik anahtarı çözülemedi (boş dosya)." >&2
  exit 1
fi

# Noterlik servisi .app dizinini doğrudan kabul etmez.
if [[ -d "$TARGET" ]]; then
  NOTARY_ZIP="$WORK/notarize-${SAFE_NAME}.zip"
  ditto -c -k --keepParent "$TARGET" "$NOTARY_ZIP"
  SUBMIT_PATH="$NOTARY_ZIP"
fi

SUBMIT_OK=0
if xcrun notarytool submit "$SUBMIT_PATH" \
  --key "$P8_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait \
  --timeout 30m \
  2>&1 | tee "$NOTARY_LOG"; then
  SUBMIT_OK=1
fi

ACCEPTED=0
if [[ -f "$NOTARY_LOG" ]] && grep -Eq '^[[:space:]]*status:[[:space:]]+Accepted[[:space:]]*$' "$NOTARY_LOG"; then
  ACCEPTED=1
fi

if [[ "$SUBMIT_OK" -ne 1 || "$ACCEPTED" -ne 1 ]]; then
  echo "::error::Notarization sonucu Accepted değil." >&2
  SUBMISSION_ID=""
  if [[ -f "$NOTARY_LOG" ]]; then
    SUBMISSION_ID="$(awk '/^[[:space:]]*id: / { print $2; exit }' "$NOTARY_LOG" || true)"
  fi
  if [[ -n "$SUBMISSION_ID" ]]; then
    xcrun notarytool log "$SUBMISSION_ID" \
      --key "$P8_PATH" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" \
      || echo "::warning::Notarization günlüğü alınamadı." >&2
  else
    echo "::error::Gönderim kimliği bulunamadı; Apple günlüğü alınamadı." >&2
  fi
  exit 1
fi
