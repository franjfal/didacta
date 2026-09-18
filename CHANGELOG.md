# Cambios

Lo que cambia en cada versión de Didacta, escrito a mano.

**A mano y no generado desde los commits**, a propósito. Un changelog sacado
de `git log` dice «arregla el test de la barra lateral» y «wip», que es
información para quien escribió el código y ruido para quien lo usa. Lo que
alguien necesita saber antes de actualizar es qué va a poder hacer que antes
no podía, y qué ha dejado de fallar.

La sección de cada versión es **lo que se publica como notas del release** y
lo que se enseña dentro de la aplicación cuando ofrece actualizar. Así que se
escribe pensando en que se va a leer en un diálogo, no en un repositorio:
frases cortas, sin nombres de fichero y sin números de issue.

El formato lo lee `packaging/release.py`, y es el mínimo que hace falta:

```markdown
## 1.4.2 — 2026-09-15

- Lo nuevo…
- Lo mejorado…
- Lo corregido…
```

El encabezado tiene que empezar por `## ` seguido de la versión. La fecha
detrás es opcional y no se usa para nada más que para leerla aquí.

**Qué versión.** La que asigne la próxima publicación, que sube la mediana por
su cuenta. La dice:

```
python3 packaging/release.py next
```

Sin esa sección no se publica: el workflow se para antes de compilar nada.

---

## 0.1.0 — 2026-09-17

- **Teoría y problemas ya no están escritos en el código.** Eran los dos
  bloques que había y no se podían ni renombrar ni añadir. Ahora los declara
  cada repositorio, con un nombre por idioma, así que quien parta su
  asignatura en teoría, problemas y prácticas de ordenador ve tres en la
  biblioteca, en el filtro y al clasificar una lección. Se gestionan desde
  Ajustes → Bloques: crear, renombrar y decir en qué repositorios se declara
  cada uno.
- Renombrar un bloque es cambiar una línea: **no mueve ningún fichero y no
  rompe ninguna referencia**, porque lo que guarda cada lección es el id y lo
  que se lee es el nombre. Es lo mismo que ya pasaba con los temas.
- **Quitar un bloque pregunta antes qué pasa con sus lecciones**, y no se
  puede saltar: o se mueven a otro --un solo commit por repositorio, aunque
  sean noventa ficheros-- o se quedan sin bloque declarado, y entonces salen
  en Entre repositorios para arreglarlas cuando toque. Lo que no puede pasar
  es que noventa lecciones queden clasificadas en ninguna parte sin que nadie
  lo haya decidido.
- **Entre repositorios tiene una comprobación más: las lecciones sin bloque.**
  Una lección que nombra un bloque que ningún repositorio abierto declara se
  sigue viendo entera --el bloque sale por su id-- pero casi siempre significa
  que falta abrir un repositorio, o que alguien quitó el bloque. Las dos
  salidas están ahí. Y si dos repositorios le dan nombres distintos al mismo
  bloque, se iguala desde donde ya se igualaban los de una asignatura.
- **Dentro de un curso hay un filtro de bloque**, discreto, encima de la lista
  de documentos, para quedarse con la teoría o con las prácticas. Solo aparece
  cuando el curso tiene de más de uno.
- **Nada de esto cambia lo que ya tenías.** Un repositorio que no declara
  ningún bloque sigue teniendo teoría y problemas, con su nombre y en su
  orden, porque Didacta los conoce sin que nadie los escriba.

- **El selector de idioma de arriba ofrecía los diez que Didacta sabe
  imprimir**, no los que hay en tu material. Elegir uno al que ningún
  repositorio traduce dejaba la pantalla entera enseñando el texto de reserva,
  y desde ahí no había nada que hacer. Ahora ofrece los que hay, y lo mismo el
  menú Idioma y el selector de la biblioteca.
- **Se pueden editar los idiomas de cada repositorio**, en Ajustes → Idiomas.
  Era lo único que quedaba que había que hacer abriendo el `didacta.yaml` a
  mano. El idioma de referencia sigue a la lista si se queda fuera, y quitar
  uno no borra ningún fichero: dejan de pedirse.
- **Y quitar uno que una asignatura usa ya no rompe la asignatura.** Se lo
  podía quitar al repositorio y el `course.yaml` quedaba diciendo algo
  imposible, así que esa asignatura desaparecía de la biblioteca y el motivo
  quedaba en una lista de errores. Ahora Didacta se niega y dice cuáles lo
  usan.
