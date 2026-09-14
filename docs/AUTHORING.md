# Escribir contenido en Didacta

Referencia de todo lo que se puede usar dentro de un fichero de contenido.

La regla que lo gobierna todo: **el contenido no sabe a qué salida va.** Se
escribe una vez y los interruptores deciden qué aparece en cada PDF.

---

## Un fichero de contenido

Sin preámbulo. Sin `\documentclass`. Sin `\begin{document}`. Solo el contenido:

```latex
\begin{frame}
\didactatitle{Definición y propiedades de los espacios normados}

La métrica usual en $\mathbb{R}$ es la distancia euclídea, dada por
\[ d(x,y) = |x-y|. \]

\onlynotes{%
  La idea detrás del concepto de norma es generalizar las propiedades más
  útiles de la distancia euclídea en $\mathbb{R}$.
}

\begin{definition}[Espacio normado]
Un \keyterm{espacio normado} es un par $(E, \|\cdot\|)$ tal que...
\end{definition}
\end{frame}
```

Ese fichero produce, sin cambiar una línea:

| Perfil | Qué sale |
|---|---|
| `slides` | una diapositiva con la definición en caja verde |
| `notes` | una subsección con el párrafo de `\onlynotes` incluido |
| `notes-teacher` | lo mismo, más las notas didácticas |
| `handout` | una hoja de referencia compacta |

`\begin{frame}` funciona en prosa porque los perfiles de documento cargan
`beamerarticle`. Es lo que permite un único origen.

---

## Contenido condicional

Lo que no se envuelve aparece **en todas** las salidas.

| Comando | Aparece en |
|---|---|
| `\onlyslides{…}` | solo diapositivas |
| `\onlynotes{…}` | solo documentos |
| `\onlyteacher{…}` | solo copias del profesor |
| `\onlystudent{…}` | todo excepto copias del profesor |
| `\onlyfull{…}` | solo con detalle completo (no en un examen) |
| `\onlybrief{…}` | solo con detalle reducido |

Formas de entorno, para cuerpos con `\par`, listas o `verbatim` — que es donde
la forma de comando se rompe:

```latex
\begin{notesonly}
Un párrafo entero.

Y otro, con \begin{itemize}\item listas \end{itemize} dentro.
\end{notesonly}
```

`slidesonly`, `teacheronly`, `studentonly`, `fullonly` funcionan igual.

### Combinaciones

| Comando | Aparece en |
|---|---|
| `\slidesandteacher{…}` | diapositivas o copia del profesor |
| `\notesandteacher{…}` | documentos o copia del profesor |
| `\bymedium{corto}{largo}` | la primera versión en diapositivas, la segunda en prosa |

`\bymedium` suele ser mejor que esconder una versión: casi siempre lo que se
quiere no es *ocultar* la frase larga, sino *acortarla* para la diapositiva.

### Alias heredados

`\onlybook{…}` sigue funcionando: es el nombre antiguo de `\onlynotes`. Los
apuntes que se migran lo usan en 429 ficheros, así que se conserva.

---

## Títulos

```latex
\didactatitle{Métrica inducida}
```

En diapositivas es el `\frametitle`. En prosa es una `\subsection` — que es lo
que un lector necesita para navegar y lo que alimenta el índice.

Escribir `\frametitle` directamente también funciona, pero en prosa desaparece:
el lector se queda sin encabezado. Usa `\didactatitle`.

---

## Pausas

```latex
Primera parte.
\dpause
Segunda parte.
```

`\dpause` revela en `slides`. En `slides-flat`, en cualquier documento y en un
handout no hace nada — sin error, y sin generar una página extra.

`\pause` a secas también funciona (`beamerarticle` lo neutraliza en prosa),
pero `\dpause` es explícito sobre que la pausa es opcional.

---

## Entornos de teorema

