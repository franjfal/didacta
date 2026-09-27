---
title: La aplicación
description: El armazón: el carril, la barra de sincronización, los atajos.
---

# La aplicación

Esta sección recorre Didacta pantalla por pantalla. Si es tu primera vez,
empieza por [los primeros diez minutos](../empezar/primeros-pasos.md).

![El armazón de Didacta: el carril, la barra de arriba y la pantalla](../img/app/biblioteca.png)

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

## Las palabras

La aplicación habla sin git: lo que git llama *commit* es un **cambio
guardado**; *confirmar* es **guardar en el historial**; el *clon* es **la
copia en tu ordenador**, y *traer* y *enviar* se quedan como están. Esta
documentación usa a veces los nombres de git porque es lo que se busca cuando
se quiere saber qué pasa por debajo, pero son lo mismo.

[:octicons-arrow-right-24: El glosario](../ayuda/glosario.md)

La barra de abajo lo resume en una frase: **Guardado en GitHub · al día**, o
lo que falte --«2 cambios sin enviar», «1 cambio nuevo en GitHub»--. Dónde
está la copia y como quién se escribe, al pasar el ratón por encima.

## Cuando algo falla

El aviso dice **qué ha pasado y qué hacer**, no lo que escribió git. Los casos
que de verdad pasan tienen su frase y, cuando lo hay, su botón:

| Lo que pasa | Lo que ofrece |
| --- | --- |
| Hay cambios nuevos en GitHub | **Traer**, y volver a intentarlo |
| GitHub no acepta tu sesión | **Volver a entrar** |
| No se llega a GitHub | nada que hacer: lo guardado está a salvo |
| Dos cambios chocan | volver a cargar el fichero |
| La carpeta está ocupada | esperar a que el otro programa acabe |
| GitHub rechaza el envío | mirar las reglas del repositorio |

Lo que dijo el programa está en **Detalles**, plegado, con **Copiar** y
**Contar el problema**, que abre una incidencia con la versión y el mensaje ya
escritos. El aviso no se va solo a los cuatro segundos.

[:octicons-arrow-right-24: Cuando algo falla, caso por caso](../ayuda/problemas.md)

## Los atajos

Los mismos en todos los sistemas, con ++cmd++ en macOS y ++ctrl++ en Windows y
Linux. La lista entera está siempre a mano con ++cmd+slash++ (++ctrl+slash++),
en Ajustes → Ayuda y, en el Mac, en el menú **Ayuda**.

| Atajo en macOS | En Windows y Linux | Qué hace |
|---|---|---|
| ++cmd+k++ | ++ctrl+k++ | La paleta de órdenes: ir a cualquier sitio o hacer algo, escribiendo |
| ++cmd+1++ / ++cmd+2++ / ++cmd+3++ | ++ctrl+1++ / ++ctrl+2++ / ++ctrl+3++ | Asignaturas · Biblioteca · Traducción |
| ++cmd+comma++ | ++ctrl+comma++ | Ajustes |
| ++cmd+bracketleft++ / ++cmd+bracketright++ | ++ctrl+bracketleft++ / ++ctrl+bracketright++, o ++alt+left++ / ++alt+right++ | Atrás y adelante |
| ++cmd+s++ | ++ctrl+s++ | Guardar lo que se está editando |
| ++cmd+f++ | ++ctrl+f++ | Buscar en la biblioteca |
| ++cmd+r++ | ++ctrl+r++ | Actualizar: el disco, el índice y GitHub |
| ++cmd+shift+p++ | ++ctrl+shift+p++ | Traer los cambios de GitHub |
| ++cmd+shift+u++ | ++ctrl+shift+u++ | Enviar los cambios guardados |
| ++cmd+slash++ | ++ctrl+slash++ | Ver los atajos |

En el Mac, el menú tiene además **Edición** (deshacer, copiar, pegar…),
**Ventana** y **Ayuda**, como cualquier otra aplicación.

### La paleta de órdenes

++cmd+k++ (++ctrl+k++), o **Ver → Ir a…** en el Mac, abre un buscador por
encima de la pantalla. Se escribe, se elige con las flechas y se va con
**Intro**:

- **una lección, un curso o un documento**, por su título --«banach»,
  «análisis 2025»--, sin tildes y con una errata como mucho;
- **una pantalla o una sección de Ajustes**: «ajustes snippets»;
- **una orden**: actualizar, traer o enviar, el tamaño del texto, la
  apariencia clara u oscura, la interfaz Esencial o Completa, el idioma del
  material que se mira;
- y, arriba del todo, **lo de la pantalla en la que estás**. En una lección:
  guardar, editar en otro idioma, compilar, los metadatos, el historial, darla
  en otro tema, duplicarla o moverla. En un curso: compilar lo desactualizado
  o todo, y crear un tema, un documento o un examen. En un documento:
  compilarlo y añadirle lecciones.

Sin escribir nada enseña lo de esta pantalla, lo que abriste hace poco y a
dónde ir. Cada orden que tiene atajo lo dice a la derecha, para aprenderlo.

![La paleta de órdenes buscando «espac»](../img/app/paleta.png)

### Sin ratón

Todo lo que se pulsa se alcanza con el **tabulador** y se pulsa con **Intro**
o **Espacio**: las filas de las listas, las tarjetas de la biblioteca, el
carril. Un borde verde dice dónde está el foco. Con un lector de pantalla, cada
fila se anuncia como botón con su texto, y el estado de cada idioma se dice con
palabras --«estado: sin revisar»--, no solo con su color.

## Cada pantalla tiene una dirección

`/unit/content/analysis/normed/definition`,
`/courses/am-iii/2025-2026/tema-1`. Eso es un requisito y no un adorno:
«mándame el enlace de esa unidad» tiene que funcionar, el botón de atrás tiene
que significar algo y recargar tiene que dejarte donde estabas.

## Lo que la aplicación no hace

Dicho aquí porque es mejor saberlo antes que descubrirlo:

- **resolver conflictos de git.** Un conflicto se dice y se ofrece recargar.
