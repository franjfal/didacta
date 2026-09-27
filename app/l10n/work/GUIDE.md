# Traducir la interfaz de Didacta

Didacta es una aplicación de escritorio (Flutter) para que el profesorado
universitario escriba, traduzca, compile (LaTeX) y reparta material docente.
Su interfaz está escrita en castellano. Cada texto es una clave: el texto en
castellano tal cual. Hay que dar su traducción al **valenciano** y al
**inglés**, o decir que **no es un texto de la interfaz**.

## Qué no se traduce nunca (valor `null`)

Lo que no lee una persona en la pantalla y cuyo contenido importa tal cual:
plantillas de ficheros (YAML, `.gitignore`, scripts de shell, workflows de
GitHub, README que se escribe en un repositorio), expresiones regulares,
identificadores, claves, nombres de fichero, textos que se mandan a un
programa o a una API, textos de ejemplo que se escriben dentro del material
(LaTeX de muestra). **Ante la duda, abre el fichero** (la ruta está en
`where`, relativa a `/Users/javier/didacta/app/lib/`) y mira cómo se usa. Si
se enseña en pantalla (un Text, un tooltip, un SnackBar, un diálogo, un
mensaje de error que ve la persona, un mensaje de commit propuesto que la
persona ve y puede cambiar), **sí** es interfaz.

## Reglas

- Los marcadores `{0}`, `{1}`… se conservan todos, exactamente, y pueden
  cambiar de orden si el idioma lo pide.
- Se conservan tal cual: órdenes de LaTeX (`\dpause`, `\begin{frame}`), código
  entre acentos graves, rutas y nombres de fichero, atajos (⌘K, Ctrl+K),
  nombres propios y marcas (GitHub, Didacta, Moodle, MathJax, LaTeX, Python,
  git, Azure, Google), identificadores de perfiles (`notes`, `slides`).
- Se conservan los saltos de línea (`\n`), los espacios del principio y del
  final, y la puntuación de la frase: el castellano usa `--` como raya dentro
  del texto y «» como comillas; en valenciano, lo mismo (`--` y «»); en inglés,
  `--` y comillas “ ”.
- El tono: el castellano habla de tú y en imperativo («Guarda», «Elige»). En
  valenciano, igual (tu: «Desa», «Tria»). En inglés, imperativo neutro
  («Save», «Choose»).
- **Valenciano**: el normativo de la Acadèmia Valenciana de la Llengua, el que
  se usa en la Universitat de València: «este/esta» o «aquest/aquesta»
  (preferible «aquest»), «seua», «meua», «servix» / «servisca» o «serveix»
  (preferible la forma valenciana: «servix», «obrir», «tancar», «eixir»),
  «desar» por guardar un fichero, «Configuració» por Ajustes. Con tildes
  valencianas («València», «també», «què»).
- **Inglés**: británico o americano neutro, frases cortas y claras, como una
  aplicación de escritorio bien escrita. Mayúscula solo al principio (sentence
  case) en botones y títulos, como en el castellano.
- Plurales: van como en castellano, cada forma en su clave.
- No añadas ni quites información. Si una frase en castellano es larga, la
  traducción también.

## Glosario (castellano → valenciano → inglés)

| castellano | valenciano | inglés |
|---|---|---|
| lección, unidad | lliçó, unitat | lesson, unit |
| asignatura | assignatura | subject |
| curso (una asignatura en un año) | curs | course |
| curso académico | curs acadèmic | academic year |
| tema | tema | topic |
| apartado / subapartado | apartat / subapartat | section / subsection |
| documento | document | document |
| composición | composició | composition |
| apuntes | apunts | notes |
| diapositivas | diapositives | slides |
| libro | llibre | book |
| hoja de problemas | full de problemes | problem sheet |
| examen | examen | exam |
| enunciado / resultado / solución, resolución | enunciat / resultat / solució, resolució | statement / answer / solution |
| profesor, copia del profesor | professor, còpia del professor | teacher, teacher's copy |
| alumno, estudiante | alumne, estudiant | student |
| repositorio | repositori | repository |
| copia (en tu ordenador), clon | còpia (al teu ordinador), clon | copy (on your computer), clone |
| guardar | desar | save |
| guardar en el historial (commit) | desar a l'historial | save to history |
| historial | historial | history |
| enviar (a GitHub) | enviar (a GitHub) | send (to GitHub) |
| traer (de GitHub) | portar (de GitHub) | get (from GitHub) |
| compilar, compilación | compilar, compilació | build, build (noun) |
| versión congelada, congelar | versió congelada, congelar | frozen version, freeze |
| traducción, traducir | traducció, traduir | translation, translate |
| original, traducida, revisada, sin revisar, desactualizada | original, traduïda, revisada, sense revisar, desactualitzada | original, translated, reviewed, not reviewed, outdated |
| plantilla | plantilla | template |
| bloque | bloc | block |
| snippet | snippet | snippet |
| vinculado, vinculación | vinculat, vinculació | linked, link |
| Ajustes | Configuració | Settings |
| Biblioteca | Biblioteca | Library |
| Asignaturas | Assignatures | Subjects |
| Traducción (la pantalla) | Traducció | Translation |
| interfaz Esencial / Completa | interfície Essencial / Completa | Essential / Full interface |
| idioma | llengua | language |
| motor (de Didacta) | motor | engine |
| índice (generated/) | índex | index |
| paleta de órdenes | paleta d'ordres | command palette |
| lector de pantalla | lector de pantalla | screen reader |
| texto alternativo | text alternatiu | alternative text |
| etiqueta (de una lección) | etiqueta | tag |
| prerrequisito | prerequisit | prerequisite |
| titulación | titulació | degree |
| repartir | repartir | hand out |
| aula virtual | aula virtual | virtual classroom |

## Lo que hay que entregar

Un fichero JSON, un objeto: cada clave del lote, tal cual, con
`["valenciano", "inglés"]` o `null`. Todas las claves del lote, ninguna más.
Escríbelo con Python (`json.dump(..., ensure_ascii=False, indent=1)`) para no
equivocarte con los escapes, y compruébalo al final: que es JSON válido, que
están todas las claves y que cada traducción tiene los mismos marcadores
`{n}` que su clave.