Un solo conjunto de nombres. El aspecto lo decide el medio: caja rellena con
barra de título en diapositivas, filete al margen que parte entre páginas en
prosa.

| Entorno | es | va | en |
|---|---|---|---|
| `theorem` | Teorema | Teorema | Theorem |
| `definition` | Definición | Definició | Definition |
| `proposition` | Proposición | Proposició | Proposition |
| `lemma` | Lema | Lema | Lemma |
| `corollary` | Corolario | Corol·lari | Corollary |
| `property` | Propiedad | Propietat | Property |
| `example` | Ejemplo | Exemple | Example |
| `question` | Cuestión | Questió | Question |
| `remark` | Nota | Nota | Remark |
| `axiom` | Axioma | Axioma | Axiom |
| `algorithm` | Algoritmo | Algoritme | Algorithm |
| `notation` | Notación | Notació | Notation |

```latex
\begin{theorem}[Teorema fundamental]
Enunciado.
\end{theorem}

\begin{definition*}          % sin numerar
Para una redefinición o un aparte.
\end{definition*}
```

**Un solo contador compartido.** Definición 1.1, Teorema 1.2, Ejemplo 1.3.
Contadores independientes producen un Teorema 2.3 seguido de una Definición
2.1, que rompe cualquier referencia cruzada que el lector intente seguir.

El color agrupa por papel y no cambia entre salidas: azul lo que se demuestra
o se asume, gris lo que se define, verde lo que se deduce, ámbar lo que se
trabaja, violeta lo que conviene destacar.

### Demostraciones

```latex
\onlynotes{%
\begin{proof}
Las tres propiedades se siguen de los axiomas...
\end{proof}
}
```

Una demostración casi nunca cabe en una diapositiva, así que envolverla en
`\onlynotes` es el caso normal. El nombre («Demostración», «Demostració»,
«Proof») viene del idioma.

### Alias heredados

`ndefn`, `nthrm`, `nprop`, `npro`, `nlem`, `ncor`, `nex`, `nques`, `nrem`,
`naxioma`, `recipe` y las versiones sin `n` (`defn`, `thrm`, …) apuntan todos al
entorno correspondiente. En el sistema antiguo había dos juegos de nombres —
uno con caja y otro sin ella — porque el contenido tenía que saber a qué salida
iba. En Didacta no: migrar es renombrar, no reescribir.

---

## Fórmulas destacadas

```latex
\begin{keyformula}
  \|f\| = \max_{x \in [a,b]} |f(x)|
\end{keyformula}
```

Para la ecuación de la diapositiva que importa. (`nformula` es el alias antiguo.)

---

## Problemas

Enunciado, indicación, respuesta, solución y corrección **en un solo fichero**.
Cada nivel aparece únicamente en el perfil que le toca.

```latex
\begin{exercise}[Axiomas de norma]
Decide cuáles de las siguientes funciones son normas.

\begin{parts}
  \item $f(x_1,x_2) = |x_1| + 2|x_2|$
  \item $f(x_1,x_2) = |x_1| - |x_2|$
\end{parts}

\dmarks{4}

\begin{hint}
Para descartar una candidata basta un contraejemplo de un solo axioma.
\end{hint}

\begin{answer}
(i) sí; (ii) no, falla la positividad.
\end{answer}

\begin{solution}
(i) Es la norma 1 con pesos: los tres axiomas se comprueban término a término.
(ii) $f(1,1) = 0$ con $(1,1) \neq 0$.
\end{solution}

\begin{marking}
Un punto por apartado. Se exige nombrar el axioma que falla; decir solo «no es
norma» vale medio punto.
\end{marking}
\end{exercise}
```

Qué muestra cada perfil:

| | `hint` | `answer` | `solution` | `marking` |
|---|:---:|:---:|:---:|:---:|
| `problems` · alumnos, solo enunciados | ✓ | | | |
| `problems-answers` · alumnos, con resultados | ✓ | ✓ | | |
| `problems-teacher` · profesor, todo | ✓ | ✓ | ✓ | ✓ |
| `exam` | | | | |
| `exam-marking` | | ✓ | ✓ | ✓ |