- **La ficha de una asignatura solo ofrece los idiomas que su repositorio
  mantiene.** Se podía marcar cualquiera de los diez y guardar, y el fallo no
  se veía al guardar sino al volver a indexar. Con la asignatura repartida
  entre dos repositorios, cada uno recibe lo suyo en lugar de la lista entera.
- **Y puedes elegir con qué idiomas trabajas tú**, también en Ajustes. Un
  repositorio del departamento que mantiene cinco y una persona que da clase
  en dos no tienen por qué estorbarse. Viaja con el resto de tus preferencias,
  no toca ningún fichero, y un idioma apagado sigue saliendo donde algo ya lo
  declara: si no, guardar se lo llevaría por delante.
- **Cambiar `didacta.yaml` o `taxonomy.yaml` no actualizaba nada hasta
  reiniciar.** Didacta miraba si el índice se había quedado viejo recorriendo
  el material, y esos dos ficheros no están dentro — así que añadir un idioma
  a mano no se veía.
- **Beautify de verdad, no solo sangría.** Ahora también **junta cada párrafo
  y lo vuelve a cortar a 80 columnas**. Era lo que faltaba: lo que devuelve un
  traductor es el párrafo entero en una sola línea de cuatrocientos
  caracteres, y eso no se lee ni se revisa --cambiar una palabra sale en el
  historial como la línea completa, así que el diff deja de decir qué cambió--.
  Junta antes de cortar, así que un párrafo que ya venía mal cortado queda
  bien y no peor.
- No corta por dentro de una fórmula ni de unas llaves: partir
  `\textit{negación}` compila igual pero deja la orden a un lado y su
  argumento al otro. Si en toda la línea no hay ningún sitio bueno, la línea
  se queda larga. Y una orden sola --`\vspace{-2mm}`, `\dpause`-- se queda
  sola: quien la puso aparte la puso aparte porque hace algo aparte.
- **El contenido de un `\begin{frame}` ahora sí se sangra.** Una unidad tiene
  varias diapositivas, así que sí hay con qué contrastar.
- La casilla se llama **«Beautify»**, y **pulsar la palabra ordena el fichero
  en ese momento** sin tocar el ajuste. La casilla sigue diciendo si se hace
  solo al guardar.
- **Una traducción metía HTML en el `.tex`.** `l'operació` se guardaba como
  `l&#39;operació`, y eso no compila: en LaTeX `&` separa columnas de tabla,
  así que fuera de una da error y dentro parte la fila en dos. La traducción
  se pide en formato HTML --es la única forma de que los proveedores respeten
  las marcas que protegen el LaTeX-- y lo que volvía venía escapado. En
  valenciano y en catalán eso es una palabra de cada cinco.
- **Y perdía los espacios de alrededor de las fórmulas.**
  `identificaremos $\mathbb Z$ con` volvía como `identificarem$\mathbb Z$ amb`:
  el espacio que iba delante aparecía detrás, y la palabra quedaba pegada a la
  fórmula. Lo mismo con `su \textit{negación}`, que volvía como
  `la seva\textit{ negació}`, con el espacio metido dentro de las llaves. Pasa
  porque la traducción viaja en HTML, y ahí el espacio de alrededor de una
  marca no es texto sino formato: los proveedores lo mueven. Ahora ese espacio
  no se le cree al traductor, se copia del original --es una propiedad de la
  pieza, no del sitio, así que vale aunque cambie el orden de las palabras--.
  El espacio entre palabras sigue siendo suyo.
- **El editor lleva números de línea.** En el fichero entero, no en los campos
  de un problema. El número va en la primera fila de cada línea: una línea
  larga ocupa cuatro renglones en pantalla y sigue siendo una línea.
- **Al guardar, el `.tex` queda ordenado.** Cada entorno abre y cierra donde
  se ve, y lo de dentro va sangrado. Usa `latexindent` --la herramienta de
  CTAN-- cuando está instalada y funciona; si no, un indentador propio que
  hace menos y no necesita instalar nada. En una traducción recién hecha es
  donde más se nota: un traductor devuelve cada párrafo en una sola línea, y
  esa primera versión es la que se queda en el repositorio.
