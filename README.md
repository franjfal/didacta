# Didacta

Plataforma de contenido docente. Se escribe el material una vez y se genera
cada PDF que haga falta: diapositivas, apuntes, handouts, hojas de problemas,
copias del profesor y exámenes, en castellano, valenciano e inglés.

Esta carpeta es la plataforma. Se moverá a su propio repositorio; el material
docente vivirá en repositorios de contenido separados que Didacta compila.

---

## El principio

```
EL CONTENIDO SE ESCRIBE UNA VEZ.
LAS ASIGNATURAS SON COMPOSICIONES.
LOS IDIOMAS SON VARIANTES DE LA MISMA ENTIDAD.
LAS SALIDAS SE GENERAN.
```

Un fichero de contenido no sabe a qué salida va. Los interruptores deciden:

```latex
\begin{frame}
\didactatitle{Definición de espacio normado}

La métrica usual en $\mathbb{R}$ es $d(x,y) = |x-y|$.

\onlynotes{La idea es generalizar las propiedades útiles de esa distancia.}

\begin{definition}[Espacio normado]
Un par $(E, \|\cdot\|)$ tal que...
\end{definition}

\begin{teaching}[Ritmo]
Quince minutos. Detente en la homogeneidad.
\end{teaching}
\end{frame}
```

Y de ese único fichero:

```bash
didacta build tema-1
  ok  tema-1  slides              va   7 pp
  ok  tema-1  slides-flat         va   6 pp
  ok  tema-1  notes               va   4 pp
  ok  tema-1  slides-teacher      va   6 pp
  ok  tema-1  notes-teacher       va   4 pp
```

---

## Las 15 salidas

```
$ didacta profiles
```

| id | clase | medio | soluciones | audiencia | pausas |
|---|---|---|---|---|---|
| `slides` | beamer | diapositivas | — | alumno | sí |
| `slides-flat` | beamer | diapositivas | — | alumno | no |
| `slides-teacher` | beamer | diapositivas | todas | profesor | no |
| `notes` | article | documento | — | alumno | — |
| `notes-solutions` | article | documento | todas | alumno | — |
| `notes-teacher` | article | documento | todas | profesor | — |
| `book` | book | documento | — | alumno | — |
| `handout` | article | documento | — | alumno | — |
| `handout-answers` | article | documento | resultados | alumno | — |
| `handout-teacher` | article | documento | todas | profesor | — |
| `problems` | article | documento | — | alumno | — |
| `problems-answers` | article | documento | resultados | alumno | — |
| `problems-teacher` | article | documento | todas | profesor | — |
| `exam` | article | documento | — | alumno | — |
| `exam-marking` | article | documento | todas | profesor | — |

Un perfil no es una plantilla: es un preajuste sobre cinco ejes
independientes — medio, detalle, audiencia, soluciones y pausas. Añadir una
salida es **una línea** en `latex/didacta-profiles.tex`, y nada más en el
sistema necesita saberlo.

---

## Las tres versiones de un problema

Un problema es un fichero con tres campos —enunciado, resultado y solución
detallada— y tres versiones que los revelan por niveles: la versión *n*
enseña los campos 1 a *n*. La del profesor añade encima la corrección.

| | `hint` | `answer` | `solution` | `marking` |
|---|:---:|:---:|:---:|:---:|
| `problems` · alumnos, solo enunciados | ✓ | | | |
| `problems-answers` · alumnos, con resultados | ✓ | ✓ | | |
| `problems-teacher` · profesor, todo | ✓ | ✓ | ✓ | ✓ |
| `exam` | | | | |

Lo mismo, con `handout-*`, para un guion de prácticas: un documento con
ejercicios dentro se reparte, se corrige y se entrega igual venga de donde
venga.

- **`answer`** el resultado, una línea, para que el alumno se corrija
- **`solution`** el desarrollo
- **`marking`** qué buscar al corregir y cuánto vale cada parte

---

## Cómo se organiza el contenido

```
<repositorio-de-contenido>/
  didacta.yaml                        ajustes del repositorio
  content/<área>/<tema>/<unidad>/
      unit.yaml                       título, etiquetas, idiomas, estado
      es.tex  va.tex  en.tex          el mismo contenido, un fichero por idioma
      figures/                        sus imágenes
  problems/<área>/<tema>/<unidad>/
      unit.yaml
      es.tex  va.tex  en.tex          enunciado + respuesta + solución + corrección
  courses/<asignatura>/
      course.yaml                     lo que no cambia entre cursos
      <curso>/
        year.yaml                     selección, orden, estructura
        <documento>.tex               la composición
```

