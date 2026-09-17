---
title: Asignaturas y cursos
description: Crear, duplicar y borrar asignaturas, cursos académicos y documentos.
---

# Asignaturas y cursos

![La pantalla de asignaturas](../img/app/asignaturas.png)

Es la pantalla que se abre cada día. Tres niveles:

```
Asignatura            Análisis Matemático III
└── Curso académico   2025-2026, grupo A
    └── Documento     Tema 1 · Hoja 1 · Parcial
```

## La asignatura

`course.yaml` guarda lo que **no cambia de un año a otro**: el título en cada
idioma, el código, la titulación, la institución, a qué idiomas se traduce.

Las asignaturas se pueden marcar como favoritas, y las favoritas suben. En una
cuenta con diecisiete asignaturas y treinta cursos académicos, las tres que
estás dando este cuatrimestre tienen que estar arriba.

## El curso académico

`year.yaml` guarda **la selección y el orden de este año**: qué documentos hay,
qué unidades lleva cada uno y en qué orden, con sus apartados.

### Duplicar un año

El botón **Duplicar**, o desde el terminal:

```bash
didacta new year am-iii 2026-2027
```

Copia la estructura. **No copia contenido**, porque no hay contenido que
copiar: las unidades siguen siendo las mismas. Lo que corrijas este año lo
hereda el siguiente, y el PDF del año pasado sigue exactamente como se dio,
porque sigue en su commit.

### Borrar

Borrar dice **qué se lleva, contado**: «esta asignatura tiene dos años y
setenta y siete documentos» es lo que permite decidir; «¿seguro?» no lo es. El
recuento lo da el motor en seco, sin borrar nada.

Y dice qué **no** se lleva: las unidades no se tocan. Lo que se pierde es la
selección y el orden. Sin esa frase, borrar una asignatura parece borrar el
material, y nadie lo pulsaría.

## Los documentos

Un documento es un tema, una hoja de problemas, un guion de prácticas o un
examen. Se crea vacío --sin unidades-- porque elegirlas es el paso siguiente y
tiene su propia pantalla.

El identificador se deduce del título, y se puede cambiar a mano.

[:octicons-arrow-right-24: La composición](composicion.md)

## Las titulaciones

Un grado agrupa asignaturas, y se gestiona desde aquí y no desde Ajustes: es
una clasificación del material, como un tema, no una preferencia de la
persona.

**Quién declara qué importa.** Un grado lo declara un repositorio y las
asignaturas de cualquier otro lo nombran; con que uno lo declare, todos lo ven
agrupado. Declararlo en dos no rompe nada --se juntan por identificador-- pero
es lo que hace que luego discrepen, así que al crear uno se pregunta dónde.

Y nada de esto puede romper nada: un grado que no declara ningún repositorio
abierto no agrupa, y sus asignaturas salen sueltas.