- Y **pone cada `\begin` y cada `\end` en su línea**, que es lo que la sangría
  sola no podía arreglar: lo que volvía de traducir era
  `\begin{definition} [Del seno] Las longitudes...`, con el entorno, su título
  y el texto pegados. Ahí no hay principio de línea que sangrar, y las barras
  de color del margen --que marcan dónde empieza y acaba cada entorno, por
  línea-- no podían dibujarse.
- Sangrar **no cambia una letra**: solo el espacio del principio de cada
  línea, y nunca dentro de un `verbatim` o un `lstlisting`, donde el espacio
  en blanco es el contenido.
- Y hay un botón **«Sangrar»** en la barra de formato para ordenarlo ahora,
  sin esperar a guardar. Hace falta porque casi todo el material se escribió
  antes que esto: al guardar se ordena solo, pero nadie va a abrir y guardar
  dos mil unidades para verlas bien puestas. Deja el cambio **sin guardar**,
  a la vista y con «Descartar» al lado, para poder mirarlo antes de escribirlo.
- **Y se puede apagar, por idioma.** En la barra del editor hay una casilla
  que deja el fichero exactamente como esté. Hace falta poco, pero hace falta:
  un entorno de código propio que el indentador no conoce, un `.tex` que
  genera otra herramienta y se regenera entero, un `\begin` sin cerrar de
  material migrado que compila igual pero descuadra el contador. Se guarda en
  el `unit.yaml`, así que vale también para quien abra el fichero en otro
  ordenador.
- **Una traducción ya no rompe el fichero.** `\item Donats` volvía como
  `\itemDonats` --el espacio que cierra el nombre de una orden se lo comía el
  traductor al recortar los extremos del texto-- y eso no compila. Y el `.tex`
  traducido salía como un muro, con los entornos pegados al contenido y sin
  una sola línea suelta, porque los saltos de dentro de un párrafo vuelven
  convertidos en espacios.
- Ahora **lo que está pegado a la sintaxis viaja con ella**: el salto que hay
  antes de un `\end{itemize}`, la sangría de una línea, el espacio que cierra
  un `\item`. El fichero traducido conserva la forma del original. Lo que
  sigue siendo del traductor es el espacio de dentro de una frase, que es
  suyo: al traducir «el conjunto $A$ es abierto» las palabras cambian de
  sitio y los espacios con ellas.
- **La pantalla de Traducción tiene dos selectores**, con la misma forma y uno
  al lado del otro: el idioma, y la clase de trabajo --«Desactualizadas», «Sin
  traducir», «Sin revisar»-- con su cuenta dentro. Los tres salen siempre, con
  un cero los que no tienen nada: un selector que se esconde cuando solo queda
  una clase de trabajo deja de decir cuál estás mirando.
- **El estado de una lección se actualizaba a medias.** Al aprobar una
  traducción cambiaba el punto de la pestaña del idioma pero no el botón de
  estado, que seguía diciendo «borrador»: el editor guarda la lección de
  cuando se abrió, y esa no se entera de nada. Quien entra a despachar
  traducciones no quiere borradores en medio, y quien entra a revisar no
  quiere ver lo que no existe. Así además traducir algo **se nota**: la unidad
  desaparece de una pestaña y aparece en la otra.
- **Y ya se puede aprobar una traducción.** Dentro de la lección, junto al
  idioma que estás editando, el estado es un botón: borrador → revisada, con
  un clic. Antes no había forma de decirlo desde la aplicación, así que el
  borrador se quedaba en la lista para siempre y la lista dejaba de significar
  nada. «No existe» y «desactualizada» no se pueden poner a mano: los calcula
  el motor, y declararlos garantizaría que se queden obsoletos.
- **La lista de traducción está partida en tres**, porque son tres trabajos
  distintos: «Desactualizadas» --su original cambió y dicen algo que ya no es
  cierto--, «Sin traducir» y «Traducidas, sin revisar». Antes iban mezcladas,
  y traducir algo no lo quitaba de la lista: pasaba de una categoría a otra
  unas filas más abajo, y desde fuera parecía no haber servido de nada. Cada
  grupo tiene su «Marcar todas», y las cuentas de la cabecera encienden y
  apagan cada uno.
- Al terminar de traducir, el resumen lleva **un enlace por fichero** que lo
  abre en su idioma para revisarlo y aprobarlo. Antes había que apuntar el
  nombre e irse a buscarlo a la biblioteca, que es el paso que convierte «lo
  reviso ahora» en «lo reviso otro día».