Tres versiones y no cuatro: la que lo enseña todo es la del profesor. Un
guion de prácticas tiene las mismas tres, con `handout`, `handout-answers` y
`handout-teacher`.

Los tres niveles son distintos a propósito:

- **`answer`** es el resultado. `f'(x) = 2x`. Una línea. Para que el alumno
  compruebe si acertó.
- **`solution`** es cómo se llega. El desarrollo.
- **`marking`** es qué buscar al corregir y cuánto vale cada parte.

En el sistema antiguo solo existía uno de los tres (`shownto{solution}`) y la
capa de respuesta corta nunca se llegó a escribir, aunque la infraestructura
estaba. Aquí los tres existen desde el principio.

### Otros comandos de problemas

| Comando | Efecto |
|---|---|
| `\begin{exercise*}` | sin numerar |
| `\begin{parts}` … `\item` | apartados (i), (ii), (iii) |
| `\dmarks{4}` | puntuación, solo en perfiles de examen |
| `\answerspace{4cm}` | espacio para responder, solo en examen |

`\dmarks`, no `\marks`: `\marks` es una primitiva de TeX y sobreescribirla
rompe las rutinas de salida de una forma que aparece mucho después y cuesta
mucho rastrear.

### Alias heredados

`\begin{ej}` es `\begin{exercise}`. `\begin{shownto}{solution}` es
`\begin{solution}`, y `\begin{shownto}{profesor}` es `\begin{marking}`.

---

## El canal del profesor

Es un canal de verdad, no un sinónimo de «los apuntes»:

```latex
\begin{teaching}[Ritmo]
Quince minutos. Merece la pena detenerse en la homogeneidad: casi nadie ve por
qué hace falta el valor absoluto hasta que se les pide $\lambda = -1$.
\end{teaching}

\begin{commonmistake}
Escriben $\|\lambda x\| = \lambda\|x\|$ y pierden el valor absoluto. Sale
sistemáticamente en el primer parcial.
\end{commonmistake}

\timing{25 min}
```

Solo aparece en `slides-teacher`, `notes-teacher`, `problems-teacher` y
`exam-marking`. Con un filete rojo y el pie de página marcado, para que sea
imposible confundir la copia que tienes en la mano.

En el sistema antiguo `\onlyteacher` estaba definido **igual** que `\onlybook`,
así que no distinguía nada: no había forma de escribir una nota que llegara al
profesor y no al alumno.

---

## Diseño de la unidad

```latex
\begin{objectives}
\begin{itemize}
  \item Reconocer los tres axiomas de norma
  \item Distinguir norma de métrica
\end{itemize}
\end{objectives}

\begin{prerequisites}
Espacios vectoriales; valor absoluto en $\mathbb{R}$.
\end{prerequisites}

\begin{summary}
Una norma mide longitud; toda norma induce una métrica; el recíproco es falso.
\end{summary}
```

No son decoración: son lo que hace que una unidad se pueda reutilizar con
seguridad, porque dicen qué asume y qué entrega. `didacta check` avisa cuando
un prerrequisito apunta a una unidad que no existe.

---

## Figuras

Van en un directorio `figures/` dentro de la unidad, y se referencian desde
ahí:

```
content/trigonometria/tales/teorema-tales/
├── es.tex
├── unit.yaml
└── figures/
    ├── Tales.png
    └── corte1.png
```

```latex
\includegraphics[width=.85\textwidth]{figures/corte1.png}
```

La figura viaja con la unidad: moverla, renombrarla o reutilizarla en otra
asignatura no rompe la referencia. Es lo contrario del sistema anterior, donde
un `img/triangles.pdf` apuntaba al directorio del fichero que hacía el
`\import`, así que la misma línea encontraba la figura o no según desde dónde
se compilara.

