---
title: El historial
description: Cómo estaba un fichero en cada versión, sin salir de la aplicación.
---

# El historial

El material vive en git, y git sabe contestar «¿cómo estaba esto en marzo?».
Hasta ahora esa respuesta estaba a un `git log` de distancia y aun así obligaba
a salir a un terminal --o a github.com-- con la ruta del fichero en la cabeza.

Una unidad se reescribe durante años. Saber qué se quitó en septiembre es tan
parte de editarla como el texto que tiene ahora.

![El historial de un fichero](../img/app/historial.png)

## La forma

Una lista de versiones a la izquierda y, a la derecha, **el fichero como
estaba en la que elijas**, con lo que ese commit añadió en verde y lo que
quitó en rojo.

Cuatro decisiones que conviene dejar dichas:

**Se enseña el fichero entero, no el recorte del cambio.** Un diff con tres
líneas de contexto contesta «¿qué tocó este commit?», que es la pregunta de
quien revisa un cambio ajeno. Editando, la pregunta es «¿cómo estaba esto en
marzo?», y ésa solo la contesta el texto completo. Las marcas de verde y rojo
van dentro, así que la primera pregunta también se sigue contestando.

**El commit se mira aparte.** Quién lo hizo, cuándo exactamente, con qué
mensaje y con qué hash están detrás de un botón y no delante del texto. En la
lista, el hash de cada versión solo sale con la interfaz completa (Ajustes →
Apariencia): a quien no usa git no le dice nada.

**Dentro de cada línea cambiada se marcan las palabras que cambiaron.** En un
párrafo de trescientos caracteres, un color más fuerte sobre «real» o sobre
`\keyterm{…}` ahorra leer las dos versiones enteras buscando la diferencia.

**Se puede copiar de una versión anterior.** Recuperar tres líneas que se
quitaron es seleccionarlas y copiarlas, no revertir un commit.

**Es del fichero, no del repositorio.** Lo que interesa es la historia de esta
unidad en este idioma, no todo lo que ha pasado alrededor.

## Comparar con ahora

En la barra de una versión antigua, **Comparar con ahora** cambia la pregunta:
en lugar de «¿qué cambió aquel día?», **«¿qué ha cambiado desde entonces?»**,
con lo de entonces en rojo y lo de ahora en verde. Es la que se hace antes de
una clase: qué ha tocado alguien en este tema desde el curso pasado.

## Recuperar una versión

**Recuperar esta versión** enseña primero qué cambiaría respecto a lo de
ahora, y si se confirma pone el texto de entonces en el editor **como un
cambio sin guardar**. No se toca nada hasta pulsar Guardar --que pide su
mensaje y enseña el diff, como siempre-- y **Descartar** lo deja como estaba.
No hay «revertir» que deshaga meses de trabajo de un clic.

## Dónde está

En la pestaña **historial** de cualquier unidad, y en la de un `year.yaml`
desde la pantalla del curso.

## Qué hace falta

Un clon local, que es lo normal en escritorio. El historial lo da git; no se
pide a GitHub, así que **funciona sin conexión**.
