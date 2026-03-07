#!/usr/bin/env bash

set -euo pipefail

APP_NAME="Pindrop"
SOURCE_APP="${1:-DerivedData/Build/Products/Release/${APP_NAME}.app}"
DEST_APP="${PINDROP_DEV_APP_PATH:-$HOME/Applications/${APP_NAME} Dev.app}"
DEFAULT_SIGN_IDENTITY="Pindrop Local Dev"
SIGN_IDENTITY="${PINDROP_DEV_SIGN_IDENTITY:-}"

if [[ ! -d "${SOURCE_APP}" ]]; then
    echo "❌ App bundle not found at ${SOURCE_APP}"
    exit 1
fi

mkdir -p "$(dirname "${DEST_APP}")"
rm -rf "${DEST_APP}"
ditto "${SOURCE_APP}" "${DEST_APP}"

if [[ -z "${SIGN_IDENTITY}" ]] && security find-identity -v -p codesigning | grep -F "\"${DEFAULT_SIGN_IDENTITY}\"" >/dev/null; then
    SIGN_IDENTITY="${DEFAULT_SIGN_IDENTITY}"
fi

if [[ -n "${SIGN_IDENTITY}" ]]; then
    echo "✍️  Signing with persistent identity: ${SIGN_IDENTITY}"
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${DEST_APP}"
else
    echo "✍️  Signing ad hoc"
    codesign --force --deep --sign - "${DEST_APP}"
    cat <<'EOF'
⚠️  No PINDROP_DEV_SIGN_IDENTITY configured.
    Ad hoc signing changes the app's code requirement on each rebuild, so
    microphone and accessibility permissions may be requested again.
EOF
fi

open "${DEST_APP}"
echo "🚀 Installed and launched ${DEST_APP}"
