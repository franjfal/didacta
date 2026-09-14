# Didacta — arquitectura

Por qué la plataforma está construida así.

Didacta es software; el material docente vive en **repositorios de contenido**
separados, cuya estructura Didacta define. Esa separación es la primera
decisión y condiciona el resto: la plataforma se versiona, se prueba y se
despliega por su cuenta, y un repositorio de contenido no contiene una sola
línea de código de plataforma.

---

## 1. El problema

Un profesor escribe un concepto una vez y lo necesita en muchas formas:
proyectado con pausas, impreso sin ellas, desarrollado en apuntes, resumido en
un handout, con notas didácticas para sí mismo, en tres idiomas. Y lo necesita
en varias asignaturas y en varios cursos académicos.

Hacerlo copiando ficheros produce lo que produce siempre: N copias que divergen.
La respuesta correcta es **un origen y muchas salidas generadas**.

El material que Didacta sustituye ya había llegado a esa conclusión y la había
implementado: 1.821 unidades reutilizadas por 778 composiciones, 1.343 de ellas
en más de un curso académico, con `\onlyslides`/`\onlybook` decidiendo qué
aparece dónde. **El mecanismo era correcto.** Lo que costaba era todo lo demás:
seis paquetes `.sty` no-CTAN, `../../../../` codificado a mano con distinta
profundidad según dónde estuviera el fichero, el idioma en el nombre del
fichero con cuatro convenciones distintas, los metadatos repartidos entre una
carpeta, una variable de Makefile y un `\def`, y 400 Makefiles.

Didacta conserva el mecanismo y rehace la infraestructura.

---

## 2. Las capas

```
┌──────────────────────────────────────────────────────────────┐
│  cli/didacta          la herramienta                         │
├──────────────────────────────────────────────────────────────┤
│  engine/didacta/                                             │
│    profiles.py    el registro de salidas                     │
│    repo.py        el modelo del repositorio de contenido     │
│    build.py       compilación, TEXINPUTS, logs               │
│    yamlio.py      lectura de metadatos                       │
├──────────────────────────────────────────────────────────────┤
│  latex/                                                      │
│    didacta-bootstrap.tex   elige la clase según el perfil    │
│    didacta-profiles.tex    ← fuente de verdad de las salidas │
│    didacta.sty  + formats · theorems · problems · theme      │
│                 · page · colours · lang/{es,va,en}           │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
        repositorio de contenido (aparte, versionado por su cuenta)
          didacta.yaml · content/ · problems/ · courses/ · shared/
```

**El motor no es obligatorio.** `pdflatex master.tex` produce un PDF sin que
Didacta intervenga. Eso no es un accidente: la compilación directa desde el
editor con SyncTeX funcionando es un requisito irrenunciable, y una plataforma
que se interpone entre el autor y su compilador acaba estorbando.

Lo que el motor añade: `TEXINPUTS`, el directorio de salida, los metadatos por
idioma, las pasadas necesarias, la lectura de los logs y saber qué construir.

---

## 3. El mecanismo de salida

### 3.1 El problema de la clase

Las diapositivas necesitan `beamer` y la prosa necesita `article` o `book`.
Ninguna clase puede ser ambas. Con un único origen, la clase **tiene** que
elegirse antes de `\documentclass`.

Didacta lo hace con un fichero de arranque:

```latex
\input{didacta-bootstrap}     % lee \DidactaProfile y elige la clase
\usepackage{didacta}
```

`didacta-bootstrap.tex` consulta el registro de perfiles, saca la clase y sus
opciones, y ejecuta `\documentclass`. Sin perfil declarado usa `notes` — así
abrir el fichero y pulsar compilar produce los apuntes sin configurar nada.

El sistema anterior llegaba a la misma solución (`\@ifundefined{documentclassname}`)
pero **deducía** el comportamiento de qué clase resultaba cargada
(`\@ifclassloaded{beamer}`). Didacta lo declara: el perfil es explícito y con
nombre, y qué significa está en un solo sitio.

