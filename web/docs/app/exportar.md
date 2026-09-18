---
title: Exportar un curso
description: Sacar los PDF de un año a una carpeta, para repartirlos.
---

# Exportar un curso

Lo que se lleva alguien al aula virtual o a un disco: los PDF ya compilados,
en carpetas con nombres que se leen.

**El repositorio no se toca.** Lo que sale es una copia.

```mermaid
flowchart LR
  R["Tu repositorio<br/>no se toca"] --> C["Los PDF ya compilados"]
  C --> E["Una carpeta<br/>por idioma y con<br/>nombres que se leen"]
  E --> A["El aula virtual"]
  E --> U["Un USB"]
```

## Desde dónde se pide

Tres sitios, según lo que haya que llevarse:

| Lo que sale | Dónde está el botón |
| --- | --- |
| **Un curso entero** | en su fila de la pantalla de asignaturas, al lado de la estrella |
| **Un documento** | en su fila del listado del curso, si tiene algo compilado |
| **El PDF que se está mirando** | en el visor, «Guardar una copia» |

El primero pregunta qué idiomas y qué documentos; los otros dos solo preguntan
dónde, que es lo único que queda por decidir.

**Exportar no pide permiso de escritura.** Copia lo que ya está compilado y no
toca el repositorio, así que también se lleva material quien solo lo tenga para
leer.

## Las tres decisiones

Están en la misma pantalla porque son la misma decisión:

1. **en qué idiomas**;
2. **qué temas**;
3. **qué documentos de cada tema**.

Todo viene marcado, que es lo que se quiere casi siempre, y desmarcar es más
rápido que buscar.

## Recompilar está apagado de salida

A propósito. Un curso entero son cuarenta salidas y media hora: quien acaba de
compilarlo no quiere repetirlo por exportar, y quien lo necesita lo marca.

**Lo que no esté compilado no se exporta, y se dice cuál falta.** En lugar de
salir un reparto al que le faltan tres PDF sin que nadie se entere.

## Cómo queda la carpeta

```
Análisis Matemático III 2025-2026/
├── es/
│   ├── Tema 1. Espacios normados - diapositivas.pdf
│   ├── Tema 1. Espacios normados - apuntes.pdf
│   └── Hoja 1 - problemas.pdf
└── va/
    └── …
```

Nombres largos y con espacios a propósito: esto no lo va a leer un programa,
lo va a leer alguien buscando un fichero en una lista del aula virtual.

El PDF que se guarda desde el visor sale con **ese mismo nombre**: es el que le
pone el motor, y es el que tendría si se hubiera exportado el curso entero.
