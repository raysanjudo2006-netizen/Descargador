// Implementación del puente con el C API de Python (ver PuentePython.h).
//
// Configuración según la guía oficial de Python para iOS: modo UTF-8, sin bytecode,
// stdio sin búfer y PYTHONHOME apuntando a la carpeta "python" de la app.

#include <Python/Python.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "PuentePython.h"

static int iniciado = 0;

/// Copia un texto con malloc (nunca devuelve NULL salvo que no haya memoria).
static char *duplicar(const char *texto) {
    return strdup(texto ? texto : "");
}

/// JSON de error escrito a mano, para cuando Python no puede ni generar uno.
static char *json_error_c(const char *mensaje) {
    const char *m = mensaje ? mensaje : "";
    size_t largo = strlen(m);
    // Cada carácter puede ocupar 2 al escaparlo; más el texto fijo.
    char *salida = malloc(largo * 2 + 96);
    if (!salida) return NULL;
    static const char inicio[] = "{\"ok\":false,\"error\":{\"codigo\":\"interno\",\"mensaje\":\"";
    static const char final[] = "\",\"detalle\":null}}";
    char *p = salida;
    memcpy(p, inicio, sizeof inicio - 1);
    p += sizeof inicio - 1;
    for (size_t i = 0; i < largo; i++) {
        unsigned char c = (unsigned char)m[i];
        if (c == '"' || c == '\\') { *p++ = '\\'; *p++ = (char)c; }
        else if (c < 0x20) { *p++ = ' '; }
        else { *p++ = (char)c; }
    }
    memcpy(p, final, sizeof final);  // incluye el '\0'
    return salida;
}

/// Convierte la excepción de Python pendiente en un JSON de error con su traceback.
/// Necesita el GIL. Siempre limpia la excepción.
static char *json_de_excepcion(const char *contexto) {
    char *resultado = NULL;
    PyObject *excepcion = PyErr_GetRaisedException();
    PyObject *modulo_traceback = PyImport_ImportModule("traceback");
    PyObject *modulo_json = PyImport_ImportModule("json");
    PyObject *lineas = NULL, *vacio = NULL, *detalle = NULL, *diccionario = NULL, *texto = NULL;

    if (modulo_traceback && excepcion) {
        lineas = PyObject_CallMethod(modulo_traceback, "format_exception", "O", excepcion);
    }
    vacio = PyUnicode_FromString("");
    if (lineas && vacio) {
        detalle = PyUnicode_Join(vacio, lineas);
    }
    diccionario = Py_BuildValue("{s:O,s:{s:s,s:s,s:O}}",
                                "ok", Py_False,
                                "error", "codigo", "interno", "mensaje", contexto,
                                "detalle", detalle ? detalle : Py_None);
    if (modulo_json && diccionario) {
        texto = PyObject_CallMethod(modulo_json, "dumps", "O", diccionario);
    }
    if (texto) {
        const char *c = PyUnicode_AsUTF8(texto);
        if (c) resultado = duplicar(c);
    }

    Py_XDECREF(texto);
    Py_XDECREF(diccionario);
    Py_XDECREF(detalle);
    Py_XDECREF(vacio);
    Py_XDECREF(lineas);
    Py_XDECREF(modulo_json);
    Py_XDECREF(modulo_traceback);
    Py_XDECREF(excepcion);
    PyErr_Clear();
    return resultado ? resultado : json_error_c(contexto);
}

static int fallo(PyStatus estado, const char *paso, char *error, size_t tam_error) {
    snprintf(error, tam_error, "%s: %s%s%s", paso,
             estado.func ? estado.func : "", estado.func ? ": " : "",
             estado.err_msg ? estado.err_msg : "error desconocido");
    return -1;
}

int dp_iniciar(const char *home, const char *rutas, char *error, size_t tam_error) {
    if (iniciado) return 0;
    PyStatus estado;

    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    estado = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(estado)) return fallo(estado, "Py_PreInitialize", error, tam_error);

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.buffered_stdio = 0;
    config.write_bytecode = 0;
    config.install_signal_handlers = 1;
    config.module_search_paths_set = 1;

    estado = PyConfig_SetBytesString(&config, &config.home, home);
    if (PyStatus_Exception(estado)) {
        PyConfig_Clear(&config);
        return fallo(estado, "PYTHONHOME", error, tam_error);
    }

    // sys.path: una ruta por línea.
    char *copia = duplicar(rutas);
    char *resto = NULL;
    for (char *ruta = strtok_r(copia, "\n", &resto); ruta; ruta = strtok_r(NULL, "\n", &resto)) {
        wchar_t *ancha = Py_DecodeLocale(ruta, NULL);
        if (!ancha) {
            snprintf(error, tam_error, "No se pudo leer la ruta %s", ruta);
            free(copia);
            PyConfig_Clear(&config);
            return -1;
        }
        estado = PyWideStringList_Append(&config.module_search_paths, ancha);
        PyMem_RawFree(ancha);
        if (PyStatus_Exception(estado)) {
            free(copia);
            PyConfig_Clear(&config);
            return fallo(estado, "sys.path", error, tam_error);
        }
    }
    free(copia);

    estado = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(estado)) return fallo(estado, "Py_InitializeFromConfig", error, tam_error);

    // Soltar el GIL: a partir de aquí cada hilo lo toma con PyGILState_Ensure.
    PyEval_SaveThread();
    iniciado = 1;
    return 0;
}

char *dp_llamar(const char *funcion, const char *peticion_json, dp_callback callback, void *contexto) {
    if (!iniciado) return json_error_c("Python no está inicializado");

    PyGILState_STATE gil = PyGILState_Ensure();
    char *resultado = NULL;

    PyObject *modulo = PyImport_ImportModule("descargador.puente");
    PyObject *funcion_py = modulo ? PyObject_GetAttrString(modulo, funcion) : NULL;
    PyObject *respuesta = funcion_py
        ? PyObject_CallFunction(funcion_py, "sKK", peticion_json,
                                (unsigned long long)(uintptr_t)callback,
                                (unsigned long long)(uintptr_t)contexto)
        : NULL;

    if (respuesta && PyUnicode_Check(respuesta)) {
        const char *c = PyUnicode_AsUTF8(respuesta);
        if (c) resultado = duplicar(c);
    }
    if (!resultado) {
        if (PyErr_Occurred()) {
            char mensaje[256];
            snprintf(mensaje, sizeof mensaje, "Fallo al llamar a descargador.puente.%s", funcion);
            resultado = json_de_excepcion(mensaje);
        } else {
            resultado = json_error_c("Python no devolvió texto");
        }
    }

    Py_XDECREF(respuesta);
    Py_XDECREF(funcion_py);
    Py_XDECREF(modulo);
    PyGILState_Release(gil);
    return resultado;
}

void dp_liberar(char *texto) {
    free(texto);
}

unsigned long long dp_direccion_evaluador(dp_evaluador_js evaluador) {
    return (unsigned long long)(uintptr_t)evaluador;
}
