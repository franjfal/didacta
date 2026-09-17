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
│                 · page · colours · lang/XX.def (10 idiomas)  │
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

Didacta trae diez ficheros de idioma --`latex/lang/didacta-lang-XX.def`, con
las treinta y seis palabras que el paquete imprime por su cuenta-- y el
registro que los enumera vive en `engine/didacta/profiles.py`. Que un idioma
esté ahí no quiere decir que se use: **a cuáles se puede imprimir** y **a
cuáles se traduce aquí** son dos listas distintas. La segunda la declara cada
repositorio en su `settings.yaml` y cada asignatura en su `course.yaml`, y es
la que decide qué sale como pendiente. Confundirlas pone ocho «falta el
fichero» en cada unidad el día que se añade un idioma al registro.

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

## 6.bis El servidor MCP

`engine/didacta/mcp.py` expone el repositorio a un modelo de lenguaje: leer
asignaturas y unidades, buscar, escribir traducciones, comprobar y compilar un
documento. Se levanta con `didacta mcp`, por stdio --cuando lo lanza un
cliente-- o por HTTP en `127.0.0.1` --cuando lo lanza la aplicación, que es lo
que permite encenderlo desde Ajustes y enseñar qué hace--.

**Vive en el motor y no en la aplicación** porque el motor ya es la autoridad
sobre lo que hay en un repositorio, y esas respuestas no pueden depender de
quién pregunte. Un servidor que se las contestara a sí mismo sería un segundo
Didacta con sus propias ideas.

Tres reglas, y ninguna es negociable por conveniencia de una herramienta:

1. **Escribir hay que pedirlo**, repositorio por repositorio. `--repo` abre en
   solo lectura y `--write` para escribir; el defecto es no poder.
2. **Ninguna ruta sale de la raíz** del repositorio que la nombra. Lo que llega
   es texto de un modelo, y `../../../.ssh/id_rsa` es una ruta relativa
   perfectamente válida.
3. **No se toca git.** No hay herramienta que haga commit, ni que traiga ni que
   envíe. Lo escrito queda en disco y lo publica la persona viendo el diff. Un
   modelo que puede publicar es un modelo que puede publicar un error en el
   material de un curso que se está dando.

Tampoco lee credenciales: no hay token ni clave de traducción en ese proceso, y
`tests/test_mcp.py` comprueba que el módulo no importe nada por donde pudieran
entrar. Lo que no está en el proceso no se filtra por una herramienta mal
escrita.