### 3.2 Perfiles como preajustes sobre ejes

Un perfil no es una plantilla. Son cinco ejes independientes:

| Eje | Valores | Qué controla |
|---|---|---|
| `medium` | `slides` · `document` | beamer, o article/book + `beamerarticle` |
| `detail` | `brief` · `full` | si aparece la prosa y las demostraciones |
| `audience` | `student` · `teacher` | si aparece el canal del profesor |
| `solutions` | `hidden` · `answers` · `full` | qué nivel de respuesta se revela |
| `pauses` | `on` · `off` | si `\dpause` revela o se colapsa |

Las 15 salidas son combinaciones con nombre. Añadir una es una línea:

```latex
\DidactaDeclareProfile{notes-solutions}{article}{12pt,oneside}{%
  medium=document,detail=full,audience=student,solutions=full,pauses=off}
```

Nada más en el sistema necesita saberlo: el motor lee el registro, el CLI lo
lista, la etiqueta se deriva de los ejes. Los ejes son ortogonales a propósito
— `detail=brief` con `medium=document` es exactamente un examen, y eso salió
gratis.

### 3.3 `beamerarticle` es la línea que lo sostiene

En un perfil de documento, `didacta.sty` carga `beamerarticle`. Eso convierte
`\begin{frame}`, `\frametitle` y `\pause` en operaciones inocuas en lugar de
errores, y es lo que permite que el **mismo** fichero sea una diapositiva y un
párrafo. Sin eso no hay un solo origen.

Se carga con `notheorems`: beamer define por su cuenta `theorem`, `definition`,
`lemma`, `corollary`, `example` y `solution`, que chocan con los de Didacta.
Suprimirlos deja un solo juego de nombres con un solo significado.

### 3.4 La interfaz motor ↔ LaTeX

Dos definiciones en la línea de órdenes:

```bash
pdflatex "\def\DidactaProfile{slides}\def\DidactaLanguage{va}\input{tema-1}"
```

Y nada más. Los metadatos no van por ahí: van en un fichero que el motor
escribe en el directorio de salida y que LaTeX hace `\input`. Meter llaves y
acentos en un `\def` de línea de órdenes es un problema de *quoting* esperando
a ocurrir; un fichero no lo es.

Ese fichero se aplica con `\AtBeginDocument`, así que gana sobre el
`\DidactaCourse` del preámbulo. El orden es intencionado: lo que el fichero
declara es un respaldo para compilar a mano, y `course.yaml`/`year.yaml` son la
autoridad cuando compila Didacta. Sin eso los metadatos hay que escribirlos dos
veces y divergen — que es cómo una cabecera en valenciano acaba sobre una hoja
en castellano.

---

## 4. El contenido

### 4.1 Una unidad es un directorio

```
content/analysis/normed-spaces/definition/
    unit.yaml        título, etiquetas, idiomas, estado, prerrequisitos
    es.tex           el contenido
    va.tex
    figures/
```

Los idiomas, los metadatos y las figuras se mueven juntos. Renombrar o mover
una unidad es una operación y nada fuera de ella hay que avisar.

Antes: `03VAL-espacios-normados.tex` junto a `03CAS-espacios-normados.tex` en
un directorio con otros treinta ficheros, sin metadatos, y el idioma en el
nombre con cuatro convenciones distintas (`CAS`, `CAST`, `VAL`, `ENG`, más 606
ficheros sin ninguna).

### 4.2 El idioma es el nombre del fichero

`es.tex`, `va.tex`, `en.tex`. Una convención, no cuatro.

El ordinal que antes llevaba el orden (`03…`) vive ahora en la composición, que
es donde el orden pertenece. Reordenar un tema ya no implica renombrar
ficheros — y en el material anterior el orden de los `\import` del maestro ya
no coincidía con el orden numérico de los nombres, precisamente porque
renombrar era demasiado caro.

### 4.3 Las referencias no son rutas

