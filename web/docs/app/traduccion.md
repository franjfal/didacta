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

Cómo se sabe: al traducir con la máquina y al marcar una traducción como
revisada, Didacta guarda en `unit.yaml` la huella del original de ese momento
(`source_hash`). Si después el original cambia, la huella ya no coincide y la
traducción pasa a **desactualizada**. Re-sangrar el original no cuenta: la
huella no mira los espacios. Lo que se tradujo antes de que existiera esto no
tiene huella, y no se marca hasta que alguien lo revise una vez.

**Qué ha cambiado**, no solo que ha cambiado. Al abrir una desactualizada,
encima del texto sale **El original ha cambiado desde que se revisó esta
traducción**, con un botón que enseña la diferencia entre el original de
entonces y el de ahora: una coma o un teorema nuevo no se ponen al día igual.
El original de entonces se busca en el historial por su huella; si no la tiene
--lo traducido antes de que existiera-- o esa versión no llegó a guardarse, lo
dice, y queda compararlos lado a lado.

Cada fila lleva a la unidad **abierta ya en el idioma que falta**: llevar a la
unidad y dejar que abra el idioma de siempre obligaría a buscar la pestaña,
que es justo el paso que sobra cuando se viene de una lista de lo que falta.

## Traducción automática

Didacta puede pedirle a un traductor automático el primer borrador de una
unidad, o de varias.

### Qué se traduce

De salida, **lo que no tiene texto** y **en el idioma que estás mirando**. Los
demás idiomas que falten se ofrecen, sin marcar.

Lo que ya tiene texto --los borradores y las desactualizadas-- no se toca
salvo que marques **Rehacer también las que ya tienen texto**. Un borrador
puede estar ya corregido a mano, y una desactualizada es una traducción
revisada a la que le falta un cambio: pasarles la máquina por encima tira ese
trabajo, y la casilla lo dice.

### Cuánto se va a mandar, antes de pulsar

Debajo de lo que se va a traducir, el diálogo dice **cuántos caracteres se
mandarían** --que es lo que se paga-- y cuánto costaría a la tarifa del
proveedor elegido (20 $ el millón en Google, 10 $ en Azure). Es un orden de
magnitud, no una factura: no cuenta lo gratuito de cada mes ni los
descuentos. Lo que ya está en la memoria de traducción no se manda y no
cuenta, y un párrafo que se repite en varias lecciones de la tanda se cuenta
una vez, porque se pide una vez.

### La tanda

Mientras traduce, **Detener** para antes de la siguiente lección. Lo que ya se
ha traducido se guarda igual: está pagado, y tirarlo sería pagarlo dos veces.

Todo lo de una tanda se guarda como **un solo cambio por repositorio**, y lo
que aprendió la memoria en otro aparte. Antes eran dos por lección, y
doscientas lecciones dejaban cuatrocientos cambios que decían lo mismo en el
historial.

La memoria crece mientras se traduce: la definición que sale en treinta
lecciones se pide en la primera y sale de la memoria en las otras veintinueve.
Y **el título de la lección** se traduce también, si en ese idioma no tenía:
va al `unit.yaml` en el mismo cambio, para que el índice del PDF no salga con
el título en el idioma original.

### Qué se protege antes de enviar

Todo lo que no es prosa. Las órdenes, los entornos, las fórmulas en línea y
desplazadas, las referencias y las etiquetas se sustituyen por marcas antes de
mandar el texto, y se devuelven a su sitio al recibirlo.

Sin eso, un traductor que se encuentre `\begin{definition}` lo traduce, y lo
que vuelve no compila. Con fórmulas es peor: lo que vuelve compila y dice otra
cosa.

### El valenciano, con Apertium

Google y Azure no distinguen el valenciano del catalán central: lo que sale
dice «aquest» y «durada» donde el valenciano dice «este» y «duració», y el
diálogo lo avisa antes de traducir. **Apertium** sí lo distingue, es gratuito y
no pide clave. Se enciende en **Ajustes → Traducción automática → Traducir el
valenciano con Apertium**, apagado de salida porque el texto va a su servidor
público (o al tuyo, si pones otro).

Traduce menos pares que los otros dos --del castellano al valenciano, al
catalán, al gallego, al inglés, al francés, al italiano y al portugués, y
algunos más--. Si en la tanda hay un par que no tiene, el diálogo lo dice
antes de pulsar, y esas lecciones se quedan sin hacer en lugar de salir mal.

### El glosario

Los términos que una traducción tiene que respetar --«sucesión» es
«successió» y no «seqüència»; «norma» no se traduce-- se escriben en
**Ajustes → Traducción automática → Glosario**, en una tabla con un término por
fila y un idioma por columna. Se guarda en `translation/glossary.tsv` del
repositorio, que también se abre con una hoja de cálculo, y al traducir se
juntan los de todos los repositorios abiertos.

Al traducir con la máquina, un término que no ha salido como dice el glosario
se avisa en el resumen, para mirarlo. **No se cambia solo**: sustituir la
palabra deja una frase que nadie ha escrito y que puede no concordar --género,
número, un artículo delante--, y encima parece revisada.

### La memoria aprende de quien revisa

Al aprobar una traducción que has corregido, cada párrafo corregido va a la
memoria de traducción: la próxima vez que aparezca, en cualquier lección, sale
ya corregido y no se paga. Solo cuando las dos versiones tienen la misma forma
--los mismos párrafos, con las mismas fórmulas en el mismo orden--: emparejar a
ojo una traducción que añadió o quitó un párrafo enseñaría frases cambiadas de
sitio.

### La clave de API

Se configura en **Ajustes → Traducción automática**, y vive en el **llavero del
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

## Dos estados: sin revisar y revisada

Lo que traduce una máquina, o una persona sin que nadie lo haya leído, queda
**sin revisar**. Al leerlo y darlo por bueno se marca como
**revisada** desde el estado de la pestaña, encima del texto. Son las dos
preguntas que se hace quien traduce, y en la interfaz esencial son las dos que
se ofrecen.

Con la [interfaz completa](ajustes.md#interfaz) se ofrecen también
**traducida** --hecha y sin revisar, que es como llega el material migrado-- y
**original**, que son cosa de quien mantiene el repositorio. «Sin traducir» y
«desactualizada» no se eligen nunca: los calcula Didacta.
