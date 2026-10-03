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
Castellano   Valencià   English  │  compilar   metadatos   historial  │  Diapositivas   Apuntes
```

**Un idioma por pestaña, con su nombre, y se carga al abrirla.** El código
--`va`, que es como se llama el fichero `va.tex`-- sale al pasar por encima. Una unidad tiene hasta tres
o cuatro versiones; pedirlas todas de entrada serían cuatro lecturas para una
pantalla donde normalmente se lee una. Cada pestaña lleva el color de su
estado de traducción, y un punto cuando tiene cambios sin guardar.

**Compilar va delante de los metadatos** --el `unit.yaml`-- porque es lo que
se hace entre una edición y la siguiente; los metadatos se tocan una vez cada
varios meses. El
orden de una fila de pestañas es una afirmación sobre con qué frecuencia se
usa cada una.

**Después, un PDF por pestaña**, según se van compilando.

## El editor

Encima del texto, lo justo para corregir una errata: el estado de la versión,
**Descartar** y **Guardar**; y debajo, la barra de formato con los canales
(Diapositivas, Apuntes, Profesor, Alumno), negrita, cursiva, Matemáticas,
Símbolos y los snippets. Con la [interfaz completa](ajustes.md#interfaz) sale
también lo de quien mantiene el repositorio: la ruta del fichero, cuántos
caracteres tiene, la casilla **ordenar al guardar** de ese fichero, el
interruptor Campos / LaTeX en una lección que no es un problema, y en la barra
de formato monoespaciada, término, resaltado, **Pausa** y **Ordenar**.

Conoce LaTeX, no solo texto:

- **resaltado** de órdenes, entornos, fórmulas y comentarios, con la misma
  paleta que usan los PDF;
- el **selector de snippets**, que envuelve lo seleccionado en uno de los
  snippets del repositorio del fichero --los entornos de Didacta, como
  `definition`, `theorem`, los campos de un problema o `teaching`, y los que
  hayáis añadido en [Ajustes](ajustes.md#snippets)--. Se escribe para
  filtrar, se elige con ↑ y ↓ y se aplica con Intro. Arriba del todo ofrece
  **quitar** el snippet que rodea al cursor, que deja el contenido y borra
  solo el envoltorio;
- **completar al escribir**: `\didac` ofrece `\didactatitle`, `\bym` ofrece
  `\bymedium`, `\alp` ofrece `\alpha`, y `\begin{` enseña los entornos de
  Didacta y al elegir uno escribe también su `\end`. Se elige con ↑ y ↓, se
  acepta con Intro o Tab y se cierra con Esc. Lo que ofrece es la lista de lo
  que se usa en una lección --la de [Escribir](../escribir/index.md) y las
  paletas--, no las miles de órdenes de LaTeX: entre mil, las veinte que se
  usan no se encontrarían;
- las **paletas de matemáticas y de símbolos**, que escriben la orden de
  LaTeX (se busca «≤» y se escribe `\leq`). Pulsadas en mitad de un párrafo,
  la meten en `$…$` con el cursor dentro, para seguir escribiendo la fórmula:
  un `\alpha` suelto en el texto no compila;
- **aviso de los caracteres reservados**: un `%` o un `&` sueltos en el texto
  son un error de compilación que se ve tres minutos después;
- **esquema del fichero**, para moverse dentro de una unidad larga;
- **buscar en el texto** con ⌘F (Ctrl+F): una barra encima del texto que
  pinta todas las coincidencias, dice cuál es y cuántas hay («2 de 4») y salta
  a la siguiente con Intro o ⌘G, y a la anterior con Mayús. Sin mirar
  mayúsculas salvo que se pulse **Aa**; con **.\***, una expresión regular.
  Esc la cierra y deja seleccionada la que se estaba mirando. Si había algo
  seleccionado al abrirla, es lo que busca. Con la interfaz completa, detrás
  del botón de reemplazar, **Reemplazar** y **Todas**; con una expresión,
  `$1`, `$2`… ponen lo que capturó. Reemplazar todas es un solo cambio: se
  deshace de una vez.

### Lo que no va a compilar, antes de compilar

Debajo del texto, un panel **Esto no va a compilar** con lo que LaTeX va a
rechazar, cada cosa con su línea: se pulsa y el cursor va allí. Busca:

- una **llave** `{` que no se cierra, o una `}` que no abre nada;
- una **fórmula** que no se cierra: un `$`, `\(` o `\[` sin su pareja antes
  de que acabe el párrafo;
- un **entorno** que se abre y no se cierra, o que se cierra por fuera de
  otro;
- una **orden que en este idioma no existe**. Cada idioma carga su parte de
  LaTeX, y lo que define uno no lo tiene otro: `\lgem` es del catalán y en
  castellano no compila; `\og` es del francés. (`\sen`, `\tg` y las demás
  funciones del castellano sí existen en todos: Didacta las define en cada
  idioma, para que una traducción que copia las fórmulas compile.)

Sin nada que avisar, el panel no está. Y no impide guardar: un fichero a
medias se puede guardar igual.

Solo avisa de lo que sabe seguro. Una orden que no conoce no la señala: LaTeX
con sus paquetes define miles, y un aviso que salta con lo que sí compila
enseña a no leer los avisos. Pasado por las mil lecciones del material migrado,
avisa de una sola, que efectivamente no compilaba.

En un problema abierto por campos, pulsar un aviso pasa al LaTeX entero, que
es donde hay líneas.

Lo que depende de los **snippets** lo avisa la propia barra, con un botón
ámbar a la derecha que dice cuántos avisos hay y lleva a cada uno:

- un snippet **de otro repositorio**: el texto usa `\begin{resumen}`, que es
  un snippet propio del repositorio de al lado y no de este. En tu máquina
  compila, porque tienes los dos abiertos; en la de quien solo tiene este, no,
  porque la definición solo entra al compilar su repositorio;
- un snippet **sin sus argumentos**: uno que se declaró con `{Título}` detrás
  de `\begin{frame}` y aquí lo ha perdido. LaTeX no se queja: toma la primera
  palabra del texto por el título, y el PDF sale mal sin decir nada.

### Ver dos idiomas a la vez

La vista lado a lado pone la pestaña que estás mirando y, al lado, las demás.
Si lo que miras es una traducción, **el original es de solo lectura** --lo dice
su cabecera con un candado-- para que una corrección no caiga en él por error;
pulsar su cabecera lo deja editar. Y va **a la vez**: al desplazarte por la
traducción, el original se desplaza con ella, a la misma altura del texto.

### Revisar una traducción

Encima de una traducción sin revisar hay un botón **Aprobar y siguiente**. Guarda
lo que hayas corregido y la marca como revisada **en un solo cambio**, con la
huella del original de ese momento, y abre la siguiente sin revisar en el mismo
idioma, en el orden de la lista de [Traducción](traduccion.md). Revisar treinta
traducciones es leer treinta y pulsar treinta veces.

Si las fórmulas de la traducción no son las del original, el panel de avisos lo
dice con su línea: **«Una fórmula no coincide con el original»**. Es la única
parte del fichero que tiene que ser idéntica en los dos idiomas, y un error ahí
compila y dice otra cosa. No cuentan los espacios ni lo que va en `\text{…}`,
que sí se traduce.

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

**Si se da en más de un curso, lo dice encima del texto**, con el panel abierto
o cerrado: «Se da en 2 cursos (…): lo que guardes aquí cambia en todos». Es lo
que hace útil una lección compartida --una errata se corrige una vez-- y lo
que sorprende a quien entra a retocarla pensando solo en el curso de este año.
Al lado está **Separar una copia…**, para cuando lo que se quiere es cambiarla
solo en uno. Cuenta cursos y no documentos: la misma lección en el tema y en
el examen del mismo curso no avisa.

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
- **Duplicar…**, para empezar una lección nueva a partir de esta: el mismo
  esquema de problema con otros números, la misma explicación para otro
  público. Pide el título --tiene que ser otro, para distinguirlas en la
  biblioteca-- y la deja al lado de la original, con sus idiomas, sus figuras
  y sus metadatos y con un id propio. Desde ese momento son dos lecciones:
  corregir una no corrige la otra. Si lo que se quiere es la misma lección en
  dos sitios, es la entrada siguiente.
- **Mover o renombrar…**, para llevarla a otro subtema --se elige en las
  mismas columnas de la biblioteca-- o cambiar el nombre de su carpeta. Es la
  misma lección en otro sitio: su id y sus traducciones no cambian, y lo que
  la usa --los temas de los cursos, también los vinculados, y los
  prerrequisitos de otras lecciones-- la nombra por su id, así que no hay que
  tocar nada y nada se queda apuntando a la carpeta vieja. Con algo sin
  guardar en la lección no se ofrece: primero hay que guardarlo o
  descartarlo. [:octicons-arrow-right-24: Mover desde la biblioteca](biblioteca.md#mover)
- **Darla en otro tema…**, para la misma lección también allí.
- **Gestionar vinculación…**, cuando se da en más de un sitio: separa unas
  ubicaciones del resto, de modo que unas sigan con la de siempre y las demás
  pasen a una copia con vida propia.

Mirando una versión congelada, en lugar de eso sale **Restaurar esta
lección…**, que la trae tal como estaba dejando un cambio pendiente.

## `unit.yaml`

![Los metadatos de una unidad](../img/app/unidad-yaml.png)

Se edita con un formulario, no escribiendo YAML.

**El sitio** --categoría › tema › subtema-- no se escribe: se ve, y al lado
está **Mover…**, que lo cambia junto con la carpeta
([Mover una lección](biblioteca.md#mover)). Antes eran dos campos de texto, y
cambiar uno sin mover la carpeta dejaba la lección en un sitio en la
biblioteca y en otro en el disco.

**Las etiquetas y los prerrequisitos sugieren lo que ya existe** mientras se
escribe, con cuántas lecciones usan cada cosa; en los prerrequisitos se busca
por el título de la lección. Lo escrito que no existe va el primero de la
lista, marcado como nuevo --Intro lo deja tal cual--. Un prerrequisito que no
es ninguna lección también se dice.

Y por debajo hay algo que conviene saber:

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

Con el botón o con **⌘S** (**Ctrl+S** en Windows y Linux), que hace lo
mismo; también en los metadatos, en la composición de un documento, en la
lista de un curso y en el `.tex` de un documento.

**Se guarda sin preguntar**, con el mensaje que propone Didacta, que dice qué
ha cambiado y dónde: «Editar la versión es de "Espacios normados"». El aviso
que sale lo repite y ofrece **Ver cambios**, con las líneas que se quitaron y
las que se pusieron; y todo sigue en el [historial](historial.md). Quien
prefiera leer el diff y escribir el mensaje antes de cada guardado lo enciende
en Ajustes → Guardar y sincronizar → **Revisar los cambios antes de guardar**.

!!! note "Por qué no se pregunta de salida"

    Un diálogo que se acepta sin leer treinta veces al día no revisa nada:
    enseña a pulsar Intro. Para corregir una errata, el mensaje propuesto es
    tan bueno como el que se escribiría, y el diff sigue a un clic.

- el autor sale de tu sesión de GitHub, o de la identidad de git de esta
  máquina;
- **un commit no necesita conexión**; enviarlo, sí. Se puede trabajar en un
  tren y enviar al llegar.

Si el fichero ha cambiado en GitHub desde que lo abriste, el guardado **falla
y lo dice**, con la opción de recargar. No se reintenta: reintentar es
sobrescribir a quien llegó antes.

**Irse con algo sin guardar pregunta antes**: cambiar de lección o de
pantalla, o cerrar Didacta, con texto escrito y sin guardar enseña qué es y
ofrece **Seguir editando**, que viene marcado. Lo mismo en la composición de
un documento y en la lista de un curso.

Y si Didacta se cierra de golpe --un cuelgue, un corte de luz-- lo escrito no se
pierde: se va copiando mientras escribes a la carpeta de datos de la
aplicación, **fuera del repositorio**, y al volver a abrir ese fichero se
ofrece **Recuperarlo** o **Descartarlo**. Si el fichero ha cambiado desde
entonces, lo dice, para que se mire el diff antes de guardar.

## Un problema se edita distinto

![El editor de un problema](../img/app/problema.png)

Una unidad de `problems/` tiene los cuatro campos --enunciado, pista,
resultado, solución y corrección-- y el editor los enseña como campos, no como
un `.tex` donde hay que acordarse de las órdenes.

[:octicons-arrow-right-24: Los cuatro niveles](../conceptos/problemas.md)