**Una unidad es un directorio.** Sus idiomas, sus metadatos y sus figuras se
mueven juntos.

**El idioma es el nombre del fichero**, no una convención: `va.tex`, no
`03VAL-espacios-normados.tex`. El ordinal que antes llevaba el orden vive ahora
en la composición, que es donde el orden pertenece — reordenar un tema ya no
implica renombrar ficheros.

**Un curso guarda selección y orden, nunca contenido.** Duplicar un curso copia
un fichero de estructura:

```bash
didacta new year am-iii 2026-2027
```

---

## Empezar

```bash
# Qué hay en este repositorio
didacta status

# La biblioteca, con el estado de traducción de cada unidad
didacta units
didacta units --category analysis --missing va

# Qué falta traducir, ordenado por cuánto se usa cada unidad
didacta translations

# Validar: referencias que no resuelven, perfiles inexistentes,
# documentos que compilan en un idioma que su contenido no tiene
didacta check

# Compilar
didacta build tema-1
didacta build tema-1 -p slides -l va
didacta build --all
didacta build --all --list          # qué haría, sin hacerlo

# Crear
didacta new unit analysis/normed-spaces/dual-space
didacta new unit analysis/series/convergence --kind problem
didacta new year am-iii 2026-2027

# El catálogo que lee la interfaz. Datos derivados: regenerarlos da los
# mismos bytes, y --check falla si están desincronizados (para CI)
didacta index
didacta index --check

# Traer material del sistema LaTeX anterior. Sin --apply no escribe nada,
# y no toca el repositorio de origen en ningún caso
didacta migrate ~/Teaching ~/didacta-content
didacta migrate ~/Teaching ~/didacta-content --year 2025-2026 --apply

# --verify compila además cada documento migrado y lista en el informe los
# que no salen, con fichero, línea y la macro culpable
didacta migrate ~/Teaching ~/didacta-content --year 2025-2026 --apply --verify
```

Se ejecuta desde cualquier sitio dentro de un repositorio de contenido: la raíz
se localiza subiendo hasta encontrar `didacta.yaml`, como hace git con `.git`.

Hay un repositorio de ejemplo completo en [`examples/demo-course`](examples/demo-course):

```bash
cd examples/demo-course
../../cli/didacta status
../../cli/didacta build --all
```

---

## La aplicación

Flutter Web, en [`app/`](app). La biblioteca ya funciona sobre el material
real: las 2147 unidades con filtros por árbol, categoría, tipo, etiqueta y
estado de traducción, búsqueda por palabras y cuatro órdenes.

```bash
didacta index                      # en el repositorio de contenido
cd app && flutter run -d chrome --dart-define=DIDACTA_INDEX=/ruta/generated
```

No habla con el repositorio: lee tres JSON estáticos que pesan **77 KB
comprimidos** para la biblioteca entera, así que se puede publicar en GitHub
Pages sin ningún servidor detrás.

Dos cosas que muestra y que el repositorio no puede contestar solo:

- **en qué documentos se usa cada unidad** — la respuesta a «¿puedo cambiar
  esto?», que exige recorrer todas las composiciones;
- **qué unidades no usa nadie** — después de una migración, material que llegó
  y no se está dando.

Lo que falta: editar, componer y compilar desde la interfaz. Los tres
necesitan `api/`, porque escribir en el repositorio exige identidad y un token
que un navegador no puede guardar.

## Qué hay aquí

```
didacta/
├── latex/                  el sistema LaTeX
│   ├── didacta-bootstrap.tex   elige la clase según el perfil
│   ├── didacta-profiles.tex    ← el registro de salidas
│   ├── didacta.sty             el paquete principal
│   ├── didacta-formats.sty     \onlyslides / \onlynotes / \onlyteacher
│   ├── didacta-theorems.sty    teoremas, dos aspectos según el medio
│   ├── didacta-problems.sty    ejercicios y los cuatro niveles
│   ├── didacta-theme.sty       el tema beamer
│   ├── didacta-page.sty        maquetación de documento
│   ├── didacta-colours.sty     la paleta
│   └── lang/                   es · va · en
├── engine/didacta/         Python: modelo, perfiles, compilación
├── cli/didacta             la herramienta
├── examples/demo-course/   repositorio de contenido de ejemplo
├── docs/
│   ├── AUTHORING.md        ← referencia de escritura
│   └── ...
├── tests/
├── app/  api/  schemas/    (siguiente fase: la interfaz web)
└── ARCHITECTURE.md
```