- **Traducir al valenciano ya funciona.** Fallaba con un volcado de JSON que
  decía «Invalid Value» y nada más: `va` es un código de Didacta y ningún
  traductor automático lo conoce. Se pide como catalán, que es lo mismo que
  hace la parte de LaTeX. Sale catalán central --«Qüestió» donde el valenciano
  dice «Questió»--, así que el diálogo lo avisa antes de traducir: es un
  borrador que hay que ajustar al revisar.
- **Traducir ya no ofrece traducir del castellano al castellano.** Cogía el
  idioma de la barra de arriba, que es el que estás mirando; ahora abre un
  diálogo con **los idiomas que le faltan** a lo que has marcado, con cuántas
  lecciones le faltan a cada uno, y marcas los que quieras.
- **Se pueden traducir muchas de golpe.** Casillas delante de cada lección en
  la pantalla de Traducción, «todas» y «ninguna», y un botón que las manda
  todas al mismo diálogo. Una que falle no para las demás: se dice cuál fue.
- **Dentro de una lección**, una pestaña de idioma vacía ofrece traducirla ahí
  mismo. Es donde se descubre que falta: entras a ver cómo quedó en valenciano
  y la página está en blanco.
- **Y dentro de un tema**, una pestaña «Traducir» con las lecciones a las que
  les falta algún idioma de esa asignatura, marcadas de entrada. Solo aparece
  cuando falta algo. Antes había que apuntar cuáles eran, irse a la lista de
  traducciones y buscarlas entre doscientas.
- **Guardar ya no te pide un mensaje de commit.** De salida, guardar deja el
  cambio confirmado y enviado a GitHub sin preguntar nada: escribes, se guarda,
  está donde tiene que estar. Las dos cosas se apagan por separado en Ajustes →
  Al guardar, porque confirmar y enviar son decisiones distintas.
- Con los commits automáticos apagados, lo que guardas se queda escrito y sin
  confirmar, y aparece un botón en la barra de arriba --delante de traer y
  enviar-- que los confirma todos juntos con el mensaje que le pongas, y te
  enseña qué ficheros van dentro antes de firmarlo. Con los automáticos puestos
  ese botón no sale: no habría nada que hacer con él.
- **El código de GitHub sale a la vez que el enlace.** Antes se abría el
  navegador primero y el código después, así que llegabas a github.com sin
  saber que te iban a pedir algo y tenías que volver a buscarlo.
- La pantalla de bienvenida lleva dibujos que enseñan de qué se habla: una
  lección dentro de varios cursos, un fichero del que salen las diapositivas y
  los apuntes, y un historial con nombres.
- Y explica mejor qué hacen los dos programas que hacen falta para compilar,
  que antes iban en la misma frase: **LaTeX** compone las páginas y lo instalas
  tú; **el motor de Didacta** decide qué páginas componer y se descarga ahí.
- **Se puede traducir una unidad con la máquina.** En la pantalla de
  Traducción, cada fila pendiente lleva un botón: elige proveedor, traduce y
  deja el resultado escrito **como borrador**, así que sigue apareciendo en la
  lista de lo que hay que revisar. Es una traducción que no ha leído nadie.
- **Las fórmulas no se traducen.** Las matemáticas, los entornos y sobre todo
  las claves de `\label`, `\ref` y `\cite` viajan protegidas y vuelven donde
  estaban: traducir una clave rompe todas las referencias del tema y no se ve
  hasta que alguien compila la víspera. Si un párrafo vuelve con la sintaxis
  cambiada, ese párrafo se queda sin traducir y se dice cuál.
- **Hay memoria de traducción.** Lo que se traduce se guarda en el repositorio,
  se versiona y se comparte: la decisión de cómo se dice algo en valenciano es
  del equipo, no de la máquina. Un párrafo ya traducido no se vuelve a pagar ni
  a decidir, y el mismo texto con otra fórmula dentro también lo reutiliza.
- Se dice lo que costó: cuántos párrafos había, cuántos salieron de la memoria
  y cuántos caracteres se mandaron. En el material de teoría, no enviar las
  matemáticas ahorra cerca de un tercio de lo que se facturaría.
- **Ya se pueden poner las claves de traducción automática.** En Ajustes, una
  sección para Google Cloud Translation y otra para Azure AI Translator, con un
  botón de probar: una credencial mal puesta no se nota hasta que mandas
  cincuenta unidades a traducir y vuelven todas con un 401.