El diario --una línea de JSON por llamada, por la salida de error-- es lo que
hace esto aceptable: un servidor que escribe en los ficheros de alguien sin que
se pueda ver qué toca no es una herramienta en la que haya motivo para confiar.

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
| D44 | Un commit local no necesita token; solo el envío | escribir en un clon que está en tu propio disco no necesita credencial, y exigirla habría roto el camino sin conexión, que es la razón de que el clon exista. Esto es sobre la **operación de git**, no sobre quién abre la aplicación: eso lo decide D64, y lo que pide es haber entrado alguna vez, no tener red ahora. El autor del commit sale de la sesión, o de la identidad de git del equipo cuando no se sabe |
| D45 | El token va en el entorno del proceso hijo, nunca en `argv` ni en `.git/config` | lo lee de ahí un credential helper de una línea. El atajo habitual —meterlo en la URL del remoto— lo deja escrito en un fichero dentro del clon, y `ps` enseña la línea de órdenes de cualquiera |
| D46 | El sandbox de macOS queda desactivado, y el entitlement explica por qué | una app en sandbox no puede ejecutar un binario fuera de su bundle ni volver a abrir una carpeta elegida en otra sesión, así que no puede llevar un clon. El coste es no poder ir a la Mac App Store, que para una herramienta que su autor instala en su propio equipo no es un coste |
| D47 | Con un clon, el catálogo se lee del clon | si la biblioteca leyera una copia servida por HTTP y el editor escribiera los ficheros del disco, las dos podrían discrepar. La fuente de la verdad en este equipo es el clon |
| D48 | Un botón de la barra de entornos es un interruptor, y la forma —macro o entorno— la elige él | sin quitar, la barra solo sabe añadir y quitar sigue siendo trabajo de teclado. Y `\onlyslides{…}` se rompe con un `\par`, con verbatim y con cualquier cambio de catcode: por eso existen `slidesonly` y compañía, y por eso la regla —línea en blanco o `\begin` dentro, entonces entorno— la aplica el botón y no la memoria de nadie |
| D49 | La vista del fuente lee los ficheros pegados, y cada trozo recuerda de dónde salió | «¿dónde cae el corte de esta diapositiva?» cruza los ficheros, y abrirlos de uno en uno no lo contesta. Una diapositiva abierta en una unidad y cerrada en la siguiente es una diapositiva, no dos errores; y sin el origen de cada trozo, una edición no sabe a qué fichero volver ni un aviso qué línea nombrar |
| D50 | Un `\begin` sin cerrar se denuncia con su fichero y su línea, antes de compilar | LaTeX lo denuncia contra la línea de la **composición** que incluye la unidad y saca un PDF de una página que parece correcto. El fichero y la línea de verdad solo los sabe quien lee los ficheros, y por eso el aviso avisa en lugar de bloquear: el fichero roto es justo el que hay que poder mirar |
| D51 | Guardar desde la vista comprueba todos los `sha` antes de escribir ninguno | escribir varios ficheros en un gesto no es una transacción —GitHub no las tiene—, pero fallar antes de tocar nada y fallar por la mitad no son lo mismo: lo segundo deja el trabajo repartido entre lo escrito y lo perdido |
| D52 | El título de un apartado no se teclea en la vista: abre el diálogo de los tres idiomas | vive en `year.yaml` y en tres idiomas (D23). Escrito donde se lee, se escribiría en uno solo, que es la cabecera en castellano sobre contenido en valenciano que D14 existe para evitar |
| D53 | Las columnas de colores se pintan también dentro del editor, midiendo el texto aparte con el mismo estilo y un strut forzado | una caja de texto no deja pintar entre sus líneas, así que la capa de guías mide por su cuenta y pinta por **línea visual**, que es lo que sigue cuadrando cuando una línea larga se parte. El strut forzado es lo que hace que las dos medidas coincidan; hay un test que compara la altura de las dos capas con una línea partida, porque si algún día dejan de coincidir no se ve leyendo el código |
| D54 | La sangría por entornos es de la vista y no se escribe nunca | no es un dato del fichero: la misma unidad está un nivel más adentro leída con su tema —porque cuelga de una diapositiva que abrió la unidad anterior— que leída sola. Guardarla sería escribir en el fichero algo que solo es cierto desde dónde se está mirando, y dos lecturas del mismo fichero pelearían por él en cada commit |
| D55 | En la vista del fuente no hay modo edición: cada fragmento es una caja de texto desde el principio, y la barra de entornos vive arriba | entrar y salir de un modo recomponía la lista bajo el ratón, así que el sitio que habías pulsado ya no estaba donde lo pulsaste; y la barra dentro del fragmento empujaba el texto al aparecer. El coste es que dentro de una caja no se puede sangrar línea a línea —tiene un solo margen izquierdo— así que el texto va como está en el fichero y la estructura la dicen las columnas del margen y el color del `\begin` y el `\end` |
| D56 | El LaTeX se pinta dentro de la caja de texto, y el troceador va aparte del color | un `.tex` se lee como código y se editaba como un bloc de notas. Sin modo edición el color no puede pintarse por encima: lo dice el propio controlador de la caja, y así lo tienen los tres sitios donde se escribe —la unidad, los campos de un problema y cada fragmento del tema—. El recorrido que dice qué es cada trozo está en el modelo y probado por su cuenta, porque sus fallos no se ven: un `\%` tomado por comentario apaga media línea y un `$` sin cerrar tiñe el resto del fichero |
| D64 | Las credenciales de traducción van al llavero, nunca a `shared_preferences` | las preferencias son un fichero de texto en disco --en macOS un `.plist` que se lee con `defaults read`-- y entran en cualquier copia de la carpeta de usuario |
| D65 | La clave viaja en una cabecera HTTP, no en la URL | los dos proveedores aceptan las dos formas; en la URL aparece en los registros de cualquier proxy por el que pase y en cualquier mensaje que imprima la dirección |
| D66 | `Credentials.toString` está escrito a mano y sin la clave | el que genera Dart la imprimiría, y un objeto así acaba en un `print` de depuración o dentro de una excepción sin que nadie lo decida |
| D61 | Un grado es una entidad con id en `degrees.yaml`, y la asignatura lo nombra con `degree_id:` | el `degree:` que ya había es el texto que se imprime en la portada; aceptar un id ahí convertiría un `degree: Grado en Matemáticas` real en una referencia a un grado llamado así, y rompería datos en silencio |
| D62 | Un grado que no declara ningún repositorio abierto no agrupa, y no es un error | misma regla que los temas: la asignatura sale entera y sin agrupar, así que nadie se queda sin ver su material por no tener el repositorio donde alguien puso un título |
| D63 | Con `degree_id` y `degree:` a la vez, manda el registro | con dos títulos para el mismo grado el que vale es el que comparten los repositorios; `check` dice cuáles llevan el texto de más para poder quitarlo |
| D58 | El servidor MCP vive en el motor, no en la aplicación | el motor ya decide qué es una unidad y qué cuenta como pendiente; un servidor con sus propias respuestas sería un segundo Didacta, y el día que discreparan nadie sabría cuál manda |
| D59 | La aplicación es dueña del proceso del servidor, por HTTP local | por stdio el dueño es el cliente, y entonces no hay interruptor en Ajustes ni forma de ver qué hace: nadie tendría el otro extremo de la tubería |
| D60 | Ninguna herramienta MCP toca git | escribir un fichero se ve en el diff y se deshace; publicar, no. Un modelo que publica puede publicar un error en el material de un curso que se está dando |
| D57 | El idioma del documento y el de un fragmento son dos cosas distintas | el del documento es el que se compilaría, y cambiarlo vuelve a elegir idioma en todas las unidades con la caída del motor (D13): la que no está traducida se sigue viendo en el suyo y lo dice. El de un fragmento es una excepción para esa unidad, que es lo que permite mirar una traducción sin cambiar de pantalla y lo que hace posible una hoja bilingüe |
| D58 | La identidad la da GitHub, no un servicio aparte | había tres cosas que cuadrar --quién eres para Firebase, qué permisos te da un `access.json` versionado, y un token pegado a mano para escribir-- y las tres contestaban a una sola pregunta que GitHub ya tenía contestada: quién puede escribir en este repositorio. Se entra con el *device flow*, que es el que usan las herramientas de terminal: sin secreto que guardar --un `client_id` es público y una aplicación de escritorio no puede esconder nada--, sin servidor que atienda una redirección, y con la contraseña tecleada en github.com y en ningún otro sitio |
| D59 | Varios repositorios a la vez, y un fichero es de uno solo | un profesor tiene el suyo, comparte otro con el departamento y da clase en una asignatura que se arma con los dos. Lo que se mezcla es la **asignatura**: los años y los temas de cada repositorio se juntan en una sola vista. Lo que no se mezcla nunca son los ficheros: un documento se compila contra la raíz del suyo y referencia unidades suyas, así que nada de lo que había --el índice por repositorio, `\DidactaContentRoot`, el motor-- necesita saber que hay más de uno |
| D60 | Dos repositorios pueden tener la misma ruta y son cosas distintas | `content/analysis/normed/definition` en dos sitios son dos unidades, no una con dos copias. Por eso la identidad de una unidad pasa a ser (repositorio, ruta) y cada pantalla pide la pasarela del repositorio del fichero que tiene en la mano. Escribir «en el repositorio» dejó de significar algo el día que hubo dos |
| D61 | Quien no tenga uno de los repositorios ve el resto | un índice que no carga se cuenta como un aviso y no como un fallo: lo que se enseña es lo que hay. Es lo que permite compartir una asignatura sin obligar a compartir todo lo demás, y lo que hace que quitar un repositorio de la lista no rompa ninguna pantalla |
| D62 | Cada repositorio tiene un color, y solo se enseña cuando hay más de uno | con dos abiertos, «¿esto dónde se está guardando?» es la pregunta que más se hace, y un color en la fila la contesta más barato que una ruta. Con uno solo no hay con qué confundirlo, así que no se marca nada: un adorno que siempre está deja de leerse |
| D63 | Crear algo pregunta en qué repositorio | crear una asignatura en el equivocado cuesta media tarde de deshacer --hay que mover ficheros y rehacer dos historiales-- y la aplicación no tiene forma de adivinarlo. Con un solo repositorio no pregunta: no hay nada que elegir |
| D64 | Sin sesión de GitHub no hay aplicación | el material vive en repositorios privados, cada cambio es un commit con el nombre de alguien detrás, y la propia aplicación se reparte a quien tiene acceso al repositorio de versiones: las tres cosas las autoriza GitHub, así que la sesión **es** el permiso y no un paso previo a pedirlo. Antes se abría igual sin entrar, y un clon ya puesto en el disco se podía editar sin que nadie hubiera demostrado ser nadie. Lo que se exige es **haber entrado**, no estar conectado: con la credencial guardada se abre sin red --un aula sin wifi no puede dejar a nadie sin sus diapositivas-- y solo se cierra la sesión cuando GitHub dice que esa credencial ya no vale |
| D65 | Solo se abren clones de GitHub a los que la cuenta llega, y se traen antes de modificarlos | un repositorio de contenido es la fuente de la verdad de un curso entero, y una copia que solo existe en un portátil es la copia que se pierde. Así que una carpeta cualquiera no se añade --lo que se escriba ahí no tiene a dónde ir-- y un clon del disco tampoco basta: que esté en esta máquina no dice quién lo puso, y se le pregunta a GitHub si esta cuenta llega a él. Al añadirlo se pone en hora, y antes de cada modificación se comprueba que lo sigue estando, con una **ventana de cinco minutos**: guardar es lo que más se hace y una llamada de red por guardado se nota justo ahí, mientras que para no editar sobre material viejo una comprobación de hace un momento vale igual que una de ahora. Quien decide si un fichero sin guardar estorba es git con `pull --ff-only`, no una regla propia: `generated/` deja el clon sucio casi siempre, y negarse a avanzar por eso habría convertido la garantía en un aviso permanente que nadie lee |
| D66 | El token va al llavero de siempre, no al «data protection keychain» | el moderno exige el entitlement `keychain-access-groups`, y ese exige firmar con un equipo de Apple. Didacta se firma ad hoc porque se instala a mano y no va a la Mac App Store (D46), así que no hay prefijo de equipo que poner: el device flow terminaba bien, GitHub devolvía el token, y guardarlo fallaba con `-34018: A required entitlement isn't present` en el último paso y sin decir de qué entitlement hablaba. El llavero de siempre no pide entitlement y guarda en el de inicio de sesión, que es donde alguien iría a buscarlo. Lo que se pierde --compartir la credencial entre aplicaciones del mismo equipo-- aquí no se usa: hay una aplicación |
| D67 | El historial de un fichero se lee desde dentro, y el diff lo calcula git | el material vive en git precisamente porque git sabe contestar «¿quién tocó esto, cuándo, y qué cambió?», y esa respuesta obligaba a salir a un terminal con la ruta en la cabeza. Es una **pestaña y no un panel** porque `git log --follow` sobre años de repositorio cuesta, y cobrárselo a quien venía a editar el castellano sería cobrarlo casi siempre por nada. El diff se le pide a git en lugar de comparar dos textos con el comparador propio: un commit puede renombrar, venir de una fusión o tocar un binario, y eso no se deduce de dos cadenas -- lo que se lee son las cabeceras `@@`, de donde salen los números de las dos columnas. Lo que se enseña de cada versión es el **fichero entero** con lo añadido y lo quitado marcado dentro, y no el recorte de tres líneas alrededor del cambio: el recorte contesta «¿qué tocó este commit?», que es la pregunta de quien revisa un cambio ajeno, y editando la pregunta es «¿cómo estaba esto en marzo?». Por eso el commit --autor, fecha exacta, mensaje, hash-- está detrás de un botón y no delante del texto: es información *sobre* el cambio. Y es de **solo lectura**: no hay «restaurar esta versión», porque deshacer tres meses de trabajo con un botón que se pulsa por error es un fallo del que no se vuelve |
| D68 | Se sangra al **guardar**, no al escribir, y con `latexindent` si lo hay | reindentar bajo los dedos de quien está en mitad de una línea le mueve el cursor y le rompe el deshacer; al guardar el fichero ya está cerrado como idea. La herramienta buena es la de CTAN y se prueba primero, pero es un script de Perl con cuatro dependencias que MacTeX no instala --`File::HomeDir`, `Log::Log4perl`, `Log::Dispatch`, `Unicode::GCString`--, así que en una máquina recién montada el fichero está y no arranca: parece disponible y no lo está. Detrás va un indentador propio que hace menos y siempre funciona, y la diferencia no se le cuenta a nadie porque no hay nada que hacer con ella. Lo que decide si se acepta su salida no es el código de salida: es que el texto sin espacios sea **el mismo** que entró, letra por letra. Un `latexindent` con la configuración de saltos de línea puesta pasaría el código de salida y habría reescrito el fichero de alguien |
| D69 | Sangrar se puede apagar, y se apaga **por idioma**, en el `unit.yaml` | hay ficheros a los que reescribirles el margen les cambia lo que imprimen --un entorno de código propio que la lista de verbatim no conoce-- o les rompe el historial --un `.tex` que genera otra herramienta y se regenera entero--, y material migrado con un `\begin` sin cerrar que LaTeX compila igual pero el contador de niveles no, así que sale todo corrido. Ninguno es frecuente y todos son reales, y en todos la respuesta es dejar el fichero en paz, no arreglar el indentador. Va en el `unit.yaml` y no en las preferencias porque es una propiedad **del fichero**: si hay que dejarlo quieto, hay que dejarlo quieto también cuando lo abra otra persona en otro ordenador. Y por idioma porque el motivo vive en un fichero concreto: que la versión castellana venga generada no dice nada de la inglesa escrita a mano |

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