```latex
\DidactaUnit{analysis/normed-spaces/definition}
\DidactaProblem{analysis/normed-spaces/norm-axioms}
```

Se resuelven contra la raíz del repositorio, que el motor inyecta. Ninguna
composición contiene `../../../../`.

En el sistema anterior el mismo import había que escribirlo con cuatro, cinco o
seis niveles de `../` según la profundidad del maestro, y mover una carpeta
rompía sus 13.212 aristas de golpe.

### 4.4 Un curso guarda estructura, no contenido

```
courses/am-iii/
    course.yaml           lo que no cambia entre cursos: código, grado, centro
    2025-2026/
      year.yaml           selección, orden, grupo, idioma
      tema-1.tex          la composición
```

`didacta new year am-iii 2026-2027` copia la estructura. Las unidades se siguen
referenciando, no se copian. Es la razón de que la separación exista.

### 4.5 El estado de traducción se calcula, no se declara

`missing` sale de si el fichero existe. `outdated` sale de comparar el
`source_hash` registrado con el hash actual del original. Escribir cualquiera
de los dos en el YAML garantiza que se quede obsoleto, así que el modelo los
**rechaza** si se declaran — incluso en los propios ejemplos de Didacta.

Declarables: `draft`, `translated`, `reviewed`, `source`.

`source` existe porque el fichero de referencia no es una traducción de nada, y
llamarlo `reviewed` por defecto afirmaría una revisión que nadie hizo.

### 4.6 Si falta una traducción, se recurre a la de referencia

Con un aviso en el log y en la salida del motor. Una diapositiva sin traducir
es mucho más útil que un hueco en la presentación. Si no existe en ningún
idioma, sale un marcador visible en el PDF: mejor enterarse al revisar que
delante de la clase.

---

## 5. Compilación

**Siempre fuera del árbol.** Auxiliares y PDF van a un directorio de
compilación. Compilar en el sitio es cómo un repositorio acaba con 1.608 `.aux`
y 1.677 `.log` versionados, que es el estado exacto del repositorio anterior.

**SyncTeX siempre activo.** Hacer clic en el PDF y llegar a la línea del fuente
es un requisito, no una opción, así que no es una bandera.

**`latexmk`, no un bucle propio.** Las referencias cruzadas, el índice y el
total de diapositivas necesitan dos o tres pasadas, y `latexmk` ya sabe cuándo
ha convergido. Reimplementarlo es una forma de publicar números de página
sutilmente equivocados.

**Un perfil, un directorio.** Dos perfiles del mismo documento comparten nombre
de trabajo solo por accidente; separar sus auxiliares significa que una
compilación en paralelo no se corrompe y que un perfil que falla deja intactos
los demás.

**`TEXINPUTS`, no rutas relativas.** El árbol LaTeX de Didacta se añade al
camino de búsqueda. Un repositorio de contenido no contiene ninguna ruta hacia
la plataforma.

### Lectura de logs

El motor sigue la pila de ficheros abiertos del log para atribuir cada error al
fichero de contenido que lo causó, no al envoltorio. Esa atribución es el punto
entero: un error reportado contra un fichero generado no sirve de nada.

De los avisos solo se muestran los que se pueden accionar — referencias y citas
sin definir. Un *underfull box* en una diapositiva es normal, y sacarlos todos
enseña al lector a ignorar la lista.

---

## 6. Dependencias

Todo lo que Didacta usa está en CTAN.

Lo que se ha eliminado y con qué se ha sustituido:

| Antes (no-CTAN) | Ahora |
|---|---|
| `boiboites.sty` (`\newboxedtheorem`) | `tcolorbox` |
| `beamerthemeTorino` + `chameleon` + `decolines` + `fancy` | `didacta-theme.sty` sobre beamer estándar |
| `multiaudience` | los cuatro niveles, implementados directamente |
| `LaffayetteComicPro` (fuente empaquetada) | eliminada |

Se ha añadido `empheq` (ecuaciones destacadas y en caja): lo usa el material
migrado y `mathtools` por sí solo no lo trae.