- Las claves se guardan en el **llavero del sistema**, en tu máquina. No entran
  en ningún repositorio, ni en git, ni en lo que exportes: son configuración
  tuya, no contenido. Lo que sí es contenido --a qué idiomas se traduce cada
  asignatura-- sigue en el repositorio y se comparte.
- Una vez guardada, la clave no se vuelve a enseñar: se dice que hay una y se
  ven sus últimos cuatro caracteres, lo justo para reconocer cuál pusiste. Para
  cambiarla, se escribe otra.
- **Una asignatura se edita entera desde un sitio.** El lápiz de la lista de
  asignaturas abría un diálogo que solo cambiaba el nombre, y los idiomas
  estaban en Ajustes, en una lista de todas las asignaturas: había que salir de
  donde trabajas para cambiar algo de la que tienes delante. Ahora el nombre,
  los idiomas y la titulación se editan en la misma ficha.
- **Las asignaturas se agrupan por titulación.** Cada una dice a qué grado
  pertenece, y la lista se puede filtrar por grado. Los grados se gestionan
  desde la propia página de asignaturas --declarar uno nuevo, cambiarle el
  nombre en cada idioma--, porque un grado es una clasificación del material,
  como un tema, no una preferencia.
- Un grado lo declara un repositorio y las asignaturas de cualquier otro lo
  nombran: con que uno lo declare, todos lo ven agrupado. **Un grado que no
  declara nadie no rompe nada**: sus asignaturas se ven enteras, sin agrupar,
  igual que antes de que los grados existieran. Y se dice cuáles son, porque
  casi siempre significa que falta abrir un repositorio.
- Si dos repositorios llaman distinto al mismo grado --o ponen la misma
  asignatura en grados distintos--, sale en «Entre repos» y se iguala desde
  allí, con el mismo gesto que el resto de los metadatos.
- **Lo que se comprueba entre repositorios tiene su propio sitio.** Estaba en
  Ajustes, que es donde se pone lo que no tiene sitio; es trabajo pendiente
  sobre el material, como las traducciones, y en Ajustes no se entra a mirar si
  algo va mal. Ahora es un apartado del carril, y **solo aparece con más de un
  repositorio abierto**: con uno no hay nada que cruzar.
- Además de los metadatos que no coinciden, ese apartado enseña ahora los
  documentos que llaman a unidades de otro repositorio. Eso compila en tu
  máquina --que tiene los dos-- y no compila en la de quien solo tenga uno, y
  hasta ahora solo se veía entrando en el curso concreto.
- **Didacta puede hablar con un modelo de lenguaje.** Un servidor MCP que se
  enciende en Ajustes: mientras está encendido, un LLM conectado puede leer tus
  asignaturas, buscar en la biblioteca, escribir una traducción y comprobar que
  lo escrito compila. Sirve para lo que se hace a mano y no tiene gracia:
  traducir cincuenta unidades, corregir la misma errata en las cuarenta que la
  repiten.
- **Se ve todo lo que hace.** Con el servidor encendido aparece un icono nuevo
  en la barra lateral, con dos cosas: qué llamadas va recibiendo --cuál, sobre
  qué, cuánto tardó, y marcadas las que escriben-- y la lista de lo que sabe
  hacer, que sale del propio servidor.
- **No publica nada.** No hay ninguna herramienta que haga commit, ni que traiga
  ni que envíe, y eso no es un olvido: lo que un modelo escriba queda en disco y
  lo envías tú, viendo el diff como cualquier otro cambio.
- **Escribir hay que pedirlo, repositorio por repositorio.** De salida el
  servidor solo lee, que ya es casi todo el valor y no puede estropear nada. Y
  escucha solo en esta máquina.
- **El idioma se elige arriba, y manda sobre lo que se lee.** Estaba escondido
  en la biblioteca: desde la lista de asignaturas no había forma de tocarlo, y
  los títulos salían siempre en el idioma propio de cada asignatura aunque
  estuvieras preparando la versión en valenciano. Ahora está en la barra
  superior, delante de traer y enviar, y cambia el título de la asignatura, el
  del tema y el de cada documento. Las asignaturas se reordenan por el título
  que estás leyendo, no por el castellano.
