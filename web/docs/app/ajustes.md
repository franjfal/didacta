---
title: Ajustes
description: La cuenta, los repositorios, LaTeX, la traducción y las actualizaciones.
---

# Ajustes

![La pantalla de ajustes](../img/app/ajustes.png)

## Tu cuenta de GitHub

Quién ha entrado, y los botones de salir o cambiar de cuenta.

El token vive en el **llavero del sistema** --Keychain, Credential Manager,
Secret Service-- y nunca en un fichero de configuración ni en un log. Salir lo
borra de ahí.

[:octicons-arrow-right-24: Cómo funciona el acceso](../empezar/primer-repositorio.md#1-entrar-en-github)

## Los repositorios

Los que están abiertos, cada uno con:

- **su carpeta** en el disco;
- **su color**, el que lo identifica en toda la aplicación;
- **cómo está respecto a GitHub**: cuántos commits por enviar, cuántos por
  traer, si hay cambios sin guardar;
- botones para traer, enviar y quitarlo de la lista.

Quitarlo de la lista **no borra la carpeta**. Es dejar de abrirlo.

Se añaden desde GitHub --Didacta lista los que alcanza tu cuenta-- o eligiendo
una carpeta que ya esté clonada.

**Dónde se clonan** se elige aquí. Por defecto, `~/Didacta`.

## Las preferencias que viajan

Algunas preferencias --qué asignaturas son favoritas, qué temas están
plegados-- son de la persona, no de la máquina, y se pueden guardar en uno de
tus repositorios para encontrarlas igual en el ordenador de casa.

Se **elige** cuál, y no se decide por ti, porque no hay ninguna elección
evidente: cada uno tiene los repositorios que tiene. Sin elegir ninguno, todo
sigue funcionando en esta máquina.

## Idiomas

Dos cosas distintas, en la misma tarjeta para que se distingan de un vistazo.

**Con los que trabajas.** De los que hay en el material, cuáles quieres que
Didacta te ofrezca: la barra de arriba, los menús de compilar, la ficha de una
asignatura. Es solo para ti, viaja con las preferencias de arriba y no cambia
ningún fichero. Un repositorio del departamento que mantiene cinco idiomas y
una persona que da clase en dos no tienen por qué estorbarse.

Un idioma apagado **sigue apareciendo donde algo ya lo declara** — en la ficha
de una asignatura que se da en él, en las pestañas de una unidad que ya tiene
ese fichero — porque si no, guardar se lo llevaría por delante.

**A los que traduce cada repositorio.** Esto sí es del material: está en su
`didacta.yaml`, se ve en el diff y lo lee todo el mundo. Marca lo que ese
repositorio mantiene de verdad; uno marcado de más convierte la lista de
traducciones pendientes --que es la lista de trabajo-- en ruido.

!!! warning "Un idioma en uso no se puede quitar"

    Si una asignatura se da en él, Didacta se niega y te dice cuáles. No es
    una formalidad: una asignatura declarada en un idioma que su repositorio
    ya no mantiene es un `course.yaml` que el motor rechaza, y entonces la
    asignatura **desaparece de la biblioteca**. Se quita antes de sus fichas.

Quitar un idioma no borra ningún `.tex`: dejan de pedirse. Volver a añadirlo
los recupera.

[:octicons-arrow-right-24: Las cuatro listas de idiomas](../conceptos/idiomas.md#que-idiomas-hay)

## Bloques

Las partes en que se divide una asignatura: la teoría, los problemas, las
prácticas de ordenador. **Cada lección dice a cuál pertenece**, con `block:`
en su `unit.yaml`.

Eran dos y estaban escritas en el código, así que no se podían ni renombrar ni
añadir. Ahora se declaran en el `taxonomy.yaml` de cada repositorio, con un
**id** --lo que guarda la lección-- y un **nombre por idioma** --lo que se
lee--. Renombrar un bloque es cambiar una línea: no se mueve ningún fichero y
no se rompe ninguna referencia.

La tarjeta resume cuántos hay y cuánto lleva cada uno; el botón abre la
pantalla donde se tocan.

### Quién declara qué

Igual que un tema o una titulación: **la lección nombra el bloque y el bloque
lo declara quien lo tenga**. Con que un repositorio lo declare, todos lo ven
con su nombre.

Aquí es corriente declararlo en varios, a diferencia de los grados: la teoría
y los problemas están repartidos en dos repositorios y los dos necesitan los
dos bloques. Por eso cada bloque enseña en qué repositorios está declarado, y
se marca y se desmarca desde ahí. El precio de declararlo en dos es que pueden
acabar discrepando, y de eso avisa [Entre repositorios](entre-repos.md).

### Con qué se compila cada bloque

Cada bloque dice en qué plantillas se compila lo suyo, y es el botón de las
hojas de su fila. Eso es **lo que viene marcado** al compilar una lección o un
tema de ese bloque; el menú sigue ofreciendo todas las encendidas, porque el
mismo tema se quiere en libro un día y en diapositivas otro.

Un bloque que no elige compila en todas las encendidas. Vacío nunca quiere
decir «ninguna»: dejaría su material sin salidas y el botón de compilar no
haría nada sin decir por qué.

### Quitar uno

Pregunta antes qué pasa con sus lecciones, y no se puede saltar:

- **moverlas a otro bloque** — reescribe el `block:` de cada `unit.yaml`, en
  un solo commit por repositorio;
- **dejarlas sin bloque declarado** — se ven igual, con el bloque por su id, y
  salen en Entre repositorios para arreglarlas cuando toque.

Lo que no puede pasar es que noventa lecciones se queden clasificadas en
ninguna parte sin que nadie lo haya decidido.

!!! info "No romperle el material a nadie"

    Un bloque que no declara ningún repositorio abierto **no esconde nada**:
    sus lecciones salen en la biblioteca, se editan y se compilan igual. Lo
    único que cambia es que el bloque se enseña por su id. Quien no tenga el
    repositorio donde alguien puso el nombre sigue viendo todo su material.

## Plantillas

Una **plantilla** es una salida: qué PDF sale de una lección o de un tema. Trae
la clase de documento, sus opciones, los cinco ejes y --si quieres-- tu propia
cabecera de LaTeX.

Las quince que trae Didacta salen aquí desde el primer día. Se pueden apagar,
renombrar, duplicar y editar, y hay una cosa que conviene entender antes:

!!! warning "Editar una de serie la escribe en tu repositorio"

    Las quince viven en el programa y **no se tocan ahí**. Al editar una,
    Didacta la declara en el repositorio que elijas con su mismo id, y a partir
    de ese momento manda la tuya. La de serie se queda intacta, que es lo que
    mantiene vivo un `pdflatex master.tex` a mano en un editor.

    El formulario lo dice antes de guardar, y el identificador no se puede
    cambiar: es justamente lo que hace que sustituya a la otra.

### Apagar no es borrar

La casilla de cada plantilla decide si esa versión se compila. Apagarla la deja
declarada, **con su cabecera**, y fuera de todo lo que se saca: es lo que se
quiere de una versión que este curso no se da. Borrarla perdería justo lo que
había que guardar.

Es también la respuesta a tener quince salidas y usar cuatro.

### Dónde se guarda cada una

Al crear o duplicar una plantilla se elige dónde vive:

- **en un repositorio** --lo normal--: viaja con el material, la ve quien lo
  comparte y la protege el historial de git;
- **en el programa**: para lo que es tuyo y no de la asignatura --el membrete
  de tu departamento, tus colores-- o para cuando el material es de otra
  persona y no puedes escribir en él.

!!! danger "Lo que se guarda en el programa no lo protege nadie"

    No está en git, no se sincroniza y **se va con el ordenador**. Por eso los
    dos botones de al lado no son un lujo:

    - **Copiar a una carpeta** saca un `templates.yaml` y sus `.tex` donde
      digas. Es la copia de seguridad, y se puede meter tal cual en cualquier
      repositorio.
    - **Traer de una carpeta** los recupera. Lo que ya esté con el mismo
      nombre se conserva: recuperar una copia encima de lo que se ha escrito
      después es la forma más rápida de perder el trabajo de una tarde.

    Ajustes dice cuántas plantillas están ahí y en qué carpeta, para que el día
    que cambies de ordenador sepas qué llevarte.

### La cabecera

El botón **Cabecera** abre el LaTeX de esa plantilla. Se lee **al final del
preámbulo de Didacta**, así que puede redefinir lo que Didacta acaba de
definir: los márgenes, los colores, un entorno. No lleva `\documentclass` ni
`\begin{document}`; de eso se encarga la plantilla.

[:octicons-arrow-right-24: Qué es una plantilla, entero](../conceptos/perfiles.md#las-plantillas-tus-propias-salidas)

## Herramientas

Didacta no trabaja sola: pide prestado a cuatro programas.

| | Para qué | Sin ella |
|---|---|---|
| **Git** | traer el material de GitHub y guardar cada cambio | no hay nada que abrir |
| **Python 3** | ejecutar el motor | no hay PDF |
| **LaTeX** (`latexmk`) | componer las páginas | no hay PDF |
| **El motor de Didacta** | saber qué componer | no hay PDF |

De cada una la lista dice **si está, dónde y qué versión**. La ruta no es un
adorno: es lo que contesta «¿cuál de los dos gits está usando?», que es la
pregunta del día que algo va raro.

La que falte tiene un botón al lado, y lo que el botón pone es lo que va a
hacer --«Instalar con Homebrew», «Descargar MacTeX (~6 GB)»-- en lugar de un
«Instalar» a secas que se pone a bajar seis gigas por la conexión de casa.

!!! tip "Instalar no es terminar"

    Después de cada instalación Didacta **vuelve a buscar** la herramienta, y
    solo entonces la da por puesta. Si el instalador ha dejado el programa en
    una carpeta que no es ninguna de las de siempre, lo dice en lugar de poner
    un tick verde que miente.

    Y lo que termina fuera de Didacta --el instalador de Apple, el `.pkg` de
    macOS, el de MiKTeX-- se anuncia como tal: la fila queda esperando y hay
    un **Volver a comprobar** para cuando la otra ventana haya acabado.

### Cuando no se puede

Pasa, y más de lo que parece: hace falta la contraseña de administrador, no
hay gestor de paquetes, la máquina es del departamento. Entonces sale un
aviso con las tres cosas que permiten salir del paso:

- **qué se intentó** y **qué contestó** el programa, con un botón para copiar
  el detalle y pegarlo en una búsqueda o en una incidencia;
- **cómo hacerlo a mano**, con las órdenes de este sistema;
- **la guía oficial** de esa herramienta.

Y, abajo, la lista de **dónde ha mirado Didacta**. Si ya la tenías instalada,
esa lista es la única pista que sirve.

## Compilación

Las dos rutas que la lista de arriba comprueba, para cuando hay que decirlas a
mano:

**El motor** --el repositorio de Didacta, el que lleva `cli/didacta`. Hay un
botón para descargarlo si no lo tienes, y otro para señalar dónde está si lo
tienes en un sitio propio.

**La distribución de TeX.** Si no la encuentra, la pantalla dice **dónde ha
mirado**, que es lo que permite arreglarlo.

[:octicons-arrow-right-24: La distribución de TeX](../empezar/latex.md)

## Poner los ids a las lecciones { #poner-los-ids-a-las-lecciones }

Esta sección **solo aparece mientras haya algo que poner al día**, y desaparece
en cuanto se hace. Un ajuste que sirve una vez y se queda ahí para siempre es
ruido en una pantalla que se abre a diario.

Un repositorio escrito antes de que las lecciones tuvieran identidad propia las
identifica por su ruta. Con un id propio, mover una de carpeta deja de romper
quién la usa, y «este material, ¿dónde más está?» sigue teniendo respuesta
después de reorganizar `content/`.

Ponerlos escribe una línea `id:` en cada `unit.yaml` que no la tenga. **No
mueve nada, no renombra nada y no toca el contenido**, y queda como un commit
propio que se puede leer y revertir de una pieza.

El id se deriva de la ruta con un hash, así que sale el mismo lo haga quien lo
haga: quien ponga al día el mismo repositorio en otro ordenador escribe
exactamente esto, y el merge no tiene nada que resolver.

Desde el terminal es `didacta ids` para ver cuántas faltan y
`didacta ids --apply` para escribirlas.

[:octicons-arrow-right-24: Contenido vinculado](../conceptos/vinculos.md)

## Traducción

La clave del traductor automático, que vive en el llavero y no se vuelve a
enseñar, con su botón de probar.

[:octicons-arrow-right-24: Traducción automática](traduccion.md#traduccion-automatica)

## El servidor MCP

El interruptor, y en qué repositorios puede escribir.

[:octicons-arrow-right-24: El servidor MCP](mcp.md)

## Actualizaciones

Qué versión tienes, cuándo se miró por última vez y un botón para mirar ahora.

### Cómo funciona

Didacta mira **una vez por semana**, en segundo plano, después de que la
aplicación esté en pie. Ni al arrancar --retrasaría la primera pantalla por
una petición que a nadie le urge-- ni cada vez, que es cómo un aviso útil se
convierte en ruido que se cierra sin leer.

**Si no hay nada nuevo, no dice nada.**

Cuando la hay, aparece una franja arriba que se puede dejar para luego.
Cerrarla no es decir que no: la versión sigue estando y Ajustes la sigue
ofreciendo. Lo que no vuelve es la franja, hasta que se publique otra versión
distinta.

### Lo que pasa al actualizar

```
1. descargar, con progreso y cancelable
2. comprobar el SHA-256   ← si no cuadra, se borra y no se instala. Nunca.
3. comprobar el tamaño
4. extraer y comprobar que dentro hay una aplicación de verdad
5. comprobar la firma, si la versión instalada estaba firmada
6. escribir el script de sustitución
   ── hasta aquí, la instalación que funciona no se ha tocado ──
7. cerrar Didacta
8. el script sustituye, con copia de seguridad
9. relanzar
```

La versión anterior **se aparta, no se borra**, y solo desaparece cuando la
nueva está en su sitio y se ha comprobado que arranca. Si algo falla entre
medias, vuelve la de antes.

Y al arrancar, Didacta compara lo que se estaba instalando con lo que de
verdad está corriendo, y lo dice. Sin eso, una sustitución que falló y se
restauró sería indistinguible de una que salió.

### Cuando no se puede

Se dice **antes** de descargar nada:

- una Didacta en `/Aplicaciones` con una cuenta que no es administradora;
- un Linux donde Didacta no viene de un AppImage --manda el gestor de
  paquetes;
- sin conexión, o con GitHub caído.

Ninguno de esos casos impide usar Didacta. Buscar actualizaciones nunca puede
quitarte la aplicación.

[:octicons-arrow-right-24: Cómo se publica una versión](../proyecto/distribucion.md)