Motivo: un sistema que no compila en una máquina limpia no es una plataforma.

Python 3.9 sin dependencias. PyYAML se usa si está; si no, el motor trae su
propio lector del subconjunto que los esquemas necesitan — la plataforma tiene
que funcionar en un runner de CI sin un paso de `pip`.

---

## 7. Decisiones registradas

| # | Decisión | Motivo |
|---|---|---|
| D1 | La plataforma y el contenido van en repositorios separados | la plataforma se versiona y prueba por su cuenta; un repositorio de contenido no contiene código |
| D2 | `didacta-profiles.tex` es la fuente de verdad de las salidas, y el motor lo parsea | declararlas en YAML y generar el LaTeX haría el sistema LaTeX inutilizable sin el motor, y `pdflatex master.tex` tiene que seguir funcionando |
| D3 | Un perfil es un preajuste sobre cinco ejes, no una plantilla | añadir una salida es una línea; los ejes ortogonales dan combinaciones útiles gratis (`detail=brief` + `medium=document` = examen) |
| D4 | Fichero de arranque, no una clase propia | ninguna clase puede ser beamer y article a la vez, y con un único origen la elección tiene que ocurrir antes de `\documentclass` |
| D5 | `beamerarticle` con `notheorems` en los perfiles de documento | es lo que permite que `\begin{frame}` funcione en prosa; `notheorems` evita el choque con los seis entornos que beamer define por su cuenta |
| D6 | Un solo juego de nombres de entorno; el aspecto lo decide el medio | antes había dos juegos (`ndefn` con caja, `defn` sin ella), así que el contenido tenía que saber a qué salida iba |
| D7 | Un contador compartido para todos los entornos de teorema | contadores independientes producen Teorema 2.3 seguido de Definición 2.1, y rompen cualquier referencia que el lector siga |
| D8 | Cuatro niveles de respuesta (`hint`, `answer`, `solution`, `marking`), no uno | el sistema anterior solo tenía `shownto{solution}`; la audiencia `profesor` estaba declarada y ningún fichero llegó a usarla |
| D9 | `\onlyteacher` es un canal real, distinto de `\onlynotes` | antes estaban definidos igual, así que no había forma de escribir una nota que llegara al profesor y no al alumno |
| D10 | El idioma es el nombre del fichero (`va.tex`) | una convención en lugar de cuatro, y el ordinal deja de codificar el orden |
| D11 | Las referencias se resuelven contra la raíz del repositorio | elimina los `../../../../`, que rompían al mover cualquier carpeta |
| D12 | `missing` y `outdated` se calculan y el modelo los rechaza si se declaran | metadato que duplica un hecho comprobable se queda obsoleto sin falta |
| D13 | Si falta una traducción se usa la de referencia, con aviso | una diapositiva sin traducir es más útil que un hueco delante de la clase |
| D14 | Los metadatos se inyectan desde `course.yaml`/`year.yaml` con `\AtBeginDocument` | escribirlos también en el `.tex` los duplica por idioma y divergen |
| D15 | Compilar siempre con `-outdir`; nunca `make clean` | compilar en el sitio es cómo el repositorio anterior acabó con 1.608 `.aux` versionados |
| D16 | `\dmarks`, no `\marks` | `\marks` es una primitiva de TeX; sobreescribirla rompe las rutinas de salida de forma tardía y difícil de rastrear |
| D17 | `enumitem` solo en perfiles de documento | bajo beamer descarta silenciosamente las plantillas de viñeta y las listas salen sin marcador |
| D18 | Solo paquetes de CTAN | seis `.sty` no-CTAN y una fuente empaquetada hacían imposible compilar en una máquina limpia |
| D19 | Los alias heredados se conservan (`\onlybook`, `ndefn`, `ej`, `shownto`) | la migración es un movimiento, no una reescritura |
| D20 | La migración nunca escribe en el origen, y nada sin `--apply` | el material antiguo tiene que seguir compilando con sus Makefiles todo el tiempo que dure el traslado; hay un test que compara el tamaño de cada fichero seguido por git antes y después |
| D21 | Al migrar se quita el prefijo de orden del nombre, y las colisiones se desambiguan con él | en Didacta el orden vive en la composición; pero 66 destinos los reclamaban 150 unidades, así que sin desambiguar se perdían 84 unidades de material real |
| D22 | Lo que estaba comentado en un master se conserva comentado en `year.yaml` | 668 referencias y 74 apartados están comentados, y cada uno registra algo que se decidió dejar fuera ese curso |
| D23 | Los apartados de un documento van en la composición, no en la unidad | un `\section` dentro de una unidad viaja con ella a cada asignatura que la reutilice, y solo puede estar en un idioma |
| D24 | Una ruta de `\import` se resuelve por su cola desde `00classnotes/` | 79 referencias no coinciden en mayúsculas con la carpeta real y otras tantas llevan un `../` de menos: funcionan en macOS y no en Linux. La cola dice sin ambigüedad qué fichero se quería |
| D25 | El tipo de un documento sale de la carpeta, no de la plantilla | un seminario y una clase cargan la misma `Presentations-template`, así que la plantilla sola convertiría 49 seminarios y 39 prácticas en clases y compilaría los perfiles equivocados |
| D26 | Las figuras van en `figures/` dentro de la unidad, y la migración reescribe la referencia | 710 de las 2147 unidades usan figuras; copiar el fichero y dejar `img/circle-1` en el `.tex` las rompe todas |
| D27 | Los entornos que declaraba cada preámbulo se renombran, no se alían | el preámbulo es justo lo que la migración borra, así que `ejer` -- 2993 usos -- no compila de ninguna forma; y lo que quede sin renombrar se reporta, porque un error de compilación descubierto unidad a unidad se descubre tarde |
| D28 | `sol` se convierte en `proof`, no en `solution` | `sol` envolvía `\begin{proof}`: prosa que siempre se veía. `solution` está detrás del eje de soluciones, así que el cambio la habría quitado de la copia del alumno |
| D29 | El encabezado va en `year.yaml` *y* en el `.tex` | `year.yaml` lo tiene en los tres idiomas y es la autoridad; el `.tex` es lo que lee `pdflatex`, así que sin él el PDF migrado perdería los 2336 encabezados que tenía. Misma división que el título del documento (D14) |
| D30 | Los nombres de metadatos antiguos (`\profesor`, `\dateshort`, `\chapterName`, …) son alias de los datos de Didacta | el material se construye sus propias cabeceras con ellos, y Didacta ya tiene cada valor en el idioma que se compila; definir el nombre antiguo conserva el contenido tal cual, mientras que reescribirlo sería editar cientos de ficheros. Los que no tienen equivalente (`\texpath`, `\nohyphens`, `\documentclassname`) sí se quitan, y se reportan |
| D31 | La compatibilidad vive en `didacta-legacy.sty`, y no carga ningún paquete nuevo | tener la superficie de compatibilidad en un fichero permite verla y verla encoger. La regla de no cargar paquetes se aprendió por las malas: `fancybox` y `todonotes` cambiaron la tipografía de *todos* los documentos, también los que no tienen material heredado. Una capa de compatibilidad que estropea la salida correcta es peor que la incompatibilidad, así que los sustitutos se construyen sobre `tcolorbox`, que ya estaba |
| D32 | `\sec` fuera de modo matemático se reescribe a `\didactaCourseGroup` | las plantillas antiguas redefinieron la secante como el grupo, y el material usa las dos cosas: 98 veces la función y 58 una cabecera. Didacta no rompe las matemáticas, así que la migración distingue por contexto |
| D33 | `\question{…}` se convierte en el entorno `question` | en LaTeX `\begin{question}` *es* `\question`, así que el macro de la plantilla FAQ y el entorno de Didacta son el mismo nombre y no pueden coexistir |
| D34 | `didacta migrate --verify` compila lo migrado y lista en el informe lo que no sale | encontrar qué unidades no compilan requería migrar la biblioteca y luego compilarla a mano leyendo los logs. Es el bucle que también tendría que hacer el autor, así que va en la herramienta. Casi nada de lo que encuentra son fallos de la migración, pero son justo los que no se ven leyendo 2147 ficheros |
| D35 | La interfaz lee un índice generado, no el repositorio | listar 2147 unidades leyendo el repositorio son 2147 peticiones desde un navegador. Tres JSON estáticos —77 KB comprimidos— responden a la vista entera, y se pueden servir desde GitHub Pages sin servidor |
| D36 | El índice no lleva marca de tiempo | la llevó, y rompió lo único que lo hace fiable: con un `generatedAt` dos ejecuciones sobre el mismo contenido dan bytes distintos, así que `--check` daba el índice por obsoleto justo después de escribirlo y cada regeneración era un diff. Cuándo se generó lo dicen el mtime y el commit; lo que hace falta saber es si coincide con el contenido, y para eso está `contentHash` |
| D37 | El índice calcula en qué documentos se usa cada unidad | es la respuesta a «¿puedo cambiar esto?», y exige recorrer todas las composiciones: precisamente lo que una interfaz no puede hacer |
| D38 | La lógica de la app va en Dart puro, sin Flutter | «web primero, escritorio después sin reescribir la lógica» solo se cumple si la parte que merece la pena reutilizar no toca un widget. Es además la parte comprobable: 33 tests sin superficie de render, y un filtro que se come filas en silencio es invisible en una interfaz |
| D39 | Cada pantalla tiene una URL | es una aplicación web: «mándame el enlace de esa unidad» tiene que funcionar, atrás tiene que significar algo y recargar tiene que dejarte donde estabas. Una ruta por pantalla es también lo que permite probar las doce direcciones a tres anchos |
| D40 | Un campo de un YAML se edita reescribiendo su línea, no reserializando el fichero | un `unit.yaml` migrado lleva el fichero del que salió y un `TODO` en cada campo que el material heredado no registraba: la lista de trabajo de dos mil unidades. Un round trip por un parser la borra entera, en silencio, en la primera edición. Y cuando `YamlPatch` no reconoce una forma, rechaza en lugar de adivinar: corromper la fuente de la verdad es peor que no editarla |
| D41 | Una entrada comentada de una composición es un estado, no basura | 905 entradas de los `year.yaml` están comentadas: material que existe y que este año no se da. Volver a activar algunas es la edición más común después de una migración, así que se ven tachadas en su sitio en el orden y se activan en un toque. Un editor que hubiera parseado el bloque las habría borrado todas en el primer arrastre |
| D42 | Antes de un commit se ve el diff | que solo se toquen las líneas pedidas es una promesa sobre el fichero de otra persona. Se enseña en lugar de afirmarse, y si el diff tiene mala pinta se cancela |
| D43 | En escritorio la aplicación lleva el clon ella misma | «sin necesidad de instalar y configurar GitHub»: clonar, traer, commit y enviar con el token que se pegó una vez, sin `gh auth login`, sin credential helper, sin clave SSH. Se hace con el binario `git`, no con una reimplementación en Dart, porque un fallo ahí corrompe el repositorio del que sale todo |
| D44 | Un commit local no necesita token; solo el envío | escribir en un clon que está en tu propio disco no necesita credencial, y exigirla habría roto el camino sin conexión, que es la razón de que el clon exista. El autor sale de la sesión o de la identidad de git del equipo: pedir que alguien inicie sesión en un servicio web para escribir un fichero de su propio disco sería absurdo |
| D45 | El token va en el entorno del proceso hijo, nunca en `argv` ni en `.git/config` | lo lee de ahí un credential helper de una línea. El atajo habitual —meterlo en la URL del remoto— lo deja escrito en un fichero dentro del clon, y `ps` enseña la línea de órdenes de cualquiera |
| D46 | El sandbox de macOS queda desactivado, y el entitlement explica por qué | una app en sandbox no puede ejecutar un binario fuera de su bundle ni volver a abrir una carpeta elegida en otra sesión, así que no puede llevar un clon. El coste es no poder ir a la Mac App Store, que para una herramienta que su autor instala en su propio equipo no es un coste |
| D47 | Con un clon, el catálogo se lee del clon | si la biblioteca leyera una copia servida por HTTP y el editor escribiera los ficheros del disco, las dos podrían discrepar. La fuente de la verdad en este equipo es el clon |

