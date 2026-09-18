---
title: La biblioteca
description: Explorar el material por materia, o buscarlo.
---

# La biblioteca

Todo el material de todos los repositorios abiertos, junto.

![La biblioteca en vista de árbol](../img/app/biblioteca.png)

## Dos vistas, dos preguntas

**Explorar** --lo que se ve al entrar-- es el árbol en columnas, tal como está
en el disco: `content/analysis/normed/definition`. Cada nivel dice cuánto
contiene y cuánto está traducido al idioma que estás mirando.

**Buscar** aparece en cuanto escribes, y aplana la lista. «hilbert» no es un
sitio del árbol: es todo lo que lo menciona, venga de donde venga.

![La biblioteca buscando](../img/app/biblioteca-buscar.png)

??? note "Por qué no una lista plana con filtros"

    Esta pantalla estaba así antes, y merece la pena decir en qué se
    equivocaba: enseñaba las 2147 unidades en una lista con un panel de
    facetas al lado. La lista funcionaba --virtualizada, ordenable,
    filtrable-- y aun así era lo peor que se podía hacer con estos datos,
    porque **tiraba a la basura la organización que el autor ya había hecho**.

    El material está en un árbol, y está en un árbol en el disco: dos áreas,
    51 categorías, 444 temas, con una mediana de tres unidades por tema. Eso
    son tres clics hasta cualquier unidad. La lista plana llegaba a la misma
    unidad pasando por delante de otras dos mil.

## Los filtros

- **por bloque** — la tira de arriba de la primera columna;
- **por idioma** — el que se está mirando manda en toda la aplicación, y
  decide qué títulos y qué estados se enseñan;
- **por estado de traducción** — qué falta, qué está viejo;
- **por tipo** — una explicación, un ejemplo, un ejercicio;
- **por etiqueta**;
- **por repositorio**, cuando hay varios abiertos.

El **bloque** es la parte de la asignatura a la que pertenece cada lección.
Eran dos y estaban escritas en el código --teoría y problemas--; ahora las
declara cada repositorio en su `taxonomy.yaml`, así que quien parta su
asignatura en teoría, problemas y prácticas de ordenador ve tres pestañas. Se
gestionan desde [Ajustes](ajustes.md#bloques).

La tira **no aparece con un solo bloque**: un filtro cuyo único valor es todo
lo que hay no contesta ninguna pregunta.

!!! info "Un bloque sin declarar también sale"

    Si una lección nombra un bloque que ningún repositorio abierto declara, el
    bloque sale igual, por su id. Esconderlo escondería sus lecciones, y un
    filtro desde el que no se llega a parte del material es peor que uno feo.
    [Entre repositorios](entre-repos.md) dice cuáles son y cómo arreglarlo.

Las categorías se ordenan **por tamaño y no alfabéticamente**: 51 categorías
en orden alfabético entierran las que se están dando.

## Lo que dice cada fila

El título en el idioma que estás mirando, y si esa unidad no lo tiene, el del
idioma de referencia **en cursiva y gris**. Eso es deliberado: un título
castellano en un listado valenciano, puesto igual que los demás, parece una
traducción que existe.

Al lado, el estado de cada idioma con su color, el mismo que usan el editor,
el carril y los PDF compilados.

## Ojear sin abrir

Si una unidad tiene un PDF ya compilado, se puede **ojear encima de la lista**
sin entrar.

La pregunta que resuelve es la de quien prepara una clase: de estas ocho
lecciones sobre sucesiones, ¿cuál era la que tenía el dibujo? Entrar en cada
una, mirar y volver son tres pasos por lección; verla encima de la lista es
uno.

Solo enseña lo que **ya está compilado**: compilar desde aquí escondería tres
segundos de espera detrás de un gesto que parece instantáneo, y para eso está
la pantalla de la unidad.