- **Los títulos se editan en todos los idiomas a la vez.** Un lápiz junto a la
  asignatura, al tema y al documento abre el mismo diálogo que ya tenían los
  apartados. Lo que dejes en blanco se marca como pendiente en el fichero, no
  se escribe vacío: un título vacío es un título, y saldría en el PDF.
- **Compilar usa el idioma en el que estás.** Un curso son cuarenta salidas y
  media hora, y la víspera de la clase en valenciano no quieres los tres
  idiomas. Mantén pulsado el botón para elegir entre el idioma actual --dice
  cuál es-- y todos los de la asignatura.
- **El visor de PDF enseña los idiomas que hay.** Una fila de idiomas encima de
  la de versiones, y entra por el que estás usando. Antes solo podía enseñar
  uno: la versión en valenciano existía en el disco y no había forma de llegar
  a ella.
- En una asignatura repartida entre repositorios se miraban los PDF de uno
  solo, así que la mitad de los documentos salían sin icono aunque estuvieran
  compilados.
- La casilla de recompilar al exportar compila los idiomas que vas a exportar.
  Antes compilaba el propio de cada documento y el reparto salía incompleto.
- **Didacta imprime sus rótulos en diez idiomas.** A castellano, valenciano e
  inglés se suman catalán, gallego, euskera, francés, alemán, italiano y
  portugués: «Teorema», «Demostración», «Curso», «Error frecuente» y las
  treinta y dos palabras restantes que el PDF lleva sin que nadie las escriba.
  Los siete nuevos son ficheros base, con la terminología matemática al uso y
  **sin revisar por nadie que dé clase en esos idiomas**: sirven para compilar
  desde el primer día, y antes de repartir material conviene que los lea quien
  lo hable. Son treinta y seis palabras cada uno y se cambian en un sitio.
- **Cada asignatura elige sus idiomas.** En Ajustes, un desplegable por
  asignatura marca a cuáles se traduce. Lo que no esté marcado no se pide y no
  cuenta como pendiente, así que la lista de traducciones que faltan vuelve a
  ser una lista de trabajo en vez de todo lo imaginable. Quitar un idioma no
  borra nada: los ficheros se quedan donde estaban y volver a marcarlo los
  recupera. En una asignatura repartida entre repositorios se escribe en
  todos, para que no acabe diciendo dos cosas distintas.
- **Un apartado con título en un idioma que no fuera castellano, valenciano o
  inglés tumbaba la compilación**, con un error que hablaba de una secuencia
  no definida que no aparecía en ningún fichero del curso.
- **Los temas se crean desde el curso, y los documentos desde su tema.** El
  botón de abajo creaba un documento y luego había que decir a qué tema
  pertenecía, que es el paso que se olvida. Ahora crea un tema, y cada tema
  lleva dentro su propio botón para añadirle documentos, que nacen ya en él.
  Queda un botón aparte para lo que no es de ningún tema --la FAQ, la
  notación--, que también existe.
- Al crear un tema o un documento con varios repositorios abiertos se
  pregunta en cuál; con uno solo no se pregunta nada.
- **Las asignaturas y los cursos se pueden marcar para tenerlos arriba.** Una
  estrella en cada uno; lo marcado se salta el orden y sale primero. Las dos
  marcas son independientes: marcar Análisis Matemático I no dice cuál de sus
  seis cursos estás dando, que es justo lo que quieres a mano. Te siguen de un
  ordenador a otro.
- El resto sigue como estaba: las asignaturas por título de la A a la Z, y los
  cursos de cada una del más reciente al más antiguo.
- **Álgebra ya no sale después de Zoología.** Los títulos se ordenaban por el
  valor de sus letras, y en esa cuenta una `á` va detrás de la `z`, así que
  todo lo que empezaba por vocal acentuada caía al final de la lista.
- **Un curso académico se puede empezar en blanco.** Antes había que copiarlo
  de otro a la fuerza, lo cual no vale ni para la primera asignatura --que no
  tiene de dónde-- ni para un año que se compone desde cero. Copiar del
  anterior sigue siendo lo que se ofrece primero, porque es lo corriente.
- Los cursos de una asignatura pasan a verse en filas, cada uno con su menú en
  el borde derecho, en la misma vertical que el de la asignatura: el mismo
  gesto, siempre en el mismo sitio.
