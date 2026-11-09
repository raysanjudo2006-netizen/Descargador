#!/usr/bin/env bash
# Prepara Python para meterlo en la app (se ejecuta en el Mac de GitHub Actions):
#   1. Descarga Python-Apple-support de BeeWare (Python.xcframework) y comprueba su sha256.
#   2. Instala yt-dlp y sus dependencias (solo Python puro) en App/python/app_packages.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ"

SOPORTE_TAG="3.14-b14"
SOPORTE_ARCHIVO="Python-3.14-iOS-support.b14.tar.gz"
SOPORTE_SHA256="703ff822529f46edcbcd8b88096b2544f6990f3109ad38b4b4b61bb489a7c1ee"
TMP="${RUNNER_TEMP:-/tmp}"

echo "::group::Python-Apple-support $SOPORTE_TAG"
if [[ ! -d Python.xcframework ]]; then
  curl -fsSL --retry 3 -o "$TMP/$SOPORTE_ARCHIVO" \
    "https://github.com/beeware/Python-Apple-support/releases/download/$SOPORTE_TAG/$SOPORTE_ARCHIVO"
  echo "$SOPORTE_SHA256  $TMP/$SOPORTE_ARCHIVO" | shasum -a 256 -c -
  mkdir -p "$TMP/python-support"
  tar -xzf "$TMP/$SOPORTE_ARCHIVO" -C "$TMP/python-support"
  mv "$TMP/python-support/Python.xcframework" .
fi
ls Python.xcframework
echo "::endgroup::"

echo "::group::yt-dlp y dependencias (python/requisitos-ios.txt)"
rm -rf App/python/app_packages
# Solo wheels "py3-none-any": funcionan igual en iOS que en el Mac que compila.
python3 -m pip install --quiet --disable-pip-version-check \
  --no-deps --no-compile --only-binary=:all: \
  --platform any --python-version 3.14 --implementation py --abi none \
  --target App/python/app_packages -r python/requisitos-ios.txt
# El ejecutable "yt-dlp" y la documentación no hacen falta dentro de la app.
rm -rf App/python/app_packages/bin App/python/app_packages/share
ls App/python/app_packages
echo "::endgroup::"

{
  echo "### 🐍 Python para iOS preparado"
  echo ""
  echo "- Python-Apple-support \`$SOPORTE_TAG\` (sha256 verificado)"
  grep -vE '^[[:space:]]*(#|$)' python/requisitos-ios.txt | sed 's/^/- /'
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