### Bibliografía

Trece unidades citan y cinco usan `\cites`, que es biblatex. Durante la
migración no había nada a lo que apuntar, así que `\cite` caía en el de LaTeX
base —que imprime la clave y avisa— y `\cites` no existía: el análisis
bibliográfico de un tema no compilaba, y el error era «Undefined control
sequence» en la primera línea de la unidad, que no dice qué falta.

Lo que hay ahora:

* **El `.bib` vive en `shared/`**, uno por repositorio, y por convención se
  llama `bibliography.bib`. Uno y no uno por tema porque el mismo libro lo
  citan el tema 1 y el tema 6: dos listas son dos listas que se separan.
  `didacta.yaml` puede decir otro nombre, y nada más.
* **Llega a LaTeX como llega el contenido**: relativo a la raíz del
  repositorio, en `\DidactaBibliographyFile`, que el paquete compone con
  `\DidactaContentRoot`. Ningún documento contiene una ruta, así que el
  repositorio se clona donde sea.
* **biblatex con biber**, que lo ejecuta latexmk al ver el `.bcf`: el motor no
  sabe que biber existe. Estilo `alphabetic`, porque el material cita en prosa
  y «[Tao14, Sección 2.1]» se lee donde «[3, Sección 2.1]» obliga a ir al
  final a ver quién es el 3.
