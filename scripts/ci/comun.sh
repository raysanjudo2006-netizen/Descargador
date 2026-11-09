#!/usr/bin/env bash
# Funciones compartidas por los scripts de CI. Se carga con:  source scripts/ci/comun.sh

# Pasa la salida de xcodebuild por xcbeautify (si está instalado) para que los errores
# aparezcan como anotaciones en GitHub y el log sea legible.
formatear() {
  if command -v xcbeautify >/dev/null 2>&1; then
    xcbeautify --renderer github-actions
  else
    cat
  fi
}

# Commit corto y número de build que se graban en la app.
COMMIT="$(git rev-parse --short=7 HEAD 2>/dev/null || echo local)"
NUM_BUILD="${GITHUB_RUN_NUMBER:-1}"
