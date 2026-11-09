#!/usr/bin/env bash
# Compila la app para el simulador de iPhone, ejecuta los tests (unitarios y de interfaz)
# y exporta las capturas de pantalla a build/capturas.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ"
source scripts/ci/comun.sh
mkdir -p build/logs
LOG=build/logs/xcodebuild-tests.log
RESULTADOS=build/Resultados.xcresult
rm -rf "$RESULTADOS"

echo "::group::Elegir y arrancar simulador"
UDID=$(xcrun simctl list devices available -j | python3 scripts/ci/elegir_simulador.py)
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
# Barra de estado limpia para las capturas.
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true
echo "::endgroup::"

echo "::group::xcodebuild test"
set +e
xcodebuild test \
  -project Descargador.xcodeproj \
  -scheme Descargador \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build/DerivedDataSim \
  -resultBundlePath "$RESULTADOS" \
  -parallel-testing-enabled NO \
  GIT_COMMIT="$COMMIT" \
  CURRENT_PROJECT_VERSION="$NUM_BUILD" \
  2>&1 | tee "$LOG" | formatear
estado=${PIPESTATUS[0]}
set -e
echo "::endgroup::"

echo "::group::Exportar capturas"
python3 scripts/ci/exportar_capturas.py "$RESULTADOS" build/capturas || true
NUM_CAPTURAS=$(find build/capturas -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
echo "::endgroup::"

if [[ $estado -ne 0 ]]; then
  bash scripts/ci/resumen_errores.sh "$LOG" "Tests en el simulador"
  exit "$estado"
fi

{
  echo "### ✅ Tests en el simulador superados"
  echo ""
  grep -E "Executed [0-9]+ tests?" "$LOG" | tail -n 1 || true
  echo ""
  echo "📸 ${NUM_CAPTURAS:-0} capturas en el artifact **capturas-simulador** (al final de esta página)."
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