---

## 8. Migración

La compatibilidad está integrada a propósito, para que traer el material sea
mecánico:

| Del sistema anterior | En Didacta |
|---|---|
| `\onlybook{…}` | funciona; alias de `\onlynotes` |
| `\onlyslides{…}` | funciona |
| `ndefn`, `nthrm`, `defn`, `thrm`, … | funcionan; apuntan al entorno correspondiente |
| `\begin{ej}` | funciona; alias de `exercise` |
| `\begin{shownto}{solution}` | funciona; se convierte en `solution` |
| `\begin{shownto}{profesor}` | funciona; se convierte en `marking` |
| `nformula` | funciona; alias de `keyformula` |
| `ejer`, `ejem`, `df`, `prob`, `nota`, `teo`, `cuestion`, … | se renombran al migrar; los declaraba el preámbulo de cada fichero, no una plantilla, así que no hay alias posible |
| `\profesor`, `\dateshort`, `\class`, `\chapterName`, … | funcionan; alias de los datos de `course.yaml` y `year.yaml` |
| `chameleongreen1..4`, `labelcolor` | funcionan; los valores son los del tema antiguo |

Está implementado en `engine/didacta/legacy.py` (leer el sistema anterior) y
`engine/didacta/migrate.py` (escribir el nuevo), y se usa con
`didacta migrate <origen> <destino>`. Medido sobre el repositorio actual: 2147
unidades a partir de 2438 ficheros, y 784 documentos en 17 asignaturas y 30
cursos académicos, con 6137 referencias a unidades de las que 4 no resuelven.