* **Solo cuando hay `.bib`.** Un repositorio sin fuentes no carga biblatex ni
  paga la pasada de biber: casi ningún tema cita. Si además cita, las citas
  salen `[?]` y el paquete avisa —pero `didacta check` lo ha dicho antes, con
  el nombre de la unidad y la clave, que es donde se arregla.
* **La lista de obras se imprime sola** al final, y solo si el documento citó.
  La alternativa era que cada documento la pidiera, y el que se olvidara
  saldría lleno de `[Abb15]` sin decir en ningún sitio quién es Abb15.

Lo que el sistema no puede saber es **qué edición** se usó al escribir las
citas, y las citas llevan capítulo y número de resultado. Eso lo dice el
`.bib`, y es del autor.

### Los temas de un curso

Un curso es una lista de documentos, y con un tema entero dentro --su teoría,
su práctica, su análisis bibliográfico, su marco histórico-- la lista deja de
contestar la pregunta que se le hace, que es **qué entra en el Tema 1**. Más
todavía cuando la mitad de ese tema vive en otro repositorio.

La forma que tiene, y el porqué de cada mitad:

* **El documento nombra** sus temas, en su entrada de `year.yaml`:
  `themes: [tema-1]`. Una lista, porque un apéndice puede servir a dos.
* **`themes.yaml` declara** el título y el orden, al lado del `year.yaml`.
* **Las dos mitades pueden estar en repositorios distintos**, y ese es el
  punto entero: la teoría declara los temas del curso y los problemas se
  limitan a nombrarlos.

