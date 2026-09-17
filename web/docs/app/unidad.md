---
title: La unidad y su editor
description: Editar en varios idiomas, ver dónde se usa y guardar como commit.
---

# La unidad

![Una unidad abierta con su editor](../img/app/unidad.png)

Tres cosas en la misma pantalla: **qué es** esta unidad, **dónde se usa**, y
**su editor**.

## Las pestañas

```
es   va   en  │  compilar   unit.yaml   historial  │  Diapositivas   Apuntes
```

**Un idioma por pestaña, y se carga al abrirla.** Una unidad tiene hasta tres
o cuatro versiones; pedirlas todas de entrada serían cuatro lecturas para una
pantalla donde normalmente se lee una. Cada pestaña lleva el color de su
estado de traducción, y un punto cuando tiene cambios sin guardar.

**Compilar va delante de los metadatos** porque es lo que se hace entre una
edición y la siguiente; `unit.yaml` se toca una vez cada varios meses. El
orden de una fila de pestañas es una afirmación sobre con qué frecuencia se
usa cada una.

**Después, un PDF por pestaña**, según se van compilando.

## El editor

Conoce LaTeX, no solo texto:

- **resaltado** de órdenes, entornos, fórmulas y comentarios, con la misma
  paleta que usan los PDF;
- una **barra de entornos** con los de Didacta --`definition`, `theorem`,
  `example`, `teaching`, los campos de un problema-- que los inserta
  alrededor de lo que haya seleccionado;
- **aviso de los caracteres reservados**: un `%` o un `&` sueltos en el texto
  son un error de compilación que se ve tres minutos después;
- **esquema del fichero**, para moverse dentro de una unidad larga.

### Ver dos idiomas a la vez

La vista lado a lado pone el original a la izquierda y la traducción a la
derecha.

!!! warning "Una pestaña de un idioma que no existe arranca vacía"

    Y marcada en rojo. Arrancaba con el original debajo --para que quien
    traduce tuviera el texto delante-- y el efecto era el contrario del
    buscado: abrir la pestaña de valenciano y ver castellano se lee como «ya
    está traducida», y un guardado distraído archiva el castellano como si
    fuera la traducción.

    El texto delante lo da la vista lado a lado, donde el original se ve y no
    se puede guardar por error.

## Dónde se usa

El panel de la derecha lista los documentos que componen esta unidad: la
asignatura, el año y el documento. Es la respuesta a «¿puedo cambiar esto?».

También están ahí los metadatos en limpio, los prerrequisitos --enlazados-- y
los avisos que el motor haya dejado sobre esta unidad, como una figura que no
encuentra.

## `unit.yaml`

Se edita con un formulario, no escribiendo YAML. Y por debajo hay algo que
conviene saber:

!!! abstract "Editar un campo no reescribe el fichero"

    Didacta cambia **la línea de ese campo** y no toca nada más. No es
    purismo: un `unit.yaml` que viene de una migración lleva dentro el fichero
    del que salió y un `TODO` en cada campo que el material antiguo no
    registraba, y eso es la lista de trabajo de dos mil unidades. Un round
    trip por un parser de YAML la borra entera, en silencio, en la primera
    edición.

    Cuando no reconoce la forma de algo, **se niega en lugar de adivinar**: lo
    dice y ofrece el editor de texto.

## Guardar es un commit

Al guardar, Didacta pide un mensaje y enseña el diff.

- el mensaje sugerido dice qué ha cambiado, y se puede sustituir;
- el autor sale de tu sesión de GitHub, o de la identidad de git de esta
  máquina;
- **un commit no necesita conexión**; enviarlo, sí. Se puede trabajar en un
  tren y enviar al llegar.

Si el fichero ha cambiado en GitHub desde que lo abriste, el guardado **falla
y lo dice**, con la opción de recargar. No se reintenta: reintentar es
sobrescribir a quien llegó antes.

## Un problema se edita distinto

Una unidad de `problems/` tiene los cuatro campos --enunciado, pista,
resultado, solución y corrección-- y el editor los enseña como campos, no como
un `.tex` donde hay que acordarse de las órdenes.

[:octicons-arrow-right-24: Los cuatro niveles](../conceptos/problemas.md)
