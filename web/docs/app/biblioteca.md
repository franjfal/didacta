---
title: La biblioteca
description: Explorar el material por materia, o buscarlo.
---

# La biblioteca

Todo el material de todos los repositorios abiertos, junto.

![La biblioteca en vista de árbol](../img/app/biblioteca.png)

## Dos vistas, dos preguntas

**Explorar** --lo que se ve al entrar-- son columnas, como las del Finder:
**categoría**, **tema**, **subtema** y, a la derecha, las lecciones. Se van
abriendo según eliges: con una categoría salen sus temas, y sus lecciones
agrupadas por tema; con un tema, sus subtemas y sus lecciones por subtema; con
un subtema, solo las suyas. Cada nivel dice cuánto contiene y cuánto está
traducido al idioma que estás mirando.

**Cada lección vive en un subtema**, y solo en uno. Es también su carpeta en
el disco --`content/<categoría>/<tema>/<subtema>/<lección>/`--, así que la
biblioteca y el repositorio dicen siempre lo mismo. En una ventana estrecha
las columnas de la izquierda se van quedando fuera según bajas, y las migas de
pan de arriba dicen dónde estás y te devuelven.

**Buscar** aparece en cuanto escribes, y aplana la lista. «hilbert» no es un
sitio del árbol: es todo lo que lo menciona, venga de donde venga. **Sin
mirar tildes ni mayúsculas**: «limite» encuentra «Límite», y cada palabra
tiene que estar, así que «normados problemas» estrecha en lugar de no
encontrar nada.

**Con una errata también.** Una letra de más, de menos, cambiada o dos
intercambiadas --«nomrados», «limtes», «difrenciales»-- encuentra lo que
habría encontrado bien escrita, en las palabras de cinco letras o más (en una
más corta, una letra cambiada es otra palabra). Solo cuando esa palabra no
está tal cual en ningún sitio: si existe, está bien escrita, y buscar
«integral» no trae también lo que dice «integrar». Lo parecido va siempre al
final, detrás de lo que coincide de verdad, y el recuento lo dice aparte:
«· 3 parecidas».

**En el texto**, junto al buscador, busca también **dentro** de las lecciones
y no solo en su título, su ruta y sus etiquetas: «¿dónde usé el teorema de
Bolzano?» se contesta así, aunque la lección se llame de otra forma. Cada
resultado enseña la línea que lo dice --«es · línea 12 · …»-- y al pulsarlo se
abre la lección en ese idioma. Primero van las que casan por el título y
después las que solo lo dicen dentro, con los mismos filtros puestos. Hace
falta la copia del repositorio en tu ordenador, porque lo que busca es git en
esa carpeta; tampoco mira tildes, y pide tres letras por lo menos.

![La biblioteca buscando](../img/app/biblioteca-buscar.png)

??? note "Por qué no una lista plana con filtros"

    Esta pantalla estaba así antes, y merece la pena decir en qué se
    equivocaba: enseñaba las 2147 unidades en una lista con un panel de
    facetas al lado. La lista funcionaba --virtualizada, ordenable,
    filtrable-- y aun así era lo peor que se podía hacer con estos datos,
    porque **tiraba a la basura la organización que el autor ya había hecho**.

    El material está en un árbol, y está en un árbol en el disco. Tres clics
    --categoría, tema, subtema-- llegan a cualquier lección. La lista plana
    llegaba a la misma pasando por delante de otras dos mil.

??? note "Por qué el subtema es una columna y no unas etiquetas"

    El tercer nivel existía antes, pero como **etiquetas**: una fila de fichas
    encima de la lista de un tema. Eran lo que de verdad se usaba para
    encontrar algo --«principio de Cavalieri» dentro de la integración--, y
    eran libres: una lección podía llevar varias, o ninguna, y nadie las
    declaraba. Por eso no podían ser una columna: una lección con dos habría
    salido en dos sitios, y los números de al lado habrían dejado de sumar.

    El subtema se declara en `taxonomy.yaml`, con su nombre en cada idioma, y
    cada lección tiene exactamente uno. Las etiquetas siguen existiendo, como
    lo que son: palabras libres para buscar.

## Vuelve donde estabas

Lo que se ha abierto del árbol, los filtros y lo buscado van **en la
dirección de la pantalla** --`/?q=norma&tipo=problem&en=analysis/normed`--,
así que abrir una lección y volver con **atrás** deja la biblioteca como
estaba, y un enlace a esa dirección la abre igual en otro ordenador.

Escribir en el buscador cambia la dirección a cada letra, pero no llena el
historial: **atrás** vuelve a la pantalla de antes, no deshace la búsqueda
letra a letra.

## Lo de hace poco

En la raíz de la biblioteca, **Abiertas hace poco**: las ocho últimas
lecciones que se han abierto en este ordenador, la más reciente primero. Es lo
que se busca al volver de una clase, y encontrarlo por el árbol son tres
clics.