La regla que lo hace seguro es una sola: **un tema que nadie declara no
agrupa**. El documento que lo nombra sale suelto, exactamente como salía antes
de que los temas existieran. Quien tenga solo el repositorio de problemas ve
todo su material; lo que no ve es la agrupación. No hay ningún caso en el que
falte un fichero y desaparezca contenido, que es la propiedad sin la cual esto
no se podría usar entre varias personas.

Por qué no es el `topic` de `taxonomy.yaml`, que se le parece: aquel clasifica
una unidad por área de conocimiento y lo comparten varias asignaturas; este
ordena un curso concreto, y su orden es el orden en que se da. Atar el segundo
al primero haría que renombrar un área reordenase una asignatura.

### Una interfaz, varias fuentes

Con dos repositorios abiertos, Didacta se comportaba como dos aplicaciones
pegadas: cada pantalla enseñaba lo de uno, y elegir repositorio parecía
navegar a otro sitio. No lo es. Son **dos fuentes de una misma biblioteca**, y
la asignatura que se arma con las dos es una asignatura, no dos.

Lo que eso obliga:

* **El filtro se aplica en un solo sitio**, el getter del catálogo de la
  sesión, por el que pasan todas las pantallas. Ninguna pregunta de qué
  repositorio es nada para decidir si lo enseña; esa pregunta es justo la que
  convierte una interfaz en dos.
