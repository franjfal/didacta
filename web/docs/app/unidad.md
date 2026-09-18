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

### El icono de información

Arriba a la derecha, la **ⓘ**. Lleva lo mismo que el panel pero se puede
abrir con el panel cerrado --y el panel sólo existe a partir de mil píxeles de
ancho--, y añade lo que antes estaba a dos pantallas de distancia:

- **Se da en**: cada tema que la llama, con su asignatura y su año. Se pulsa y
  se va. Si no la llama nadie, lo dice: después de una migración eso es
  material que llegó y no se está dando.
- **Versiones congeladas**: las de las asignaturas donde se da. Son de un
  curso académico y no de un fichero, así que una lección que se da en cuatro
  asignaturas tiene cuatro juegos y salen con el nombre de cada una delante.
  Crear una sólo se ofrece cuando hay una sola y no hay duda de cuál se
  congela.
- **Darla en otro tema…**, para la misma lección también allí.
- **Gestionar vinculación…**, cuando se da en más de un sitio: separa unas
  ubicaciones del resto, de modo que unas sigan con la de siempre y las demás
  pasen a una copia con vida propia.

Mirando una versión congelada, en lugar de eso sale **Restaurar esta
lección…**, que la trae tal como estaba dejando un cambio pendiente.

## `unit.yaml`

![Los metadatos de una unidad](../img/app/unidad-yaml.png)

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

## En qué se compila esta lección

En el formulario, debajo de la clasificación. Lo normal es **no elegir**: sale
lo que diga su bloque, y cambiar el bloque las cambia todas de una vez.

Elegir aquí es apartar **esta**: una lección que no se quiere en diapositivas
porque no cabe, un ejemplo largo que solo tiene sentido en los apuntes. Se
guarda en su `unit.yaml`:

```yaml
templates: [notes]
```

Volver a «lo que toque» quita la línea, y la lección vuelve a seguir a su
bloque.

[:octicons-arrow-right-24: Las plantillas](../conceptos/perfiles.md#las-plantillas-tus-propias-salidas)

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

![El editor de un problema](../img/app/problema.png)

Una unidad de `problems/` tiene los cuatro campos --enunciado, pista,
resultado, solución y corrección-- y el editor los enseña como campos, no como
un `.tex` donde hay que acordarse de las órdenes.

[:octicons-arrow-right-24: Los cuatro niveles](../conceptos/problemas.md)
