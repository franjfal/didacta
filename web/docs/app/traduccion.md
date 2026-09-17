---
title: Traducción
description: La cola de lo que falta, ordenada por lo que más se usa.
---

# Traducción

![La pantalla de traducción](../img/app/traduccion.png)

Qué falta por traducir, **en el orden que merece la pena hacerlo**.

## El orden es la pantalla

Está ordenada por cuántos documentos usan cada unidad, y ése es el punto.

Una biblioteca de dos mil unidades tiene más huecos de los que nadie va a
cerrar nunca. Una lista alfabética de lo que falta no es una cola de trabajo:
es un reproche. Ordenada por reutilización sí lo es --traducir una unidad de la
que dependen seis cursos compra seis documentos-- y además dice cuándo parar:
cuando lo que queda no lo usa nadie.

## `outdated` va antes que `missing`

Una traducción cuyo original ha cambiado **dice algo que ya no es cierto**, y
compila sin quejarse. Una que falta, al menos, se nota.

Cada fila lleva a la unidad **abierta ya en el idioma que falta**: llevar a la
unidad y dejar que abra el idioma de siempre obligaría a buscar la pestaña,
que es justo el paso que sobra cuando se viene de una lista de lo que falta.

## Traducción automática

Didacta puede pedirle a un traductor automático el primer borrador de una
unidad, o de varias.

### Qué se protege antes de enviar

Todo lo que no es prosa. Las órdenes, los entornos, las fórmulas en línea y
desplazadas, las referencias y las etiquetas se sustituyen por marcas antes de
mandar el texto, y se devuelven a su sitio al recibirlo.

Sin eso, un traductor que se encuentre `\begin{definition}` lo traduce, y lo
que vuelve no compila. Con fórmulas es peor: lo que vuelve compila y dice otra
cosa.

### La clave de API

Se configura en **Ajustes → Traducción**, y vive en el **llavero del
sistema**.

Es configuración privada de esta máquina, no contenido: a qué idiomas se
traduce cada asignatura sí va en el repositorio y se comparte; una clave de
API no sale de aquí.

Después de guardarla **no se vuelve a enseñar**. Se dice que hay una y se
enseñan sus cuatro últimos caracteres, lo justo para reconocer cuál de las
tuyas pusiste; para cambiarla se escribe otra. Un campo que devuelve la clave
entera es una clave en la primera captura de pantalla que alguien comparta.

Hay un botón de **probar**, porque una credencial mal puesta no se nota hasta
que alguien manda cincuenta unidades a traducir y vuelven todas con un 401.

### Sigue habiendo que leerlo

Lo que sale de ahí es un borrador, y se guarda como cualquier otro cambio: con
un commit a tu nombre. Lo que firmas es tuyo.