* **Filtrar es una vista, no otra carga.** Volver al disco por marcar una
  casilla costaría medio segundo y perdería el resto mientras tanto.
* **Apagar enseña exactamente lo mismo que no tener.** Los temas de un
  repositorio apagado se van con él, así que sus documentos vuelven a salir
  sueltos. Por eso el filtro contesta «¿qué vería quien solo tiene esto?», que
  es la pregunta por la que se usa.
* **La composición se lee entera y se escribe donde toca.** Un año con
  documentos en dos repositorios abre los dos `year.yaml`: se ven juntos, y
  mover uno escribe en el fichero del suyo. Un commit por repositorio, porque
  son historiales distintos. Lo único que no cruza es el orden, que vive
  dentro de cada fichero.

Apagar no es quitar: el repositorio sigue abierto, sigue trayendo y sigue
guardando. Quitarlo está en Ajustes y es otra cosa.

### Las preferencias que viajan

Plegar el Tema 3 porque este año no se da es una decisión sobre **el
material**, no sobre esta máquina: quien la toma en el despacho espera
encontrarla en casa. La ruta del clon o dónde está TeX son lo contrario, y
sincronizarlas rompería la máquina de al lado.

Las primeras van a un repositorio de contenido, en
`.didacta/prefs/<login>.json`. Tres cosas que eso resuelve de golpe:

* **se sincroniza por donde ya se sincroniza todo** --clon, traer, enviar,
  commits con autor--, sin un servicio nuevo ni un permiso nuevo;
* **dos personas no se pisan**: el nombre del fichero es el login de GitHub de
  quien entró, así que un departamento comparte repositorio y cada uno tiene
  el suyo;
* **no hay un repositorio impuesto**: cada uno tiene los suyos y no coinciden,
  así que se elige en Ajustes. Sin elegir ninguno todo funciona en local, que
  es lo que hacían todas las preferencias hasta ahora.

Se escribe con espera de unos segundos: plegar tres temas seguidos son tres
clics y un commit. Y el JSON sale siempre con las claves en el mismo orden,
porque un fichero que cambia de forma en cada guardado da un diff que no dice
nada y un commit que no cambia nada.

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
repositorio directamente. Con varios repositorios abiertos, cada uno trae los
suyos y la aplicación los mezcla: las asignaturas se juntan, los ficheros no
(D59).

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

## 8.ter Cómo se reparte y cómo se actualiza

Didacta es **software libre bajo la GPL-3.0** y se publica desde este mismo
repositorio: los releases llevan los instaladores de los tres sistemas, y la
web de documentación --construida desde `web/` y servida en GitHub Pages-- es
la página de descarga.

