# Ajustes

![La pantalla de ajustes](../img/app/ajustes.png)

Los ajustes van **por secciones**, en la columna de la izquierda, y se ve una a
la vez. Son las de abajo, en el mismo orden; cada apartado de esta página lleva
en su dirección el nombre de la sección --`#idiomas`--, que es también lo que
lleva la de Didacta: `/settings?s=idiomas`. Por eso los avisos de otras
pantallas («falta el motor», «no hay repositorios») llevan directamente a la
que hace falta, y *Atrás* vuelve a la de antes. En una ventana estrecha, la
columna pasa a ser una tira arriba.

| Sección | Qué hay | `?s=` |
|---|---|---|
| [Cuenta y repositorios](#repositorios) | la cuenta de GitHub, los repositorios abiertos y dónde se clonan | `repositorios` |
| [Guardar y sincronizar](#guardar) | qué pasa al guardar, las preferencias que viajan, la carpeta de reparto | `guardar` |
| [Idiomas](#idiomas) | con cuáles trabajas y a cuáles traduce cada repositorio | `idiomas` |
| [Traducción automática](#traduccion) | las claves del traductor y el glosario | `traduccion` |
| [Bloques y catálogo](#material) | las partes de una asignatura y lo que hay cargado | `material` |
| [Plantillas de compilación](#plantillas) | qué PDF salen, cómo quedan y en qué repositorios están | `plantillas` |
| [Snippets de LaTeX](#snippets) | lo que envuelve la barra del editor | `snippets` |
| [Herramientas](#herramientas) | git, Python, LaTeX y el motor; cómo se compila | `herramientas` |
| [Servidor MCP](#mcp) | un asistente de IA sobre tu material | `mcp` |
| [Apariencia](#apariencia) | claro u oscuro, el tamaño del texto, Esencial o Completa | `apariencia` |
| [Actualizaciones](#actualizaciones) | qué versión tienes y si hay otra | `actualizaciones` |
| [Ayuda](#ayuda) | la presentación, el recorrido, los atajos y el diagnóstico | `ayuda` |
| [Empezar de cero](#empezar) | dejar Didacta como recién instalada | `empezar` |

En la web no salen *Herramientas* ni *Empezar de cero*: allí no hay nada que
instalar ni que borrar. Y con la [interfaz](#interfaz) *Esencial*, que es la de
salida, tampoco *Bloques y catálogo* ni *Servidor MCP*, que son de quien
mantiene el repositorio del departamento: salen con *Completa*, cuando se llega
a ellas por un enlace, y el servidor también mientras esté encendido.

## Cuenta y repositorios { #repositorios }

### Tu cuenta de GitHub

Quién ha entrado, y los botones de salir o cambiar de cuenta.

El token vive en el **llavero del sistema** --Keychain, Credential Manager,
Secret Service-- y nunca en un fichero de configuración ni en un log. Salir lo
borra de ahí.

[:octicons-arrow-right-24: Cómo funciona el acceso](../empezar/primer-repositorio.md#1-entrar-en-github)

### Los repositorios

Los que están abiertos, cada uno con:

- **su carpeta** en el disco;
- **su color**, el que lo identifica en toda la aplicación;
- **cómo está respecto a GitHub**: cuántos commits por enviar, cuántos por
  traer, si hay cambios sin guardar;
- botones para traer, enviar y quitarlo de la lista.

**Quitar** uno pregunta qué hacer con su carpeta: **Quitar de la lista**, que
la deja en el disco tal cual, o **Quitar y mandar a la Papelera**, con todo lo
que tiene dentro --se recupera desde la Papelera mientras no la vacíes--. Si
tiene cambios sin guardar o sin enviar a GitHub, el diálogo lo dice antes.

Se añaden desde GitHub --Didacta lista los que alcanza tu cuenta-- o eligiendo
una carpeta que ya esté clonada.

**Dónde van** se elige aquí: una carpeta para todos, y dentro, cada
repositorio en la suya. Por defecto, `~/Didacta`.

Uno que esté **fuera** --clonado antes de elegirla, o añadido como carpeta que
ya tenías-- lo dice debajo de su nombre, con un botón para **llevarlo allí**.
Al cambiar de carpeta, Didacta ofrece llevar todos los de antes a la nueva, y
al añadir una carpeta de otro sitio pregunta si moverla. Se mueve la carpeta
entera, con lo que tenga sin enviar; si en el destino ya hay algo, no se toca,
y con cambios sin guardar en alguna pantalla tampoco se mueve nada.

### Compilar en GitHub { #compilar-en-github }

El icono de la nube de cada repositorio hace que **GitHub compile todo su
material cada vez que envías cambios**, sin tu ordenador. Añade al repositorio
un fichero, `.github/workflows/material.yml`, como un cambio más, y a partir
del siguiente envío, en la pestaña **Actions** del repositorio en GitHub:

- comprueba el material con `didacta check`, y el envío sale en rojo si algo
  no va a compilar, con su lección y su línea;
- si el índice (`generated/`) no describe lo que hay, lo regenera y lo guarda;
- compila todos los documentos, y deja los PDF para descargar durante treinta
  días en **dos paquetes separados**: *PDF para repartir*, que como mucho
  lleva los resultados --lo que se puede colgar en el aula virtual--, y *PDF
  del profesor*, con las soluciones, las notas y los exámenes con su
  corrección. Separados a propósito, con la misma regla que al repartir desde
  la aplicación: descargar el primero no puede traer una solución.

Con el CI ya puesto, el icono lleva a lo compilado. El repositorio de ejemplo
lo trae de salida.

Gasta minutos de GitHub Actions --los repositorios privados tienen unos dos mil
al mes sin pagar-- y compila con la versión de Didacta que lo añadió: para
cambiarla, se cambian las dos etiquetas del fichero; para dejar de compilar, se
borra.

!!! note "Si dice que falta un permiso"
    Añadir un workflow necesita el permiso `workflow` de GitHub, que Didacta
    pide desde esta versión. Una sesión de antes no lo tiene: sal y vuelve a
    entrar y ya se podrá. Didacta lo pregunta antes de escribir nada, porque
    un cambio que GitHub rechaza se quedaría sin enviar y taparía los de
    después.

### Poner los ids a las lecciones { #poner-los-ids-a-las-lecciones }

Este apartado **solo aparece mientras haya algo que poner al día**, y con la
interfaz *Completa*; desaparece en cuanto se hace. Un ajuste que sirve una vez y se queda ahí para siempre es
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

## Guardar y sincronizar { #guardar }

### Al guardar

Tres interruptores, en Guardar y sincronizar:

- **Guardar lo deja en el historial.** Encendido, cada guardado es un cambio
  guardado en el historial; apagado, lo guardado se queda escrito y se lleva
  al historial desde la barra de arriba, cuando se quiera.
- **Revisar los cambios antes de guardar.** Apagado de salida: se guarda con
  el mensaje que propone Didacta, y lo que cambió se ve en **Ver cambios**, en
  el aviso. Encendido, cada guardado enseña el diff y pide el mensaje antes.
- **Y se envía a GitHub**, en cuanto se guarda.

### Las preferencias que viajan

Algunas preferencias --qué asignaturas son favoritas, qué temas están
plegados-- son de la persona, no de la máquina, y se pueden guardar en uno de
tus repositorios para encontrarlas igual en el ordenador de casa.

Se **elige** cuál, y no se decide por ti, porque no hay ninguna elección
evidente: cada uno tiene los repositorios que tiene. Sin elegir ninguno, todo
sigue funcionando en esta máquina.

### La carpeta de reparto

Opcional, y apagada de salida. Si repartes con una carpeta de OneDrive, Drive
o Nextcloud que ven tus estudiantes, **elígela aquí**: a partir de entonces
cada curso académico tiene **Publicar en la carpeta de reparto** en su `⋯`.
Publicar es exportar sin preguntar dónde --a `<carpeta>/<asignatura> <año>`--
con lo del estudiante, y el programa de sincronización hace el resto.

Es una ruta de este ordenador, así que no viaja con las preferencias.

[:octicons-arrow-right-24: Exportar un curso](exportar.md)

## Idiomas { #idiomas }

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
`didacta.yaml`, se ve en el diff y lo lee todo el mundo. Pon lo que ese
repositorio mantiene de verdad; uno de más convierte la lista de traducciones
pendientes --que es la lista de trabajo-- en ruido.

![Los idiomas, en Ajustes](../img/app/ajustes-idiomas.png)

En las dos, los idiomas que están salen como **etiquetas**, y los demás se
eligen en el desplegable *Otro idioma…* y entran con *Añadir*. Cada etiqueta
lleva una cruz pequeña para quitarla, y quitar **pregunta antes**: en un
repositorio el botón va en rojo, porque cambia el `didacta.yaml` de todo el
que lo use. Las que no se pueden quitar --el idioma de referencia, uno en el
que se da alguna asignatura, el último que queda-- llevan un **candado** en
lugar de la cruz, y al pasar el ratón por encima dicen por qué.

!!! warning "Un idioma en uso no se puede quitar"

    Si una asignatura se da en él, Didacta se niega y te dice cuáles. No es
    una formalidad: una asignatura declarada en un idioma que su repositorio
    ya no mantiene es un `course.yaml` que el motor rechaza, y entonces la
    asignatura **desaparece de la biblioteca**. Se quita antes de sus fichas.

Quitar un idioma no borra ningún `.tex`: dejan de pedirse. Volver a añadirlo
los recupera.

[:octicons-arrow-right-24: Las cuatro listas de idiomas](../conceptos/idiomas.md#que-idiomas-hay)

## Traducción automática { #traduccion }

La clave del traductor automático --Google o Azure--, que vive en el llavero
y no se vuelve a enseñar, con su botón de probar; el interruptor de
**Apertium**, gratuito y sin clave, para el valenciano; y el **glosario**, los
términos que una traducción tiene que respetar.

[:octicons-arrow-right-24: Traducción automática](traduccion.md#traduccion-automatica)

## Bloques y catálogo { #material }

El bloque dice **qué** material es, y el catálogo enseña lo que hay cargado.
Lo que **sale** de él --las plantillas-- tiene [su propia
sección](#plantillas).

### Bloques { #bloques }

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

#### Quién declara qué

Igual que un tema o una titulación: **la lección nombra el bloque y el bloque
lo declara quien lo tenga**. Con que un repositorio lo declare, todos lo ven
con su nombre.

Aquí es corriente declararlo en varios, a diferencia de los grados: la teoría
y los problemas están repartidos en dos repositorios y los dos necesitan los
dos bloques. Por eso cada bloque enseña en qué repositorios está declarado, y
se marca y se desmarca desde ahí. El precio de declararlo en dos es que pueden
acabar discrepando, y de eso avisa [Entre repositorios](entre-repos.md).

#### Con qué se compila cada bloque

Cada bloque dice en qué plantillas se compila lo suyo, y es el botón de las
hojas de su fila. Eso es **lo que viene marcado** al compilar una lección o un
tema de ese bloque; el menú sigue ofreciendo todas las encendidas, porque el
mismo tema se quiere en libro un día y en diapositivas otro.

Un bloque que no elige compila en todas las encendidas. Vacío nunca quiere
decir «ninguna»: dejaría su material sin salidas y el botón de compilar no
haría nada sin decir por qué.

#### Quitar uno

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

### El catálogo

Lo que Didacta ha leído de tus repositorios, en cifras: cuántas unidades,
asignaturas, salidas e idiomas, el hash del contenido y de dónde se ha leído.
**Recargar el catálogo** lo vuelve a leer sin cerrar la aplicación, y si algo
no se pudo leer --un `unit.yaml` roto, un curso que nombra un idioma que no
está--, la lista de problemas sale aquí.

## Plantillas de compilación { #plantillas }

Una **plantilla** es una salida: qué PDF sale de una lección o de un tema. Trae
la clase de documento, sus opciones, los cinco ejes y --si quieres-- tu propia
cabecera de LaTeX. Esta sección sale con las dos [interfaces](#interfaz): la
cabecera de tu departamento o tus colores también son de quien no mantiene el
repositorio.

Se parece a la de los snippets: **una lista** con todas, y cada una se abre en
**un editor con su vista previa**.

### La lista { #plantillas-lista }

Cada fila dice qué produce --su id, la clase, cuánto enseña de un ejercicio,
si tiene cabecera propia-- y **cuántas cosas la usan**. Debajo, una casilla por
repositorio:

- **marcada**, el repositorio la declara en su `templates.yaml`;
- **marcar otro la copia allí**, entera y con su cabecera;
- **desmarcar uno la quita solo de ese**. Si era el último, pregunta: lo que la
  nombre deja de compilarla.

Con un repositorio basta para usarla en todos: el bloque de teoría puede
compilarse con una plantilla que declara el de problemas. Tenerla también en
otro es lo que hace que viaje con ese material y que no dependa de tener
abierto el primero. Si los dos acaban diciendo cosas distintas, lo avisa
[Entre repositorios](entre-repos.md).

#### Apagar no es borrar

La casilla grande de cada plantilla decide si esa versión se compila. Apagarla
la deja declarada, **con su cabecera**, y fuera de todo lo que se saca: es lo
que se quiere de una versión que este curso no se da. Borrarla perdería justo
lo que había que guardar. Es también la respuesta a tener quince salidas y usar
cuatro.

### El editor { #plantillas-editor }

**Editar**, **Duplicar** y **Nueva plantilla** abren el mismo editor. A la
izquierda, lo que la define:

- **el nombre**, en los idiomas de los repositorios donde está;
- **el identificador**, que es lo que escriben los bloques y los temas y no se
  cambia;
- **la clase y sus opciones**, y **los ejes** --medio, detalle, audiencia,
  soluciones, pausas, maqueta--;
- **su cabecera de LaTeX**. Se lee **al final del preámbulo de Didacta**, así
  que puede redefinir lo que Didacta acaba de definir: los márgenes, los
  colores, un entorno. No lleva `\documentclass` ni `\begin{document}`; de eso
  se encarga la plantilla;
- **en qué repositorios está**, con las mismas casillas que la lista;
- **dónde se usa**: los bloques que la nombran, los que la heredan por no
  decir nada, los documentos que la piden en su `year.yaml` y las lecciones que
  se apartan de su bloque para pedirla.

A la derecha, **la vista previa**: una lección de verdad compilada con lo que
hay en la pantalla, **sin guardar**. Se vuelve a compilar al dejar de escribir
(o con ⌘↵), y la lección se elige arriba --por defecto, la primera que se
compila con esa plantilla--. Si no compila, sale lo que ha dicho LaTeX.

!!! tip "Diapositivas con beamer"

    Con `beamer`, la clase necesita la opción `notheorems`: sin ella beamer
    define sus propios teoremas, chocan con los de Didacta y no compila nada.
    Todas las diapositivas de serie la llevan, y el editor avisa si falta.

!!! warning "Editar una de serie la escribe en tu repositorio"

    Las quince que trae Didacta viven en el programa y **no se tocan ahí**. Al
    editar una, Didacta la declara en el repositorio que marques con su mismo
    id, y a partir de ese momento manda la tuya. La de serie se queda intacta,
    que es lo que mantiene vivo un `pdflatex master.tex` a mano en un editor.

    El editor lo dice antes de guardar, y el identificador no se puede
    cambiar: es justamente lo que hace que sustituya a la otra.

### La carpeta del programa { #carpeta-del-programa }

Además de los repositorios, una plantilla se puede guardar **en el programa**:
para lo que es tuyo y no de la asignatura --el membrete de tu departamento, tus
colores-- o para cuando el material es de otra persona y no puedes escribir en
él. Sale como una casilla más, *programa*, en cada fila y en el editor.

!!! danger "Lo que se guarda en el programa no lo protege nadie"

    No está en git, no se sincroniza y **se va con el ordenador**. Por eso los
    dos botones del final de la sección no son un lujo:

    - **Copiar a una carpeta** saca un `templates.yaml` y sus `.tex` donde
      digas. Es la copia de seguridad, y se puede meter tal cual en cualquier
      repositorio.
    - **Traer de una carpeta** los recupera. Lo que ya esté con el mismo
      nombre se conserva: recuperar una copia encima de lo que se ha escrito
      después es la forma más rápida de perder el trabajo de una tarde.

    La sección dice cuántas plantillas están ahí y en qué carpeta, para que el
    día que cambies de ordenador sepas qué llevarte.

[:octicons-arrow-right-24: Qué es una plantilla, entero](../conceptos/perfiles.md#las-plantillas-tus-propias-salidas)

## Snippets de LaTeX { #snippets }

Un **snippet** es lo que la barra del editor escribe alrededor de lo que
marcas --un teorema, un «solo diapositivas», una caja tuya-- y lo que sabe
quitar después sin tocar lo de dentro. Aquí están todos, los que trae Didacta
y los tuyos, en una sola lista:

- **se buscan** por el nombre, el entorno, la orden o los nombres heredados, y
  se filtran por repositorio, por grupo o por los que no coinciden;
- **se ordenan** arrastrando por el asa (o con Subir y Bajar en su menú): es
  el orden en que salen en el selector de la barra;
- **se reparten**: cada fila tiene una casilla por repositorio, y marcarla o
  desmarcarla lo pone o lo quita de la barra de ese repositorio. Solo se
  ofrece un snippet donde está, porque es donde compila.

### El editor

Al pulsar uno --o **Nuevo snippet**-- se abre su editor, con el formulario a la
izquierda y la **vista previa** a la derecha:

- **qué escribe**: un entorno (`\begin{…} … \end{…}`), una orden
  (`\orden{…}`) o las dos, como los canales, que usan la orden para una frase
  y el entorno para párrafos. Con **argumentos** si lleva algo entre el nombre
  y el cuerpo, como `[Título]` o `{red}`, y con **nombres heredados** para que
  sepa quitar también los que escribía el material migrado;
- **cómo se define**: *Ya definido* si lo define Didacta o un paquete; *Caja de
  teorema* para una caja como las de Didacta, con su pestaña y su número, de
  la que solo se elige el título y el color; o *LaTeX propio*;
- **el título en cada idioma**: si los repositorios elegidos se dan en más de
  un idioma, la caja de teorema pide un título por cada uno --«Resumen»,
  «Resum», «Summary»-- y el PDF saca el del idioma en que se compila. Uno
  vacío saca el del idioma de referencia. En *LaTeX propio* se consigue lo
  mismo con `\DidactaTranslated`, en cualquier texto de la definición;
- un **texto de ejemplo**, que es lo que se ve dentro en la vista previa;
- **en qué repositorios** se ofrece.

La vista previa **compila de verdad**, con el preámbulo de Didacta, mientras
escribes: en apuntes, en la versión del profesor o en diapositivas, y en
cualquiera de los idiomas de los repositorios elegidos. Si la definición tiene
un error, enseña lo que dijo LaTeX.

!!! tip "Un texto que cambia con el idioma"

    ```latex
    \DidactaNewTheorem{resumen}{\DidactaTranslated{es=Resumen, va=Resum, en=Summary}}{didactaThm}
    ```

    Sale el texto del idioma que se compila; en uno que no está en la lista,
    el primero. Un texto con comas o con `=` va entre llaves:
    `es={Uno, dos}`. Los snippets de Didacta no lo necesitan: sus nombres ya
    salen traducidos.

!!! warning "Una definición va al preámbulo de todo el repositorio"

    Lo que define un snippet se lee al compilar **cualquier** documento del
    repositorio que lo tiene, justo antes de la cabecera de la plantilla. Una
    definición con un error deja sin compilar todo ese repositorio. Por eso
    guardar una que no ha compilado en la vista previa se pregunta, y el
    editor no deja definir otra vez un entorno que ya define Didacta.

### Los de Didacta

Los treinta y tantos de siempre salen aquí desde el primer día, con la
etiqueta *Didacta*. Retocarlos --otro nombre, otro grupo-- escribe solo lo que
cambia; el resto sigue siendo el de serie y mejora cuando mejore Didacta.
**Volver al de Didacta**, en su menú, deshace el retoque. Quitar uno de la
barra de un repositorio no rompe nada: el material que ya lo usa sigue
compilando, porque lo define Didacta.

### Dónde se guardan

Cada repositorio tiene los suyos en un `snippets.yaml` en su raíz, con la
definición y el ejemplo dentro. Un repositorio **sin** ese fichero ofrece los
de Didacta, en su orden, como siempre; en cuanto se toca su barra, el fichero
se escribe con esos mismos y lo que cambies.

El mismo snippet en dos repositorios es **uno**: se edita una vez y se guarda
en los dos. Si alguna vez dicen cosas distintas --alguien lo cambió a mano en
uno--, sale marcado como *No coincide* aquí y en
[Entre repositorios](entre-repos.md#los-snippets-que-no-coinciden).

## Herramientas { #herramientas }

### Lo que hace falta en tu ordenador

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

#### Cuando no se puede

Pasa, y más de lo que parece: hace falta la contraseña de administrador, no
hay gestor de paquetes, la máquina es del departamento. Entonces sale un
aviso con las tres cosas que permiten salir del paso:

- **qué se intentó** y **qué contestó** el programa, con un botón para copiar
  el detalle y pegarlo en una búsqueda o en una incidencia;
- **cómo hacerlo a mano**, con las órdenes de este sistema;
- **la guía oficial** de esa herramienta.

Y, abajo, la lista de **dónde ha mirado Didacta**. Si ya la tenías instalada,
esa lista es la única pista que sirve.

### Compilar { #compilacion }

Las dos rutas que la lista de arriba comprueba, para cuando hay que decirlas a
mano:

**El motor** --el repositorio de Didacta, el que lleva `cli/didacta`. Hay un
botón para descargarlo si no lo tienes, y otro para señalar dónde está si lo
tienes en un sitio propio.

Debajo, **de qué versión es**: «Motor de la 0.2.1, la versión de la
aplicación». El que descarga Didacta va siempre en la versión de la
aplicación, y al actualizarla se mueve solo a la nueva. Uno que no descargó
ella --una copia propia, uno clonado a mano-- no se toca solo: si no es el de
esta versión, lo dice y ofrece **Poner el de la 0.2.1**, que pregunta antes.
Con cambios sin guardar en esa carpeta no se ofrece: se perderían.

**La distribución de TeX.** Si no la encuentra, la pantalla dice **dónde ha
mirado**, que es lo que permite arreglarlo.

[:octicons-arrow-right-24: La distribución de TeX](../empezar/latex.md)

**Compilaciones a la vez.** Cuántas versiones de un documento se compilan al
mismo tiempo --las diapositivas y los apuntes, en castellano y en valenciano--.
De salida, **automático**: la mitad de los núcleos del ordenador y no más de
cuatro. Más es más rápido y deja el ordenador más ocupado mientras dura; se
baja en un portátil que se calienta, y se sube en uno que va sobrado.

**Vista rápida.** Apagado de salida. Compilar un documento desde su pantalla
en una sola pasada: tarda la mitad, y el índice y las referencias pueden no
estar al día. Al lado queda «Compilar entero», y compilar un tema o un curso
desde la lista del curso es siempre entero.
[:octicons-arrow-right-24: Vista rápida](compilar.md#vista-rapida)

**Avisar de las líneas que se salen en los apuntes.** Apagado de salida. De
las diapositivas que se salen por abajo se avisa siempre; esto añade las
líneas de los apuntes que pasan del margen derecho más de 5 pt, cada una con
su lección y su línea. Está apagado porque muchas se salen a propósito.
[:octicons-arrow-right-24: Diapositivas que se salen](compilar.md#diapositivas-que-se-salen)

**PDF accesibles.** Apagado de salida. Los apuntes, las hojas y los exámenes
salen **etiquetados** (PDF/UA-2): con su estructura --títulos, párrafos,
listas, fórmulas--, su idioma y el texto alternativo de las figuras, que es lo
que necesita un lector de pantalla para leerlos en orden. Compila con LuaLaTeX
y tarda el doble. Las diapositivas salen como siempre: LaTeX todavía no sabe
etiquetar beamer. Si un documento no se deja etiquetar --hay construcciones que
el etiquetado de LaTeX todavía no admite--, sale sin etiquetar y lo dice.
[:octicons-arrow-right-24: Apuntes accesibles](compilar.md#apuntes-accesibles)

**Avisar al terminar de compilar.** Apagado de salida. Una notificación del
sistema cuando acaba una compilación --si ha salido bien, o cuántos documentos
tienen errores--, pero solo si mientras tanto te has ido a otra ventana: con
Didacta delante no avisa, porque ya se ve. Es para compilar un curso entero y
seguir con otra cosa. En Windows la notificación sale a nombre de PowerShell,
y en Linux hace falta `notify-send`, que traen casi todos los escritorios.

### La carpeta de compilación

La de cada repositorio: cuánto ocupa --los PDF compilados, sus registros y lo
que LaTeX guarda para ir más rápido-- y **Vaciar**, que pregunta antes. No se versiona y no toca el material: todo
vuelve a salir al compilar, la primera vez un poco más despacio. En el
repositorio de Análisis eran 440 MB.

## Servidor MCP { #mcp }

El interruptor, y en qué repositorios puede escribir.

[:octicons-arrow-right-24: El servidor MCP](mcp.md)

## Apariencia { #apariencia }

![Claro, oscuro o el del sistema](../img/app/ajustes-apariencia.png)

**Claro, oscuro o como el sistema**, que es lo que viene: de día claro y de
noche oscuro, si el ordenador lo hace. Cada opción lleva una muestra de cómo
se ve. El botón del sol y la luna, **abajo del todo en la columna de la
izquierda**, pasa de uno a otro sin venir aquí; volver a «como el sistema» se
hace desde esta sección.

El oscuro no es el claro invertido: los colores de los entornos --el azul de
una definición, el ámbar de un ejemplo, el rojo de lo del profesor-- son los
mismos del PDF, aclarados lo justo para leerse sobre oscuro. **Los PDF no
cambian**: se compilan siempre en claro, que es como se imprimen y se
proyectan.

![La biblioteca, en oscuro](../img/app/oscuro-biblioteca.png)

Se recuerda en cada ordenador por separado, y no viaja con las demás
preferencias: la pantalla del despacho y la del portátil en el aula no tienen
por qué querer lo mismo.

### Idioma de Didacta { #idioma-de-didacta }

**Castellano, valenciano o inglés**, o **el del sistema**, que es lo que
viene: si el ordenador está en catalán o en valenciano, Didacta sale en
valenciano; en inglés, en inglés; en cualquier otro, en castellano. Cambia al
momento, sin cerrar nada.

Es el idioma de **la aplicación**, no el del material. Quien trabaja con
Didacta en valenciano sigue preparando los apuntes en castellano y en inglés,
y el idioma que se mira en la biblioteca se elige arriba, como siempre.

Como el modo, es de cada ordenador.

### Tamaño del texto { #tamano-del-texto }

**Más grande o más pequeño**, del 85 % al 150 %, para el proyector del aula o
una pantalla pequeña. Con los botones de aquí o, desde cualquier pantalla, con
**⌘+** y **⌘−** (**Ctrl++** y **Ctrl+−** en Windows y Linux); **⌘0** lo deja
en el normal. En un teclado español vale la tecla del **+**, y también las del
teclado numérico. En el Mac están además en el menú **Ver**.

Como el modo, es de cada ordenador. Los PDF no cambian.

### Interfaz { #interfaz }

**Esencial o Completa.** Esencial, la de salida, es lo de todos los días:
escribir, traducir, compilar y repartir. Completa enseña además lo de quien
mantiene el repositorio del departamento:

- en el editor, la ruta y el tamaño del fichero, la casilla **ordenar al
  guardar** y, en la barra de formato, monoespaciada, término, resaltado,
  **Pausa** y **Ordenar**;
- **reemplazar** en la búsqueda del editor (buscar es de todos);
- **copiar la referencia** de una lección y el `unit.yaml` **en bruto**;
- las **búsquedas guardadas** de la biblioteca;
- **Mover a…** y **Gestionar vinculación…** de un tema, y gestionar la
  vinculación de una lección desde su menú. *Crear copia independiente* es de
  todos, y la franja que avisa al editar una lección que se da en varios
  cursos ofrece gestionarla también con *Esencial*: ahí es parte de no romper
  la asignatura de otro;
- copiar el comando para compilar un documento desde el terminal;
- **Entre repos** en la columna de la izquierda siempre que haya varios
  repositorios abiertos. Con *Esencial* sale solo cuando hay algo que mirar;
- en Ajustes, **Bloques y catálogo**, **Servidor MCP** y
  [poner los ids](#poner-los-ids-a-las-lecciones);
- la ruta y la versión de cada herramienta y del motor. Con *Esencial*, si
  todo está en su sitio, la lista sale en una línea con **Ver detalles**; si
  falta algo, sale entera;
- el registro entero de lo que escriben LaTeX y git al compilar o
  sincronizar. Con *Esencial*, la ventana dice qué está haciendo y cómo ha
  acabado, con el registro detrás de **Ver detalles**; si algo falla sin
  decir por qué, el registro sale solo, que es donde está el porqué.

Un solo interruptor y no uno por botón: lo que se elige es qué clase de uso
se hace de Didacta, no cada cosa por separado.

## Actualizaciones { #actualizaciones }

Qué versión tienes, cuándo se miró por última vez y un botón para mirar ahora.

### Cómo funciona

Didacta mira **una vez por semana**, en segundo plano, después de que la
aplicación esté en pie. Ni al arrancar --retrasaría la primera pantalla por
una petición que a nadie le urge-- ni cada vez, que es cómo un aviso útil se
convierte en ruido que se cierra sin leer.

**Si no hay nada nuevo, no dice nada.**

**Versiones de prueba.** Apagado de salida. Encendido, Didacta ofrece también
las versiones que se publican para probarlas antes que nadie --la 1.5.0-rc.1
antes que la 1.5.0--, y dice «de prueba» al ofrecerlas. Pueden traer fallos.
La final llega después igual: es más alta que sus pruebas, así que quien
estaba en una pasa a la final sin hacer nada.

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
## Ayuda { #ayuda }

**Volver a ver la presentación**, que explica qué es Didacta; **Ver el recorrido
guiado**, que va de pantalla en pantalla --una asignatura, su curso, un
documento, la biblioteca y una lección-- señalando cada parte y al acabar te
deja donde estabas; los **atajos de teclado** y **la documentación**. Y, debajo, **Copiar informe de diagnóstico**: lo que ha pasado
por dentro --la versión, el sistema, cada orden del motor y de git con su
resultado y cuánto tardó, lo que contestó GitHub cuando no fue un sí y los
errores que Didacta se tragó para seguir adelante-- listo para pegar en una
incidencia. El aviso ofrece **Abrir una incidencia** con el informe ya dentro.

!!! note "Sin claves ni contraseñas"

    Todo pasa antes por un filtro que quita los tokens de GitHub, las claves
    de traducción y las credenciales de una dirección. Sí lleva rutas y
    nombres de ficheros: revísalo antes de enviarlo.

El registro también queda en un fichero, dos de un mega como mucho: en macOS,
`~/Library/Logs/Didacta/diagnostics.log`; en Windows,
`%LOCALAPPDATA%\Didacta\diagnostics.log`; en Linux,
`~/.local/state/didacta/diagnostics.log`.

## Empezar de cero { #empezar }

Aparte, al final y en rojo, porque no se deshace. **Restablecer Didacta…** deja
la aplicación en este ordenador como recién instalada: sin la sesión de GitHub
ni las claves de traducción, sin ajustes y sin la lista de repositorios. Al
volver a abrirse empieza por la bienvenida.

El diálogo dice qué se va a borrar y ofrece dos casillas, apagadas de salida:
mandar también a la Papelera **las carpetas de los repositorios** --con aviso
si alguno tiene trabajo sin enviar a GitHub-- y **las plantillas guardadas en
el programa**. En GitHub no se toca nada.

!!! tip "Tirar la aplicación a la Papelera no basta"

    Desinstalar Didacta deja el token en el llavero y los ajustes en su
    carpeta. Si no quieres que quede nada, restablécela antes.