Con la [interfaz completa](ajustes.md#interfaz), también las **búsquedas
guardadas**: con algo buscado, **Guardar esta búsqueda** le pone un nombre a
lo que se está mirando --lo buscado, los filtros y lo abierto--, y sale ahí
para volver a ello de un clic. La cruz la olvida.

## Los filtros

- **por bloque** — la tira de arriba de la primera columna;
- **por idioma** — el que se está mirando manda en toda la aplicación, y
  decide qué títulos y qué estados se enseñan;
- **por estado de traducción** — qué falta, qué está viejo;
- **por tipo** — una explicación, un ejemplo, un ejercicio;
- **por etiqueta**, que ya no es un nivel sino una palabra libre para buscar;
- **por repositorio**, cuando hay varios abiertos.

Los filtros recortan **también el árbol**, no solo lo que se busca: con «Falta
en este idioma» puesto, las categorías, los temas y sus números cuentan solo lo
que falta, y la cabecera dice cuántas quedan de cuántas —«14 de 58 unidades ·
sin va»—. **Orden** ordena igual las listas de cada tema. Si no queda nada, lo
dice y ofrece quitar los filtros.

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

Las categorías, los temas y los subtemas salen **en el orden en que los
declara `taxonomy.yaml`**, que es el orden en que se dan: la recta real antes
que las sucesiones aunque las sucesiones tengan más. Lo que no declara nadie va
detrás, de mayor a menor.

## Crear categorías, temas y subtemas { #crear-sitios }

Al pie de cada columna, **Nueva categoría…**, **Nuevo tema…** y **Nuevo
subtema…**. Piden el nombre en cada idioma de tus repositorios --basta con
uno; los que dejes vacíos quedan como pendientes de traducir-- y del primero
sale el identificador, que es también el nombre de la carpeta.

Se declaran en el `taxonomy.yaml` de **todos los repositorios abiertos** en los
que puedes escribir, con un cambio en cada uno: la teoría y los problemas de
una asignatura suelen vivir en dos, y los dos tienen que enseñar las mismas
columnas. Lo recién creado sale en su columna aunque esté vacío, para poder
llevarle lecciones.

Cambiar el nombre después se hace en `taxonomy.yaml`; el identificador no se
cambia nunca.

## Mover una lección { #mover }

Tres formas, y las tres hacen lo mismo:

- **arrastrar** la tarjeta de la lección hasta la fila de un subtema, en la
  columna de subtemas;
- el **botón derecho** sobre la tarjeta, **Mover a…**;
- en la lección, **Mover…**, junto a su sitio en los metadatos.

**Mover a…** abre las mismas tres columnas para elegir a dónde, y deja
cambiar de paso el nombre de la carpeta.

La carpeta se mueve de verdad, con sus idiomas y sus figuras, y **nada de lo
que la usa hay que tocarlo**: los temas de los cursos y los prerrequisitos de
otras lecciones la nombran por su **id** (`u-3fa9c2e1b0d4`), que no cambia, y
al compilar Didacta le dice a LaTeX dónde está ahora. Su historial de
traducciones tampoco cambia. Una lección no cambia de repositorio al moverla.

## Lo que dice cada fila

El título en el idioma que estás mirando, y si esa unidad no lo tiene, el del
idioma de referencia **en cursiva y gris**. Eso es deliberado: un título
castellano en un listado valenciano, puesto igual que los demás, parece una
traducción que existe.

Al lado, el estado de cada idioma con su color, el mismo que usan el editor,
el carril y los PDF compilados.

## Crear una lección

Arriba de la lista, **Nueva lección en…** el sitio que estás mirando. Pide lo
mínimo:

- el **título**, del que sale el nombre de la carpeta;
- el **sitio**, en las mismas tres columnas, que vienen abiertas donde estabas.
  Hace falta llegar a un subtema, y si el que quieres no existe, se crea desde
  ahí mismo;
- el **tipo**: teoría, problema, ejemplo…

Y antes de crearla enseña **dónde va a quedar**
--`content/analysis/normed/hilbert/espacios-de-hilbert`--. Si ya hay una
lección ahí, lo dice y no deja crearla.

Al crearla se guarda en el historial, como cualquier otro cambio, y se abre en
el editor con el fichero del idioma de referencia vacío. Los problemas van a
`problems/` y el resto a `content/`: lo decide el tipo, no hace falta
acordarse.

Con más de un repositorio donde se puede escribir, pregunta también en cuál.

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

## Revisar { #revisar }

**Revisar**, arriba a la derecha, mira todo el material abierto en busca de lo
que compila --o casi-- y está mal, y lo enseña agrupado, cada cosa con su
lección, su idioma, su línea y **Abrir**:

- **Órdenes de otro idioma**: `\sptext` y compañía, que solo existen en
  castellano, copiadas en el valenciano. Ahí no compila.
- **Entornos que no define nadie**: ni LaTeX, ni Didacta, ni los snippets del
  repositorio, ni la propia lección.
- **Figuras que faltan.**
- **Etiquetas repetidas y referencias sin destino**, documento por documento
  y en cada idioma: un `\ref` que saldrá como «??» en la clase.
- **Diapositivas que se salen**, según la última compilación.
- **Traducciones desactualizadas** en lo que usan los documentos.

Arriba se piden cinco más, que ayudan a unos y estorban a otros: **fórmulas
distintas entre idiomas**, **lecciones sin usar**, **líneas que se salen en
los apuntes**, **coma y punto decimal mezclados** y **palabras que el
diccionario no conoce**. Se recuerdan mientras la aplicación esté abierta.

La ortografía necesita [hunspell](../cli/index.md#comprobar) y el diccionario
de cada idioma, que se instalan aparte; sin ellos, lo dice. Lo que el
diccionario no conoce y está bien escrito --un nombre propio, un término del
curso-- se apunta en `shared/palabras.txt` del repositorio y deja de salir.

Lo mismo se revisa antes de exportar, solo con lo que se va a repartir.
[:octicons-arrow-right-24: Revisar antes de repartir](exportar.md#revisar-antes-de-repartir)