```
   franjfal/didacta  (público)
          │
  «Publish Didacta Release»
          ├── compila macOS / Windows / Linux
          ├── publica el release aquí mismo
          └── dispara «Publish the documentation site»
                        └── capturas + página de descarga → Pages
```

Empezó de otra manera, y merece la pena dejar dicho por qué cambió. El código
era privado, así que las versiones vivían en un **segundo repositorio privado**
para poder dar la aplicación a quien no se le daba el código; quién podía
instalarla era quién tenía acceso allí, la publicación necesitaba el token de
una GitHub App instalada solo en él, y el actualizador descargaba con la
credencial de cada persona porque un repositorio privado no se lee de otra
manera.

Al abrir el código, esa separación dejó de separar nada. Se fueron con ella el
segundo repositorio, la GitHub App, sus dos secrets, la comprobación de
autorización que la aplicación hacía al entrar y el `Authorization:` de cada
petición del actualizador. Es la clase de simplificación que conviene apuntar:
**no se arregló nada; se quitó lo que ya no sujetaba nada.**

Las cuatro decisiones que sostienen lo demás:

1. **La versión la dice `app/pubspec.yaml` y nadie más.** De ahí salen el tag,
   el nombre de los artefactos, lo que la aplicación dice de sí misma y lo que
   declara el manifiesto. La aplicación lee el paquete construido y no una
   constante, porque una constante puede quedarse atrás de la compilación. Y
   ese número **lo sube el ciclo de publicación**, no una persona.

2. **El manifiesto guarda el `assetId` de cada artefacto, no una URL.** Ya no
   hace falta --con el repositorio público, la dirección de descarga es
   pública-- y se conserva igual: es la forma que funciona en los dos casos, y
   lo que se comprueba después es el SHA-256 y no de dónde vino.

3. **Un binario cuyo SHA-256 no cuadra no se instala nunca**, y además no se
   queda en el disco. Es la afirmación que sostiene el sistema entero.

4. **El programa que se actualiza no puede ser el que actualiza.** La
   sustitución la hace un script externo que espera a que Didacta cierre; la
   versión anterior se aparta y solo desaparece cuando la nueva está en su
   sitio y comprobada.

La entrada sigue siendo el **device flow** de la OAuth App (§D63), y sigue
haciendo falta, pero por lo que siempre fue de verdad: el material vive en
repositorios de GitHub. Lo que ya no hace es decidir si la aplicación se puede
usar.

Publicar una versión son tres pasos y ninguno es una orden en un terminal:
mirar qué número sale (`release.py next`), escribir esa sección del
`CHANGELOG.md`, y Actions → «Publish Didacta Release» → Run workflow.

El detalle entero --artefactos por sistema, el manifiesto, la firma, la web y
cómo hacer rollback-- está en
[`docs/DISTRIBUTION.md`](https://github.com/franjfal/didacta/blob/main/docs/DISTRIBUTION.md).

---

## 9. Lo que falta

Esta fase es la infraestructura: el sistema LaTeX, el modelo de contenido, el
motor de compilación, la herramienta y el migrador. Verificado compilando de
verdad las 15 salidas, y migrando el material real: 194 unidades tomadas al
azar de 51 categorías compilan sin un solo fallo, y el Tema 1 de 2025-2026
sale de la composición migrada en sus 7 perfiles.

El migrador (§8), los índices (§8.bis) y la aplicación están hechos sobre el
material real: las siete rutas, el editor multilingüe, la edición de
`unit.yaml` y el constructor de composiciones, sobre **clones locales de
varios repositorios a la vez**, con la identidad de GitHub (D58–D63). Lo
siguiente, en orden:

1. **Compilar desde la interfaz** — en escritorio, con un clon en disco y
   LaTeX instalado, ya es posible: falta lanzar `didacta build` y mostrar el
   log y el PDF. En web no lo es, y la pantalla del documento no lo finge.
4. **Crear unidades desde la interfaz** — hoy se editan, traducen, reclasifican
   y recomponen las que hay; una nueva pide crear el directorio a mano.
5. **CI** — compilar en cada push, `didacta index --check`, publicar los PDF
   como artefactos.

Nada de eso cambia lo de aquí: el sistema LaTeX y el modelo de contenido son la
base sobre la que se apoya el resto.