---

## Otros

| Comando | Para |
|---|---|
| `\keyterm{norma}` | el término que se está definiendo (negrita) |
| `\hl{esto}` | resaltado |
| `\didactaprofilebanner` | imprime los ejes activos — útil cuando una compilación ha salido raro |

---

## Composiciones

Un documento es una lista de unidades:

```latex
\input{didacta-bootstrap}
\usepackage{didacta}

\DidactaDocument{Preliminars: espais normats}

\begin{document}
\DidactaTitlePage
\DidactaContents

\section{Espais normats}
\DidactaUnit{analysis/normed-spaces/definition}
\DidactaUnit{analysis/normed-spaces/induced-metric}
\end{document}
```

### Los apartados van en `year.yaml`

El `\section` de arriba funciona, y para compilar a mano desde el editor es lo
más cómodo. Pero está en un idioma, y el mismo documento se compila en tres:

```yaml
structure:
  - section:
      va: Espais normats
      es: Espacios normados
      en: Normed spaces
  - unit: analysis/normed-spaces/definition
  - unit: analysis/normed-spaces/induced-metric
```

Esa es también la razón por la que un apartado no va **dentro** de una unidad:
el encabezado viajaría con ella a cada asignatura que la reutilice, en el
idioma en que se escribió y en la posición en que se dejó.

| Comando | Incluye |
|---|---|
| `\DidactaUnit{cat/tema/unidad}` | de `content/` |
| `\DidactaProblem{cat/tema/unidad}` | de `problems/` |
| `\DidactaUnit[en]{…}` | esa unidad en inglés, sea cual sea el idioma del documento |
| `\DidactaInclude{ruta/fichero}` | un `.tex` suelto, sin separar por idiomas |

**Sin `../../../../`.** Las referencias se resuelven contra la raíz del
repositorio, que la herramienta inyecta. Mover una carpeta no rompe nada.

`\DidactaUnit[en]{…}` es lo que permite una hoja bilingüe sin duplicar la
composición.

### Si falta una traducción

Didacta usa la de referencia y avisa:

```
Package didacta Warning: No `va' version of `analysis/normed-spaces/induced-metric';
using `es' instead on input line 34.
```

Una diapositiva sin traducir es mucho más útil que un hueco en la presentación.
Si no existe en ningún idioma, sale un marcador visible en el PDF: mejor
enterarse al revisar que delante de la clase.

### Metadatos

No los escribas en el `.tex`. Van en `course.yaml` y `year.yaml`, por idioma, y
Didacta los inyecta al compilar. Lo que declares en el fichero es solo un
respaldo para que compilar a mano desde el editor siga dando un documento con
título.

Es lo que evita que una cabecera en valenciano acabe en una hoja en castellano.

---

## Compilar

Desde el editor, directamente, con SyncTeX funcionando:

```bash
pdflatex master.tex                       # los apuntes, en el idioma por defecto
```

Un perfil concreto:

```bash
pdflatex "\def\DidactaProfile{slides}\def\DidactaLanguage{va}\input{master}"
```

O con la herramienta, que se encarga de `TEXINPUTS`, del directorio de salida,
de los metadatos y de las pasadas:

```bash
didacta build tema-1                      # todas las salidas del documento
didacta build tema-1 -p slides -l va
didacta build --all
```

---

## Dependencias

Todo lo que Didacta usa está en CTAN: una TeX Live estándar basta.

El sistema anterior necesitaba seis `.sty` no-CTAN (`beamerthemeTorino`,
`beamercolorthemechameleon`, `beamerouterthemedecolines`,
`beamerinnerthemefancy`, `boiboites`, `multiaudience`) y una fuente empaquetada
en el propio repositorio. Didacta no depende de ninguno: los teoremas con caja
los hace `tcolorbox` y las audiencias están implementadas directamente.
