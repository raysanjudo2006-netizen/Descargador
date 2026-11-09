#!/usr/bin/env bash
# Fase de compilación de Xcode "Instalar Python": mete en Descargador.app la biblioteca
# estándar de Python, yt-dlp y el código Python propio (App/python/app).
#
# Usa las funciones de Python.xcframework/build/utils.sh (BeeWare):
#   - install_stdlib: copia la biblioteca estándar a <app>/python/lib
#   - process_dylibs: convierte cada módulo binario (.so) en un framework, porque iOS solo
#     carga código firmado que esté dentro de Frameworks/.
#
# Sin "-u": utils.sh usa variables de Xcode que pueden no existir.
set -eo pipefail

XCFRAMEWORK="Python.xcframework"
if [[ ! -d "$PROJECT_DIR/$XCFRAMEWORK" ]]; then
  echo "error: Falta $XCFRAMEWORK. Ejecuta scripts/ci/preparar_python.sh antes de compilar."
  exit 1
fi
if [[ ! -d "$PROJECT_DIR/App/python/app_packages/yt_dlp" ]]; then
  echo "error: Falta yt-dlp en App/python/app_packages. Ejecuta scripts/ci/preparar_python.sh."
  exit 1
fi

# utils.sh firma cada framework con EXPANDED_CODE_SIGN_IDENTITY. En la compilación sin firmar
# está vacía: se usa firma ad hoc ("-"). SideStore/iloader vuelven a firmar al instalar.
if [[ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  export EXPANDED_CODE_SIGN_IDENTITY="-"
fi

# shellcheck disable=SC1090
source "$PROJECT_DIR/$XCFRAMEWORK/build/utils.sh"

install_stdlib "$XCFRAMEWORK"
PYTHON_VER=$(ls -1 "$CODESIGNING_FOLDER_PATH/python/lib" | grep -E '^python3\.[0-9]+$')
LIB="$CODESIGNING_FOLDER_PATH/python/lib/$PYTHON_VER"

# Quitar lo que la app no usa (unos 38 MB): tests de CPython, IDLE, Tk, pip…
rm -rf "$LIB"/{test,idlelib,tkinter,turtledemo,ensurepip,pydoc_data,__phello__}
find "$LIB/lib-dynload" \( -name '_test*.so' -o -name 'xx*.so' \) -delete

echo "Convirtiendo los módulos binarios de $PYTHON_VER en frameworks…"
process_dylibs "$XCFRAMEWORK" "python/lib/$PYTHON_VER/lib-dynload"

echo "Copiando el código Python de la app y sus paquetes…"
mkdir -p "$CODESIGNING_FOLDER_PATH/python/app" "$CODESIGNING_FOLDER_PATH/python/app_packages"
rsync -a --delete --exclude '__pycache__' "$PROJECT_DIR/App/python/app/" "$CODESIGNING_FOLDER_PATH/python/app/"
rsync -a --delete --exclude '__pycache__' "$PROJECT_DIR/App/python/app_packages/" "$CODESIGNING_FOLDER_PATH/python/app_packages/"
process_dylibs "$XCFRAMEWORK" python/app_packages

echo "Python instalado: $(du -sh "$CODESIGNING_FOLDER_PATH/python" | cut -f1)"