- **Un tema se puede copiar de un curso a otro.** En la lista de cursos de una
  asignatura, el menú de un curso lleva a «Copiar a otro curso…»: se elige a
  cuál y se marcan los documentos que se quieren. Lo que se copia es la
  composición --qué unidades lleva y en qué orden--; las unidades no se
  duplican, así que corregir una errata sigue siendo corregirla una vez. Los
  temas se llevan su declaración consigo, y lo que ya esté allí no se pisa.
- **Se pueden añadir varios repositorios de una vez**, marcándolos en la
  lista. Y antes de clonar se mira qué hay en la carpeta de destino: si ya
  está clonado se dice y se ofrece abrir el que hay --volver a clonar encima
  se llevaría por delante lo que tenga sin enviar, que puede ser el trabajo de
  otra persona de la misma máquina--; si hay otra cosa, no se toca nada.
- **Los repositorios se encienden y se apagan desde arriba.** Los nombres de
  la barra superior ahora son botones: pulsa uno y su material desaparece de
  la biblioteca y de las asignaturas; púlsalo otra vez y vuelve. Apagarlo no
  lo cierra --sigue trayendo y guardando--, y enseña exactamente lo mismo que
  vería quien no lo tuviera, así que sirve para comprobar qué ve un compañero.
  La elección te sigue de un ordenador a otro.
- **Una asignatura repartida entre dos repositorios se ve entera.** Antes la
  pantalla del curso enseñaba los documentos de uno solo y había que cambiar
  de repositorio para ver los demás, como si fueran dos sitios distintos.
  Ahora salen todos juntos, y al mover uno se guarda en el repositorio del que
  sale.
- **Un curso se ve por temas.** Lo que se da junto sale junto: el Tema 1, con
  su teoría, su práctica, su análisis bibliográfico y su marco histórico en
  una misma tarjeta, aunque esos ficheros estén en repositorios distintos. Los
  temas se pliegan, y lo que no pertenece a ninguno sigue donde estaba.
- El tema lo declara un repositorio y lo nombran los documentos, que pueden
  estar en otro. Quien no tenga el repositorio donde se declaró ve todo su
  material igual que antes: lo que no ve es la agrupación. Nunca desaparece
  nada por no tener un repositorio.
- Un documento puede pertenecer a varios temas, y sale en todos.
- Los temas se declaran por curso académico, así que dos años del mismo tema
  son dos temas: lo que se dio en cada uno no se mezcla.
- **Tus preferencias te siguen de un ordenador a otro.** Qué temas tienes
  plegados se guarda en el repositorio que elijas, en un fichero con tu nombre
  de GitHub: podéis compartir repositorio sin pisaros las vuestras. Se elige
  en Ajustes, y sin elegir ninguno todo sigue funcionando en esta máquina.
- **Los análisis bibliográficos ya compilan.** Un tema puede citar sus fuentes
  —«la demostración está en el Teorema 1.1.1 de Abbott»— y la cita sale en el
  PDF con su autor y su año. Las obras se listan solas al final del documento,
  y solo si se ha citado alguna. Las fuentes se escriben una vez para todo el
  repositorio, en `shared/bibliography.bib`.
- Didacta avisa antes de compilar de toda obra citada que no esté en esa
  lista, con el nombre de la lección donde está la cita. Antes eso aparecía
  compilando, como un error que no decía qué faltaba.
- **Las diapositivas de un tema largo ya no fallan la primera vez.** La barra
  de progreso del pie se desbordaba mientras LaTeX aún no sabía cuántas
  diapositivas había, y el tema no salía. Compilarlo dos veces lo arreglaba,
  lo cual no es un arreglo.
- **Con dos repositorios abiertos, los dos se miran.** Al segundo no se le
  veían los cambios hechos desde fuera —ni un fichero editado en otro
  programa, ni un `git pull`— hasta reiniciar. Y un repositorio recién añadido
  al que todavía no se le había generado el índice se quedaba enseñando el
  error para siempre, incluso después de generarlo: ahora lo coge en cuanto
  aparece.
- **Didacta es software libre.** El código está publicado bajo la GPL-3.0, y
  con él la documentación: qué es cada pantalla, cómo se escribe una unidad y
  cómo se publica una versión, con capturas. Está en
  <https://franjfal.github.io/didacta/>, que es también de donde se descarga.
