#!/usr/bin/env bash
# Extrae los errores de un log de xcodebuild y los escribe en el resumen del job
# (pestaña "Summary" de la ejecución en GitHub Actions), para no tener que bucear en el log.
# Uso: resumen_errores.sh <log> [título]
set -uo pipefail

LOG="$1"
TITULO="${2:-xcodebuild}"
SALIDA="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
PREFIJO="${GITHUB_WORKSPACE:-$PWD}/"

errores=$(grep -E "(error:|fatal error:|\*\* (BUILD|TEST|ARCHIVE) FAILED \*\*|Testing failed:|The following build commands failed:|Test Case .* failed)" "$LOG" \
  | sed "s|${PREFIJO}||g" \
  | awk '!visto[$0]++' \
  | head -n 60)

{
  echo "### ❌ Falló: $TITULO"
  echo ""
  if [[ -n "$errores" ]]; then
    echo "Primeros errores del log (cópialos y pégamelos):"
    echo ""
    echo '```'
    echo "$errores"
    echo '```'
  else
    echo "No hay líneas con \`error:\`. Últimas 40 líneas del log:"
    echo ""
    echo '```'
    tail -n 40 "$LOG" | sed "s|${PREFIJO}||g"
    echo '```'
  fi
  echo ""
  echo "El log completo está en los artifacts de esta ejecución."
} >> "$SALIDA"

echo "---------------- Resumen de errores ----------------"
echo "${errores:-(sin líneas 'error:'; mira el final del log)}"
echo "----------------------------------------------------"