### Una unidad

1. los ficheros de un mismo contenido en varios idiomas se agrupan en un
   directorio y se renombran `es.tex` / `va.tex` / `en.tex`;
2. se **borra el preámbulo**, que es exactamente lo que `docmute` estaba ahí
   para descartar;
3. se renombran entornos y macros donde el alias es peor que el nombre real;
4. se escribe un `unit.yaml` con lo que la ruta permite deducir.

### Una composición

Un master antiguo es un preámbulo, un título y una lista ordenada de
`\import{../../../../00classnotes/…}`. Lo único con significado propio es la
lista, y pasa al `structure:` de un `year.yaml`; el `.tex` que queda son dos
líneas de arranque. Los `\section` intercalados pasan también a la
composición, que es donde pueden estar en los tres idiomas (D23).

El master antiguo nombraba una variante concreta (`03VAL-espacios-normados`) y
la composición nueva nombra la unidad (`functional/espacios-normados/…`),
dejando el idioma al perfil. Ese colapso es el objetivo de todo el ejercicio.

### Lo que no compila y por qué

Migrar el material y compilarlo entero es lo que encuentra estas cosas; leer el
código no las encuentra. Lo que apareció al hacerlo:

* **entornos que declaraba el preámbulo de cada fichero** (`ejer`, 2993 usos)
  — no hay alias posible, porque el preámbulo es justo lo que se borra, así que
  se renombran (D27) y lo que quede sin renombrar se reporta;
