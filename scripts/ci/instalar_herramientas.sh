#!/usr/bin/env bash
# Instala lo que necesita la compilación en el runner macOS de GitHub Actions:
#   - XcodeGen (versión fijada, desde su release oficial de GitHub)
#   - xcbeautify (logs de xcodebuild legibles y anotaciones de error en GitHub)
#   - Selecciona la versión de Xcode pedida en XCODE_VERSION, si existe.
set -euo pipefail

XCODEGEN_VERSION="${XCODEGEN_VERSION:-2.46.0}"

echo "::group::XcodeGen ${XCODEGEN_VERSION}"
destino="${RUNNER_TEMP:-/tmp}/xcodegen-${XCODEGEN_VERSION}"
if [[ ! -x "$destino/xcodegen/bin/xcodegen" ]]; then
  curl -fsSL --retry 3 -o "$destino.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
  mkdir -p "$destino"
  unzip -q "$destino.zip" -d "$destino"
fi
# Disponible en los pasos siguientes del job.
echo "$destino/xcodegen/bin" >> "${GITHUB_PATH:-/dev/null}"
"$destino/xcodegen/bin/xcodegen" --version
echo "::endgroup::"

echo "::group::xcbeautify"
if ! command -v xcbeautify >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install xcbeautify \
    || echo "::warning::No se pudo instalar xcbeautify; los logs saldrán sin formato."
fi
command -v xcbeautify >/dev/null 2>&1 && xcbeautify --version || true
echo "::endgroup::"

echo "::group::Xcode"
if [[ -n "${XCODE_VERSION:-}" ]]; then
  if [[ -d "/Applications/Xcode_${XCODE_VERSION}.app" ]]; then
    sudo xcode-select -s "/Applications/Xcode_${XCODE_VERSION}.app"
  else
    echo "::warning::Xcode ${XCODE_VERSION} no está en este runner; se usa el predeterminado."
  fi
fi
xcodebuild -version
echo "::endgroup::"
