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

## 1.2.0 — 2026-09-16

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
