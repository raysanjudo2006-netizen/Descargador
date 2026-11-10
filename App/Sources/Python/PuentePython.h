// Puente mínimo entre Swift y el intérprete de Python embebido.
//
// Swift solo ve estas funciones con tipos de C sencillos; todo el C API de Python
// queda dentro de PuentePython.c. Los datos viajan como texto JSON en UTF-8.

#ifndef PUENTE_PYTHON_H
#define PUENTE_PYTHON_H

#include <stddef.h>

/// Callback de eventos (registro y progreso) que Python llama desde su hilo.
/// Recibe un JSON y el contexto que pasó Swift. Devuelve 1 para pedir cancelar, 0 para seguir.
typedef int (*dp_callback)(const char *evento_json, void *contexto);

/// Inicializa Python una sola vez.
/// - home: carpeta "python" dentro de la app.
/// - rutas: carpetas de sys.path separadas por '\n'.
/// Devuelve 0 si todo va bien; si no, escribe el motivo en `error` y devuelve -1.
int dp_iniciar(const char *home, const char *rutas, char *error, size_t tam_error);

/// Llama a descargador.puente.<funcion>(peticion_json, callback, contexto) desde cualquier hilo.
/// Devuelve siempre un JSON reservado con malloc (nunca NULL); hay que liberarlo con dp_liberar.
char *dp_llamar(const char *funcion, const char *peticion_json, dp_callback callback, void *contexto);

/// Libera un texto devuelto por dp_llamar.
void dp_liberar(char *texto);

/// Python llama a esta función para entregar un texto (resultado o error) a quien lo pidió.
typedef void (*dp_respuesta)(const char *texto, void *contexto_respuesta);

/// Evaluador de JavaScript que Swift ofrece a Python (JavaScriptCore), para los desafíos de
/// YouTube. Ejecuta `script` y entrega por `responder` lo que imprimió con console.log
/// (devuelve 0) o el error (devuelve 1).
typedef int (*dp_evaluador_js)(const char *script, dp_respuesta responder, void *contexto_respuesta);

/// Dirección numérica de un evaluador, para pasársela a Python (ctypes la convierte en función).
unsigned long long dp_direccion_evaluador(dp_evaluador_js evaluador);

#endif
