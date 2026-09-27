---
title: Compilar
description: Sacar los PDF, ver la consola y comparar versiones dentro de la ventana.
---

# Compilar

Didacta no reimplementa nada de LaTeX: llama a `cli/didacta`, que es el mismo
camino que se usa desde el terminal. Lo que aporta es elegir, lanzar y enseñar.

!!! note "En Windows hace falta Python"

    El motor está escrito en Python, que macOS y Linux traen y Windows no. Si
    falta, Didacta lo dice en Ajustes --y en el botón de compilar-- antes de
    que pulses nada. [Cómo instalarlo](../empezar/index.md#que-mas-hace-falta-en-la-maquina).

![Elegir qué versiones y en qué idiomas](../img/app/unidad-compilar.png)

## El botón

**Compilar** saca lo que corresponda a lo que estés mirando: una unidad suelta
en su perfil de vista previa, un documento en los perfiles que tenga
declarados.

Manteniéndolo pulsado se eligen **perfiles e idiomas**. Y hay una opción de
compilar en todos los idiomas a la vez, que es lo que hace falta antes de
subir un tema al aula virtual.

En la lista de un curso pasa lo mismo: el botón de cada tema, el de cada
documento y **Compilar el curso** sacan las versiones que declara cada
documento, no las siete que admite un tema de teoría. Manteniéndolo pulsado
está **Todas las versiones**, para cuando sí se quieren.

**Compilar un curso entero pregunta antes**, con cuántos documentos son: es
media hora con el ordenador ocupado, y con un clic y sin avisar se lanzaba
cuando se quería mirar un tema. Un tema o un documento suelto no preguntan.

## Lo que no ha cambiado no se recompila

Compilar otra vez un documento en el que no ha cambiado nada --ni una
lección, ni una figura, ni la plantilla-- es **inmediato**: se ve que todo
sigue igual y se deja el PDF que había. Y lo que sí ha cambiado tarda menos,
porque las pasadas que LaTeX ya había hecho se aprovechan. En el repositorio
de ejemplo, un tema en dos versiones son unos diez segundos la primera vez,
menos de medio segundo si nada ha cambiado y la mitad si se ha tocado una
lección; en un curso entero, recompilar después de corregir dos erratas es
compilar dos documentos, no cuarenta.

**Las versiones de un documento se compilan a la vez**, cada una en su
carpeta: las seis de un tema --tres versiones en dos idiomas-- tardan lo que
tardan dos o tres. Cuántas a la vez se elige en
[Ajustes → Herramientas](ajustes.md#compilacion); en la consola, cada línea
dice de cuál es: `[slides · es]`.

## Vista rápida { #vista-rapida }

Para ver cómo queda un cambio sin esperar a la compilación entera. Se
enciende en *Ajustes → Herramientas → Vista rápida*, y entonces el botón de
la pantalla de un documento dice **Vista rápida** y compila **en una sola
pasada**: en un tema del material de Análisis, después de añadir una
diapositiva, treinta segundos en lugar de cincuenta y cuatro. A cambio, el
índice, las referencias cruzadas y el total de diapositivas pueden no estar al
día --salen de la compilación anterior--. El panel del PDF lo dice:
**«vista rápida · 3 / 16»**.

Al lado queda **Compilar entero**, para lo que se reparte. Y lo que sale de
una sola pasada cuenta como **desactualizado**, así que *Compilar lo
desactualizado* lo rehace entero. Compilar un tema o un curso desde la lista
del curso es siempre entero. En una lección suelta no cambia nada: entera
tarda lo mismo.

## Una detrás de otra, y se puede parar

Lo que se compila **va a una cola**: si se pulsa compilar mientras otra cosa
compila, espera su turno. Dos a la vez se pisaban la consola --que es una-- y,
si eran del mismo documento, la carpeta de salida.

Mientras dura, **abajo, en todas las pantallas**, una tira dice qué se está
compilando, por cuál va en un lote --«Compilando Análisis · 2025-2026 ·
9/38»-- y cuántas esperan detrás, con **Ver**, que abre la consola, y
**Detener**. Detener para lo que se compila --LaTeX incluido, con todo lo que
haya lanzado-- y vacía la cola; no es un error, y lo que ya se había hecho se
queda.

Al acabar un lote la tira dice cómo fue --**«36 bien, 2 con errores»**, o
«Detenida: 9 de 38 hechos»-- hasta que se cierra.

## La consola

Mientras compila se puede abrir la consola, que enseña lo que el motor va
escribiendo según lo escribe: qué fichero lee, qué paquete carga, qué pasada
va.

No es adorno. La alternativa era un botón que ponía «Compilando…», y un minuto
de eso no se distingue de un cuelgue.

Se enseña **entera y sin filtrar**. Los diagnósticos ya interpretados están en
las tarjetas de resultado, que contestan a «¿qué ha fallado?»; la consola
contesta a «¿qué está haciendo?», y esa pregunta no se contesta con una
selección de líneas.

Cerrarla no para nada, y se puede volver a abrir mientras corre y después,
desde la tira de abajo. Mientras corre tiene también **Detener**.

## El PDF, dentro

Cada salida es **una pestaña más**, al lado de los idiomas y de `unit.yaml`. Y
los idiomas del mismo perfil van en la misma pestaña, lado a lado.

Eso es lo que hace falta para el trabajo real: comparar «cómo queda en
diapositivas» con «cómo queda en libro», o el castellano con el valenciano, es
mirar dos cosas a la vez, y salir a otra aplicación para cada una rompe justo
eso.

En la barra de la pestaña está lo que vale para toda ella: pasar página en los
dos paneles a la vez, separar una versión, elegir otras. Las acciones sobre un
PDF concreto --abrirlo en el visor del sistema, enseñarlo en el Finder-- están
en su propio panel, porque con dos PDF a la vez «abrir en el visor» en la
barra no dice cuál.

### Moverse por el documento

El número de página **se escribe**: con ciento veinte páginas, llegar a la 84
con las flechas son setenta y siete clics. Al lado están el zoom y los tres
ajustes --al ancho, al alto y página entera--, que es como se llega al tamaño
que se quiere de verdad; el porcentaje es un rótulo, y pulsarlo devuelve al
tamaño real.

El botón de la izquierda despliega el **lateral**, con dos vistas:

- **Índice**: los apartados y subapartados del documento, tal y como están en
  la composición. Pulsar uno salta ahí. Sólo aparece cuando el PDF trae
  marcadores, que es el caso de cualquier documento compilado por Didacta.
- **Páginas**: las miniaturas, para reconocer una página por su forma --la
  diapositiva con la figura, la hoja que se quedó casi vacía--.

Todo esto mueve los dos paneles a la vez, igual que pasar página: dos idiomas
del mismo perfil se comparan al mismo tamaño y en la misma página. Y a la
derecha del PDF hay una barra de desplazamiento que se arrastra y dice por qué
página va mientras se mueve.

El visor del sistema sigue estando, y no es redundancia: tiene pantalla
completa para pasar diapositivas de verdad, y el explorador de archivos es
desde donde se arrastra un PDF a un correo.

### Buscar en el PDF { #buscar-en-el-pdf }

La lupa de la barra, o **⌘F** (Ctrl+F) con el PDF delante, abre la búsqueda:
«¿en qué diapositiva estaba la definición de supremo?» sin pasar doscientas
páginas. Como el resto de búsquedas de Didacta, **sin mirar tildes ni
mayúsculas** --«axiomatica» encuentra «Axiomática»--, y un espacio vale
también por un salto de línea, así que se encuentra una frase aunque LaTeX la
haya partido. Lo encontrado se resalta; **Intro** va al siguiente,
**Mayús+Intro** al anterior, y **Esc** cierra.

Con dos idiomas lado a lado se busca en los dos. Cuenta y avanza el primero
que tenga algo, dice cuál («2 de 23 · es»), y el otro panel va a la misma
página, para comparar. En la ventana que abre lo ya compilado está la misma
lupa.

### Del PDF a la lección { #del-pdf-a-la-leccion }

**⌘+clic** (Ctrl+clic en Windows y Linux) sobre cualquier cosa del PDF abre la
lección de donde sale, en su idioma y **con el cursor en su línea**. Lo que se
ve mal en una diapositiva se arregla ahí mismo, sin buscarlo en el fichero.

Lo dice SyncTeX, que viene con la distribución de TeX: cada compilación deja
junto al PDF un `.synctex.gz` con de qué fichero y de qué línea sale cada
trozo. En unos apuntes es exacto. En una diapositiva LaTeX lo apunta todo al
`\end{frame}` --beamer la compone entera al llegar ahí--, así que Didacta
busca además la palabra pulsada entre el principio y el final de esa
diapositiva; si no la encuentra, lleva al `\begin{frame}`.

Lo que no es de ninguna lección --la portada, el índice, que los pone el
documento-- lo dice con su fichero y su línea, sin ir a ninguna parte.

### Cuando un PDF se ha quedado viejo

La pestaña lo marca en ámbar. Lo que hay abierto sigue siendo un PDF de
verdad, pero es de antes del último cambio, y eso hay que saberlo **antes** de
proyectarlo en una clase.

**Viejo es que haya cambiado algo de lo que entró en él.** Al compilar, Didacta
apunta junto al PDF una huella de cada fichero que LaTeX leyó --las lecciones,
sus figuras, la bibliografía, las plantillas-- y después compara el contenido,
no las fechas: traer cambios de GitHub o cambiar de rama pone fechas nuevas a
ficheros que dicen lo mismo, y eso ya no deja nada viejo. Corregir una errata
en una lección sí deja viejo el tema que la incluye; aprobar una traducción,
que solo cambia `unit.yaml`, no. Y si aparece la traducción de una lección
que se había compilado con el original en su sitio, también: el PDF ya no es
el que saldría.

Los PDF de antes de esto, que no tienen huella, siguen juzgándose por las
fechas hasta que se vuelvan a compilar.

### Compilar lo desactualizado

En la página de un curso, cada tema con algo viejo lo dice en su cabecera
--**«2 desactualizados»**-- y al pulsarlo compila solo eso: las versiones y los
idiomas que se han quedado viejos, no todo el tema. Abajo, junto a **Compilar
el curso**, está **Compilar lo desactualizado**, que hace lo mismo con el curso
entero. Después de corregir dos erratas, es compilar dos documentos, no
cuarenta.

## Cuando falla

Las tarjetas de resultado dicen, por cada salida, si salió y en cuántas
páginas. Cuando no sale, **cada error con la lección donde está, su idioma y
su línea**:

```
«Espacios normados» (es) · línea 42 · Undefined control sequence. · \foo   Abrir
```

**Abrir** lleva a esa lección, en ese idioma, con el cursor en esa línea. Salen
todos, no solo los primeros: seis a la vista y **Ver los N** para el resto. El
motor sabe en qué fichero está cada error aunque LaTeX lo encuentre al
componer el documento entero --que es cuando un error de una lección se dice
contra la composición que la incluye--, así que la lección que sale es la que
hay que arreglar.

**En un lote** --un tema entero, un curso-- los errores ya no se pierden entre
las miles de líneas del registro: la consola los enseña arriba, agrupados por
documento y versión, cada uno con su **Abrir**.

Un idioma que falta no es un error: es un aviso. El documento se compila con
el idioma de referencia en su sitio y se dice cuál faltaba.

## Diapositivas que se salen { #diapositivas-que-se-salen }

Una diapositiva con más de lo que cabe **compila**: LaTeX la corta por abajo y
sigue. En el PDF pequeño de la vista previa no se nota, y se descubre al
proyectarla. Ahora la tarjeta de la salida lo dice, con la lección, su idioma y
la línea donde **empieza** esa diapositiva:

```
«Teorema de Bolzano» (es) · línea 1 · La diapositiva se sale por abajo 60 pt (en 5 páginas)   Abrir
```

Solo las que se pasan más de **5 pt**: por debajo no se ve, y son la mayoría
--en el material de Análisis, cuatro de cada cinco se pasan unas décimas--.
Una diapositiva con capas (`\pause`, `\only`) se sale en cada una de sus
páginas y se avisa una vez, diciendo en cuántas. En un lote, la consola las
pone arriba junto a los errores, bajo **«Se salen de la página»**.

**Las líneas de los apuntes** que se salen por el margen derecho no se avisan
de salida: muchas se salen a propósito --una figura más ancha que el texto--.
Quien las quiera ver enciende *Ajustes → Herramientas → Avisar de las líneas
que se salen en los apuntes*.

## Apuntes accesibles { #apuntes-accesibles }

Para quien lee con un lector de pantalla, o necesita el texto grande, Didacta
saca los apuntes de dos maneras más. Ninguna cambia el material: salen del
mismo origen, con las mismas reglas de lo que se ve en cada versión.

**PDF etiquetado.** Con *Ajustes → Herramientas → PDF accesibles*, lo que no
son diapositivas se compila etiquetado (PDF/UA-2): el PDF lleva su árbol de
estructura, dice su idioma y enseña su título en la barra del visor. Desde la
terminal, `didacta build --accessible`. Lo que el etiquetado de LaTeX todavía
no admite --sobre todo las opciones de una lista, `\begin{enumerate}[a)]`--
hace que ese documento salga sin etiquetar, con un aviso que lo dice; no se
queda nadie sin sus apuntes.

**HTML.** Al exportar un curso, *También: los apuntes en HTML* deja al lado de
cada PDF una página que se lee con cualquier navegador: se agranda sin perder
nada, se lee en voz alta --las fórmulas también, con MathJax-- y se adapta al
contraste de quien la mira. Es lo que suelen pedir los servicios de
accesibilidad de la universidad. Las diapositivas no salen en HTML: se leen
sus apuntes.

**El texto alternativo de las figuras** es lo que un lector de pantalla lee en
lugar del dibujo, en el PDF etiquetado y en el HTML:

```latex
\includegraphics[width=.6\textwidth,alt={La bola unidad de la norma uno:
  un cuadrado girado 45 grados}]{figures/bola-uno.pdf}

\begin{tikzpicture}[alt={Una parábola que corta el eje en 1 y en 3}]
  ...
\end{tikzpicture}
```

Sin etiquetado no hace nada, y no estorba: el mismo fuente compila igual. Se
traduce con la lección. Para saber qué figuras no lo tienen, y qué impediría
etiquetar un documento, `didacta check --with accessible` --o la comprobación
*Lo que el PDF accesible no puede leer* al revisar un curso--.

