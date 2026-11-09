#!/usr/bin/env bash
# Compila la app para iPhone SIN FIRMAR y la empaqueta como build/Descargador.ipa.
# SideStore/AltStore la firman con tu Apple ID al instalarla.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ"
mkdir -p build/logs
LOG=build/logs/xcodebuild-iphoneos.log
COMMIT="$(git rev-parse --short=7 HEAD 2>/dev/null || echo local)"
NUM_BUILD="${GITHUB_RUN_NUMBER:-1}"

formatear() {
  if command -v xcbeautify >/dev/null 2>&1; then
    xcbeautify --renderer github-actions
  else
    cat
  fi
}

echo "::group::xcodebuild (iphoneos, Release, sin firmar)"
set +e
xcodebuild \
  -project Descargador.xcodeproj \
  -scheme Descargador \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  GIT_COMMIT="$COMMIT" \
  CURRENT_PROJECT_VERSION="$NUM_BUILD" \
  build 2>&1 | tee "$LOG" | formatear
estado=${PIPESTATUS[0]}
set -e
echo "::endgroup::"

if [[ $estado -ne 0 ]]; then
  bash scripts/ci/resumen_errores.sh "$LOG" "Compilación para iPhone"
  exit "$estado"
fi

APP="build/DerivedData/Build/Products/Release-iphoneos/Descargador.app"
if [[ ! -d "$APP" ]]; then
  echo "::error::No se encontró $APP tras compilar"
  exit 1
fi

# Estructura de un .ipa: un zip con Payload/Descargador.app
rm -rf build/Payload build/Descargador.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry Descargador.ipa Payload)

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
TAM=$(du -h build/Descargador.ipa | cut -f1)
SHA=$(shasum -a 256 build/Descargador.ipa | cut -d' ' -f1)
{
  echo "### ✅ Descargador.ipa generado"
  echo ""
  echo "| Dato | Valor |"
  echo "|---|---|"
  echo "| Versión | $VERSION (build $NUM_BUILD) |"
  echo "| Commit | \`$COMMIT\` |"
  echo "| Tamaño | $TAM |"
  echo "| SHA-256 | \`$SHA\` |"
  echo ""
  echo "Descárgalo en **Artifacts**, al final de esta página."
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
echo "IPA: build/Descargador.ipa ($TAM)"