---

## Documentación

- **[docs/AUTHORING.md](docs/AUTHORING.md)** — todo lo que se puede escribir en
  un fichero de contenido. Es la referencia que se usa a diario.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — el diseño y por qué está así.
- **[latex/didacta-profiles.tex](latex/didacta-profiles.tex)** — las salidas,
  documentadas en el propio registro.

---

## Requisitos

| | |
|---|---|
| TeX Live | 2023 o posterior, con `latexmk` |
| Python | 3.9 o posterior, **sin dependencias** |

Todos los paquetes LaTeX que Didacta usa están en CTAN: una TeX Live estándar
basta, sin instalar nada más. El sistema anterior arrastraba seis `.sty`
no-CTAN y una fuente empaquetada en el repositorio, lo que hacía imposible
compilar en una máquina limpia.

Sirve cualquiera de las tres, y la aplicación **no obliga a configurar nada**:
busca `latexmk` donde cada una se instala.

| | |
|---|---|
| macOS | MacTeX, o BasicTeX si importa el disco (`brew install --cask basictex`) |
| Windows | TeX Live o MiKTeX |
| Linux | el `texlive` de la distribución |
| las tres | [TinyTeX](https://yihui.org/tinytex/), ~100 MB y ampliable con `tlmgr` |

Didacta **no lleva una distribución dentro**, y es deliberado: la completa son
varios gigas, la versión de cada paquete la tiene que poder elegir quien
compila, y las actualizaciones de CTAN no pueden depender de que se publique
una versión de esta aplicación. Lo que sí hace es encontrar la que haya y
decir dónde ha mirado cuando no encuentra ninguna; si está en un sitio raro,
se le dice en Ajustes.

Que la aplicación de escritorio busque en lugar de preguntar al PATH no es un
lujo: **una app no hereda el PATH del terminal**. A una aplicación lanzada
desde el Finder launchd le da `/usr/bin:/bin:/usr/sbin:/sbin`, y en macOS
`latexmk` vive en `/Library/TeX/texbin`, que entra en el PATH por
`/etc/paths.d/TeX` --que solo lee un shell de login--. Didacta decía
«necesita una distribución de TeX» con TeX Live 2026 instalada y compilando
en el terminal.

PyYAML se usa si está instalado; si no, el motor trae su propio lector del
subconjunto que los esquemas necesitan. Es deliberado: la plataforma tiene que
funcionar en un runner de CI sin un paso de `pip`.

---

## Estado

Lo que funciona hoy, verificado compilando de verdad:

- las 15 salidas, desde un único origen;
- los tres idiomas, con nombres de entorno y cadenas fijas traducidos;
- los cuatro niveles de un problema, cada uno en su perfil;
- el canal del profesor, distinto del canal de apuntes;
- respaldo al idioma de referencia cuando falta una traducción, con aviso;
- inyección de metadatos desde `course.yaml` y `year.yaml`;
- compilación fuera del árbol, con SyncTeX;
- `didacta status | units | translations | check | build | new | migrate | index`;
- la biblioteca de la aplicación, sobre el material migrado de verdad.

La migración del sistema anterior está hecha y medida sobre el material real:
2147 unidades a partir de 2438 ficheros, y 784 documentos en 17 asignaturas y
30 cursos académicos, con 6137 referencias a unidades de las que 4 no
resuelven. De una muestra de 194 unidades migradas repartidas por las 51
categorías, las 194 compilan; el Tema 1 de 2025-2026 sale de su composición
migrada en los 7 perfiles que le corresponden.

Dos cosas que la migración no hace: escribir en el repositorio de origen —
comprobado con un test que compara cada fichero seguido por git antes y después
— e inventar los metadatos que el material anterior no guardaba.
`MIGRATION-REPORT.md` dice qué falta y dónde.

253 tests de Python y 33 de Dart.

Siguiente fase: la bibliografía (5 unidades no compilan sin biblatex) y `api/`,
que es lo que bloquea editar y compilar desde la interfaz.