* **macros de metadatos** (`\profesor`, `\dateshort`) — el material se
  construye sus propias cabeceras con ellas, así que Didacta las define (D30);
* **colores del tema retirado** (`chameleongreen3`) — mismo trato;
* **`empheq`** — lo usa el material y `mathtools` no lo trae;
* **encabezados envueltos en `\onlybook{…}`** — `year.yaml` no sabe decir "solo
  en apuntes", así que se quedan en el `.tex` y se reportan.

* **`\sec` como grupo** — `(\sec)` en una cabecera es `Missing $ inserted`;
  se reescribe por contexto (D32);
* **`\question{…}`** — el mismo nombre que el entorno de Didacta, así que se
  reescribe (D33);
* **un `%` en el título** — `clean_text` no quitaba comentarios, y el título de
  un documento salía como `%`, que además latexmk rechaza como nombre de
  trabajo.

Lo que queda son fallos del contenido, no de la migración: un `tikzpicture` que
desborda una dimensión, una interacción de `tikzfill` con beamer, un
`\animategraphics` cuyo paquete Didacta no carga. Salen en el informe con
fichero, línea y la macro culpable, que es lo que hace falta para arreglarlos
de uno en uno.

### Lo que no se deduce

El título por idioma, las etiquetas más allá de la carpeta, los prerrequisitos,
los objetivos y la duración no están en ninguna parte del material anterior.
`MIGRATION-REPORT.md` dice qué falta y en qué unidad, en lugar de rellenarlo
con algo plausible: un metadato inventado llega al lector con la autoridad de
estar escrito.