- **Actualizarse ya no depende de tener acceso a nada.** Antes las versiones
  vivían en un repositorio privado y la aplicación comprobaba, después de
  entrar en GitHub, si tu cuenta llegaba a él. Esa comprobación ya no existe:
  buscar una versión nueva no manda ninguna credencial. Entrar en GitHub sigue
  haciendo falta, pero por lo que siempre fue de verdad, que es que tu material
  vive en tus repositorios.
- **La primera vez, Didacta se presenta y se configura sola.** Explica qué es
  en tres pantallas y después deja hecho lo que hace falta para trabajar:
  entrar en GitHub, abrir el primer repositorio --de GitHub, de una carpeta ya
  clonada, o preparando uno vacío-- y descargar el motor, que hasta ahora había
  que clonar a mano desde un terminal. Se puede saltar entera, y no vuelve.
- **Y un recorrido guiado por la ventana**, que señala el carril, la barra de
  arriba y la cola de traducción diciendo para qué es cada cosa. Se sale con
  ++esc++ o pulsando fuera, y desde Ajustes se vuelven a ver las dos cosas.

---

## 1.1.0 — 2026-09-15

- **Compilar ya no es una espera a oscuras.** Se abre un terminal que enseña
  lo que LaTeX va escribiendo, línea a línea y mientras compila: qué fichero
  está leyendo, qué paquete carga y en qué pasada va. Vale tanto para una
  unidad suelta como para un tema entero.
- La ventana se quita sola cuando la compilación sale bien y se queda cuando
  algo falla, que es cuando hay algo que leer. El registro se puede volver a
  abrir, y copiar entero.
- **Didacta pide entrar en GitHub para abrirse.** El material está en
  repositorios privados y cada cambio se guarda con el nombre de quien lo hace,
  así que la sesión es el permiso. Se entra una vez; a partir de ahí la
  aplicación abre también sin conexión, y solo vuelve a pedirlo si GitHub deja
  de reconocer la sesión.
- **Solo se abren repositorios de GitHub a los que llegas.** Una carpeta
  cualquiera del disco ya no vale: lo que se escriba en ella no tendría a dónde
  ir. Al añadir un clon se comprueba de qué repositorio es y si tu cuenta
  alcanza ese repositorio, y se pone al día con GitHub en ese momento.
- **Historial en cada lección, práctica y tema.** Una pestaña nueva con todas
  las versiones de ese fichero: se elige una y se lee el fichero entero tal y
  como estaba ese día, con lo que esa versión añadió en verde y lo que quitó en
  rojo. Quién la escribió, cuándo y con qué mensaje están a un clic, en el
  botón de información. Un fichero que se movió de sitio conserva su
  historial.
- Las pestañas de una lección cambian de orden: los idiomas, compilar,
  `unit.yaml` y el historial. Compilar pasa delante porque es lo que se hace
  entre una edición y la siguiente.
- **Lo que se edita está al día.** Antes de guardar un cambio se comprueba que
  el repositorio no se haya quedado atrás, y si se ha quedado se trae. La
  comprobación vale unos minutos, así que guardar sigue siendo instantáneo. Si
  las dos versiones han seguido por su lado, no se toca nada y se avisa en la
  barra de arriba.
- **Un repositorio recién creado en GitHub se prepara desde Ajustes.** Al
  añadir uno que todavía está vacío, en lugar de un error de git, Didacta
  ofrece dejarlo listo: lo configura con el nombre que elijas, hace el primer
  commit y lo envía. Y un clon que falla ya no deja una carpeta vacía detrás.

## 1.0.0 — 2026-09-15

Primera versión que se distribuye e instala como una aplicación, en lugar de
compilarse en la máquina de cada uno.

- **Didacta se actualiza sola.** Comprueba si hay una versión nueva una vez
  por semana, lo pregunta antes de hacer nada y se encarga del resto. También
  se puede buscar a mano desde Ajustes.
- **Se instala en Windows, macOS y Linux.** Hasta ahora solo había una
  compilación para macOS hecha a mano.
- **Se entra con la cuenta de GitHub**, sin escribir la contraseña dentro de
  la aplicación: se autoriza en github.com y se vuelve. Quien tenga acceso al
  repositorio de versiones puede instalar y actualizar; quien no, no.
- Se trabaja con varios repositorios de contenido a la vez, cada uno con su
  carpeta y su color.
- Edición multilingüe de unidades, de `unit.yaml` y de composiciones, sobre
  clones locales.
