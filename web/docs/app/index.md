---
title: La aplicación
description: El armazón: el carril, la barra de sincronización, los atajos.
---

# La aplicación

Esta sección recorre Didacta pantalla por pantalla. Si es tu primera vez,
empieza por [los primeros diez minutos](../empezar/primeros-pasos.md).

## El carril

Cuatro destinos, en este orden:

| | | |
|---|---|---|
| :material-school: | **Asignaturas** | [lo que se está dando](asignaturas.md) |
| :material-library-books: | **Biblioteca** | [todo el material](biblioteca.md) |
| :material-translate: | **Traducción** | [lo que falta](traduccion.md) |
| :material-cog: | **Ajustes** | [cuenta, repositorios, LaTeX](ajustes.md) |

Asignaturas primero, y no la biblioteca: la biblioteca son dos mil unidades
ordenadas por materia, que es **cómo se busca material**; una asignatura es lo
que se está dando este cuatrimestre, que es **lo que se abre cada día**.

Y dos más que aparecen solo cuando hacen falta:

| | | |
|---|---|---|
| :material-compare-horizontal: | **Entre repos** | [con más de un repositorio abierto](entre-repos.md) |
| :material-hub: | **Servidor** | [con el servidor MCP encendido](mcp.md) |

Aparecen y desaparecen a propósito. Con un solo repositorio, «Entre repos» no
puede encontrar nada, y un apartado que siempre dice «todo cuadra» es un
apartado que se deja de abrir.

El carril lleva además **cuentas vivas**: cuántas unidades esperan traducción,
cuántos documentos hay. Un número en la navegación es la forma más barata de
contestar «¿hay algo esperándome?» sin abrir la pantalla.

## La barra de sincronización

Arriba, en todas las pantallas. Lleva la única información que tiene que estar
visible desde cualquier sitio: **cómo se está llegando al contenido y como
quién**.

- en qué repositorio estás trabajando, con su color;
- cuántos commits tienes sin enviar;
- cuántos hay en GitHub que todavía no tienes, con un botón de **Traerlos**;
- quién ha entrado.

Está en el armazón y no en Ajustes porque dónde va a parar lo que escribes no
debería ser nunca un misterio.

## Los atajos

=== "macOS"

    | Atajo | Qué hace |
    |---|---|
    | ++cmd+1++ / ++cmd+2++ / ++cmd+3++ | Asignaturas · Biblioteca · Traducción |
    | ++cmd+comma++ | Ajustes |
    | ++cmd+bracketleft++ / ++cmd+bracketright++ | Atrás y adelante |
    | ++cmd+shift+p++ | Traer los cambios de GitHub |
    | ++cmd+shift+u++ | Enviar los commits |
    | ++cmd+r++ | Volver a leer el disco |

=== "Windows y Linux"

    | Atajo | Qué hace |
    |---|---|
    | ++alt+left++ / ++alt+right++ | Atrás y adelante |

    El resto de las acciones están en los botones de cada pantalla. El menú de
    sistema con atajos es de macOS.

## Cada pantalla tiene una dirección

`/unit/content/analysis/normed/definition`,
`/courses/am-iii/2025-2026/tema-1`. Eso es un requisito y no un adorno:
«mándame el enlace de esa unidad» tiene que funcionar, el botón de atrás tiene
que significar algo y recargar tiene que dejarte donde estabas.

## Lo que la aplicación no hace

Dicho aquí porque es mejor saberlo antes que descubrirlo:

- **compilar en Windows.** El resto funciona; los PDF salen desde el terminal;
- **crear una unidad desde cero.** Se editan, se traducen, se reclasifican y
  se recomponen las que hay; para una nueva, `didacta new unit`;
- **resolver conflictos de git.** Un conflicto se dice y se ofrece recargar.