Todas las unidades llegan con estado `draft`. Se han movido, no revisadas en el
sistema nuevo.

---

## 8.bis Los índices y la interfaz

```
repositorio de contenido          la interfaz
├── content/  problems/           ┌─────────────────────┐
├── courses/                      │  app/  (Flutter)    │
└── generated/        ─────────►  │  lee generated/     │
    ├── manifest.json             └─────────────────────┘
    ├── units.json     2 MB / 77 KB comprimido
    └── courses.json
```

`didacta index` genera esos tres ficheros; la aplicación no habla con el
repositorio directamente. Son estáticos, así que una publicación en GitHub
Pages no necesita servidor — y `api/` solo hará falta cuando haya que
*escribir*.

Dentro de la aplicación el corte es el mismo por el mismo motivo:

```
app/lib/
├── model/   Dart puro. Parseo, filtros, cuentas, edición de YAML. Cero widgets.
├── data/    De dónde vienen los datos y por dónde salen los cambios.
├── state/   Session: lo único que sabe el estado del mundo.
├── router.dart  Las rutas: una URL por pantalla.
└── ui/      Widgets.
```

---

## 9. Lo que falta

Esta fase es la infraestructura: el sistema LaTeX, el modelo de contenido, el
motor de compilación, la herramienta y el migrador. Verificado compilando de
verdad las 15 salidas, y migrando el material real: 194 unidades tomadas al
azar de 51 categorías compilan sin un solo fallo, y el Tema 1 de 2025-2026
sale de la composición migrada en sus 7 perfiles.

El migrador (§8), los índices (§8.bis) y la aplicación están hechos sobre el
material real: las siete rutas, el editor multilingüe, la edición de
`unit.yaml` y el constructor de composiciones, con un clon local en escritorio
y el Worker en web. Lo siguiente, en orden:

1. **Compilar desde la interfaz** — en escritorio, con un clon en disco y
   LaTeX instalado, ya es posible: falta lanzar `didacta build` y mostrar el
   log y el PDF. En web no lo es, y la pantalla del documento no lo finge.
2. **Bibliografía** — 13 unidades citan y 5 usan `\cites` de biblatex, que hoy
   no compila. Hay que decidir dónde vive el `.bib` y con qué motor.
3. **Desplegar el Worker y Firebase** — el código está escrito y probado, pero
   `wrangler deploy`, el secreto del token y los proveedores de acceso piden
   credenciales que solo tiene el autor.
4. **Crear unidades desde la interfaz** — hoy se editan, traducen, reclasifican
   y recomponen las que hay; una nueva pide crear el directorio a mano.
5. **CI** — compilar en cada push, `didacta index --check`, publicar los PDF
   como artefactos.

Nada de eso cambia lo de aquí: el sistema LaTeX y el modelo de contenido son la
base sobre la que se apoya el resto.
