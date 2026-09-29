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

**Qué versión.** La que asigne la próxima publicación, que sube lo que diga
`release.yaml` --la mediana si no dice otra cosa--. La dice:

```
python3 packaging/release.py next
```

Si todavía no se sabe, la sección puede empezar como `## Próxima`:
`python3 packaging/publish.py` pregunta el tamaño y le pone el número.

Sin esa sección no se publica: el workflow se para antes de compilar nada.

---

## Próxima

- **Las plantillas de serie dicen lo que son.** En Ajustes → Bloques y
  plantillas, la lista decía «solo los enunciados» también de las copias del
  profesor, y al editar una de las que trae Didacta el editor salía con los
  ejes por defecto --alumno, sin soluciones, con pausas-- en lugar de los
  suyos. Ahora cada una enseña lo que lleva y se edita desde lo que es.
- **Los avisos con botón vuelven a irse solos.** «Guardado en el historial ·
  Ver cambios», «Deshacer» y los demás se quedaban puestos hasta pulsarlos y
  tapaban la barra de abajo, la que dice si hay cambios sin enviar. Ahora
  duran sus segundos, como antes.
- **«Ver qué ha cambiado» en una traducción desactualizada funciona.** Se
  confundía la línea del título en ese idioma con la de su estado, y decía
  siempre que no se sabía desde cuándo había cambiado el original.
- **Traducir varias lecciones seguidas ya no deja algunas sin hacer.** Entre
  una lección y la siguiente el servidor podía cerrar la conexión, y la
  siguiente salía en el resumen como «Connection closed before full header
  was received». Ahora esa petición se repite una vez.
- **La cola de traducción abre en el idioma que falta.** Pulsar una lección
  en Traducción la abría en la pestaña de siempre, y había que buscar la del
  idioma que se venía a traducir.
- **«Aprobar y siguiente» ya no pregunta por lo que acaba de guardar.** Con
  algo corregido, guardaba y marcaba revisada, pero al pasar a la siguiente
  salía «Hay cambios sin guardar». Y al pasar a la siguiente se abre con su
  texto: de una lección a otra, la pantalla se reutilizaba con el editor de
  la anterior, y guardar habría escrito ese texto en la nueva. Pasaba igual
  con cualquier enlace directo de una lección a otra, de un documento a otro
  o de un curso a otro.
- **«Darla en otro tema» ya no propone el tema donde ya está.** Con la
  lección en el curso de este año y en el que viene, el diálogo abría con su
  propio tema elegido, y aceptarlo la ponía dos veces. Ahora propone uno que
  no la lleva, marca los que sí y, si se elige uno de ellos, lo dice.
- **Con la interfaz Esencial, llevar un tema a otro sitio ya no ofrece
  moverlo.** El menú escondía «Mover a…», pero el diálogo de «Añadir
  vinculado a…» y «Duplicar en…» lo seguía ofreciendo. Y el aviso de al
  terminar dice el tema y la asignatura por su nombre, no por su id.
- **El tamaño del texto se lee entero con el texto grande.** En Ajustes →
  Apariencia, a partir del 135 % el tanto por ciento se partía en dos líneas.
- **La biblioteca llama a las categorías y a los temas por su nombre.** Los
  sacaba de la carpeta --«algebra» salía como «Algebra»-- y no los traducía.
  Ahora usa los de `taxonomy.yaml`, en el idioma que miras.
- **Un documento que llama a otro repositorio ya no sale también como
  referencia rota.** La página del curso lo contaba dos veces: una como
  «no apunta a ninguna unidad del catálogo», que no era verdad, y otra con
  su aviso de verdad, el de que llama a una lección de otro repositorio.
- **Declarar la teoría o los problemas trae su nombre.** Declarado el
  primer bloque propio, los dos de siempre salen por su id hasta declararlos
  también, y al hacerlo había que volver a escribir «Teoría» y se perdían sus
  traducciones. Ahora viene escrito, y se guarda en todos sus idiomas.
- **Crear tu primera plantilla ya no deja sin compilar lo demás.** En cuanto
  un repositorio declara alguna plantilla, valen solo las declaradas; al
  duplicar o retocar la primera se escribía solo esa, y todo lo que usaba
  las de serie dejaba de compilarse. Ahora la primera se escribe con las de
  serie, y el diálogo lo dice: las que no quieras, se apagan.
- **La plantilla compacta se llama «Guía» en todas partes.** La lista de
  plantillas decía «Handout», y el fichero que se exportaba, «Guía».
- **Una lección nueva va, de salida, al repositorio de su tema.** Con varios
  abiertos, el diálogo proponía siempre el primero, aunque las demás
  lecciones de ese tema estuvieran en otro.

## 0.3.0 — 2026-09-28

- **Videotutoriales.** La web de Didacta estrena una galería de vídeos cortos,
  de uno a tres minutos, ordenados por rutas --empezar, escribir, preparar una
  asignatura, compilar, traducir…--, con un índice por pregunta y el recorrido
  que conviene según lo que hagas. Todos con subtítulos, capítulos y la
  transcripción al lado. El primero, *Didacta en dos minutos*, se ve pulsando
  la ventana de la portada; los demás van saliendo, y cada página de la ayuda
  enseña los suyos.
- **Entrar en GitHub solo con los repositorios que elijas.** Didacta entra
  ahora con su GitHub App: GitHub pregunta a qué repositorios puede llegar, en
  lugar de darle todos los tuyos, y la sesión se renueva sola. Si ya habías
  entrado con una versión anterior, hay que volver a entrar una vez.
- **Didacta, en valenciano y en inglés.** En Ajustes → Apariencia, *Idioma
  de Didacta*: castellano, valenciano, inglés o el del sistema, que es lo que
  viene. Cambia al momento, sin reiniciar. Es el idioma de la aplicación, no
  el del material: se sigue pudiendo preparar los apuntes en cualquiera.
- **Crear una lección sin salir de la aplicación.** En la biblioteca, «Nueva
  lección en…» el tema que se está mirando; en la composición de un
  documento, «Crear una nueva…» al añadir, que la crea y la deja puesta. Se
  pide el título, el tema y el tipo, y enseña dónde va a quedar antes de
  crearla. Antes había que ir al terminal a escribir `didacta new unit`.
- **Duplicar una lección** para empezar otra a partir de ella, desde su icono
  de información: la copia lleva sus idiomas, sus figuras y sus metadatos con
  el título nuevo, y desde ese momento son dos lecciones.
- **Mover o renombrar una lección** sin romper nada, con cualquiera de las
  dos interfaces: cada documento que la usa, los temas vinculados y los
  prerrequisitos de otras lecciones se reescriben en el mismo cambio, y su id
  y sus traducciones siguen siendo los mismos. Antes de confirmar dice de qué
  cursos son esos documentos, y avisa cuando hay más de uno.
- **Lo que no va a compilar se dice antes de compilar.** Debajo del editor,
  con su línea y un clic para ir allí: una llave o una fórmula sin cerrar, un
  entorno que no se cierra y las órdenes que en ese idioma no existen, como
  `\lgem` fuera del catalán y del valenciano.
- **Los símbolos de la paleta ya no rompen la compilación.** Pulsar «α» en
  mitad de un párrafo escribía `\alpha` suelto; ahora lo mete en `$…$`, con el
  cursor dentro para seguir con la fórmula. Dentro de una fórmula, va tal cual.
- **Completar al escribir.** `\didac` ofrece `\didactatitle` y `\begin{`
  enseña los entornos de Didacta, y al elegir uno escribe también su `\end`.
  Con las flechas se elige y con Intro o Tab se acepta.
- **Más entornos en la barra**: Propiedad, Cuestión, Axioma, Notación,
  Algoritmo, el título de la diapositiva y, para el profesor, Nota didáctica y
  Error frecuente.
- **Buscar en la lección que se edita.** ⌘F (Ctrl+F) abre una barra encima
  del texto que pinta las coincidencias y salta de una a otra con Intro o ⌘G.
  También reemplaza, una o todas, y acepta expresiones regulares.
- **Los metadatos sugieren lo que ya existe.** La categoría, el tema, las
  etiquetas y los prerrequisitos ofrecen lo que usan las demás lecciones, y
  avisan cuando lo escrito es nuevo: una errata ya no crea una categoría sin
  que nadie lo note.
- **Guardar ya no pregunta el mensaje.** Se guarda con el que propone
  Didacta, y el aviso ofrece «Ver cambios» con lo que se quitó y lo que se
  puso. Quien quiera revisar cada cambio antes lo enciende en Ajustes →
  Guardar y sincronizar.
- **Una barra del editor más corta, y una interfaz Esencial o Completa.**
  Para corregir una errata se ven el estado, Descartar, Guardar y la barra de
  formato básica; las pestañas dicen «Castellano» y «Valencià» en lugar de
  «es» y «va», y «Beautify» pasa a llamarse «Ordenar» y sale una vez. La
  ruta, el contador, la sangría de cada fichero, reemplazar, copiar la
  referencia y mover lecciones están en la interfaz Completa, en Ajustes →
  Apariencia.
- **La biblioteca vuelve donde estabas.** Lo abierto, los filtros y lo
  buscado se conservan al abrir una lección y volver, y van en la dirección:
  un enlace abre la biblioteca igual.
- **Buscar sin tildes.** «limite» encuentra «Límite» en la biblioteca.
- **Buscar dentro de las lecciones.** «En el texto», al lado del buscador de
  la biblioteca, encuentra lo que una lección dice aunque no lo diga su
  título, y enseña la línea.
- **Añadir a una composición busca como la biblioteca**: cada palabra en
  cualquier orden, en todos los idiomas y sin tildes.
- **Abiertas hace poco**, en la raíz de la biblioteca: las últimas lecciones
  abiertas, a un clic. Y en la interfaz Completa, **búsquedas guardadas** con
  nombre.
- **Compilar se puede parar.** Una tira abajo, en todas las pantallas, dice
  qué se compila y por cuál va --«9/38»--, con **Detener**, que para también
  LaTeX. Lo que se pulsa mientras otra cosa compila espera su turno en lugar
  de pisarla, un curso entero pregunta antes de empezar, y al acabar un lote
  se dice cómo fue: «36 bien, 2 con errores».
- **Los errores de compilación llevan a la lección y a la línea.** Cada uno
  dice en qué lección está, en qué idioma y en qué línea, con **Abrir**, que la
  abre con el cursor ahí. Salen todos, y en un lote se guardan aparte con su
  documento en lugar de perderse en el registro.
- **Recompilar lo que no ha cambiado es inmediato**, y lo que sí ha cambiado
  tarda menos: se aprovecha lo que LaTeX ya había hecho. Recompilar un curso
  después de corregir dos erratas es compilar dos documentos, no cuarenta.
- **Las versiones de un documento se compilan a la vez**: un tema en tres
  versiones y dos idiomas tarda la mitad o menos. Cuántas a la vez, en Ajustes
  → Herramientas.
- **Viejo de verdad, y compilar solo lo viejo.** Un PDF se da por viejo si ha
  cambiado el contenido de algo de lo que entró en él, no su fecha: traer
  cambios de GitHub ya no deja todo viejo. Cada tema dice cuántos documentos
  tiene desactualizados, y «Compilar lo desactualizado» rehace solo eso, en el
  tema o en el curso entero.
- **Diapositivas que se salen.** Una diapositiva con más de lo que cabe se
  cortaba por abajo sin que nadie lo dijera. Ahora se avisa de las que se
  salen más de 5 pt, con su lección y la línea donde empieza, y **Abrir** lleva
  allí. En un lote salen junto a los errores. Las líneas de los apuntes que
  pasan del margen, si se piden en Ajustes → Herramientas.
- **Vista rápida**, en Ajustes → Herramientas: compilar un documento desde su
  pantalla en una sola pasada, para ver cómo queda un cambio en la mitad de
  tiempo. El PDF dice que es una vista rápida, al lado queda «Compilar
  entero», y lo que sale así cuenta como desactualizado hasta compilarlo
  entero.
- **Buscar en el PDF**, con la lupa del visor o ⌘F: sin mirar tildes ni
  mayúsculas, resaltado, e Intro para ir al siguiente. Con dos idiomas lado a
  lado se busca en los dos.
- **Del PDF a la lección con ⌘+clic** (Ctrl+clic): se abre la lección de donde
  sale lo pulsado, en su idioma y con el cursor en su línea. En las
  diapositivas también, aunque LaTeX lo apunte todo al final de cada una.
- **Mejor contraste.** Los colores de cada repositorio se leen en claro y en
  oscuro (el ámbar se quedaba corto en claro y todos en oscuro), la acción de
  los avisos ya no es verde claro sobre claro en oscuro, y el número del carril
  ya no es blanco sobre ámbar.
- **El menú de cortar, copiar y pegar, en castellano**, como el resto de la
  aplicación. Salía en inglés.
- **Se puede usar sin ratón.** Las filas y las tarjetas se alcanzan con el
  tabulador, se pulsan con Intro o Espacio y enseñan dónde está el foco; un
  lector de pantalla las anuncia como botones, las cruces de cerrar dicen qué
  cierran y el estado de cada idioma se dice con palabras, no solo con color.
  Los botones más pequeños crecen hasta 32 píxeles.
- **Los atajos, en todos los sistemas.** En Windows y Linux funcionan los
  mismos que en el Mac, con Ctrl en lugar de ⌘, y los tooltips los escriben
  como toca en cada sistema. ⌘/ (Ctrl+/) enseña la lista entera, que también
  está en Ajustes → Ayuda. El menú del Mac gana Edición, Ventana y Ayuda.
- **Las pantallas vacías dicen por qué y ofrecen la salida.** Sin
  asignaturas, «Nueva asignatura» y «Probar con un ejemplo»; con todas
  ocultas, «Ver las ocultas»; la biblioteca sin repositorio, «Añadir un
  repositorio». Y si el índice falta o no se puede leer, un botón lo
  regenera, en lugar de mandar al terminal a escribir `didacta index`.
- **La aplicación habla sin git.** Un commit es un *cambio guardado*,
  confirmar es *guardar en el historial* y el clon es *la copia en tu
  ordenador*. La barra de abajo dice «Guardado en GitHub · al día» o lo que
  falte, en lugar de «Clon local en /Users/…, enviando cada commit».
- **Los fallos se entienden y dicen qué hacer.** En lugar del mensaje de git
  en inglés, el aviso dice qué ha pasado --hay cambios nuevos en GitHub, la
  sesión ha caducado, no hay red, dos cambios chocan, la carpeta está
  ocupada, GitHub rechaza el envío-- con el botón que lo arregla cuando lo
  hay, y lo que dijo el programa en «Detalles», con Copiar y Contar el
  problema. Ya no se va a los cuatro segundos.
- **Lo escrito sobrevive a un cierre de golpe.** Si Didacta se cuelga o se va
  la luz con texto sin guardar en una lección, al volver a abrirla se ofrece
  recuperarlo. Se guarda fuera del repositorio, y se borra al guardar o al
  descartar.
- **⌘S (Ctrl+S en Windows y Linux) guarda** en el editor de una lección, en
  sus metadatos, en la composición de un documento y en la lista de un
  curso. Hace lo mismo que el botón: pide el mensaje y enseña el diff.
- **Irse con cambios sin guardar pregunta antes.** Cambiar de lección o de
  pantalla, o cerrar Didacta, con algo escrito y sin guardar dice qué es y
  deja volver a guardarlo. Antes se perdía sin avisar.
- **La guía de escritura enseña lo que existe**: los problemas se escriben con
  `exercise` y los entornos `hint`, `answer`, `solution` y `marking`, y las
  figuras con `\includegraphics{figures/…}`. Copiar el ejemplo de la
  documentación ya compila, y un test comprueba que siga siendo así.
- **«Atrás» vuelve a donde estabas de verdad**: a la sección de Ajustes en la
  que estabas y a la lección en el idioma que mirabas, no solo a la pantalla.
- **El menú Repositorio dice la verdad.** «Enviar commits» (⌘⇧U) envía solo
  lo que ya está guardado, en lugar de cerrar lo demás con el mensaje
  «Enviar»; y ni «Enviado» ni «Traído» salen cuando algo ha fallado: dicen en
  qué repositorio y por qué.
- **Guardar ya no deja ficheros sueltos.** Después de reordenar un tema y
  guardar, «Enviar a GitHub» avisaba de tres ficheros sin guardar en el
  historial que nadie había tocado: el índice que Didacta regenera al
  guardar. Ahora va en el mismo cambio que lo que se guardó.
- **«Desactualizada» funciona.** Al traducir y al revisar se guarda la huella
  del original; si luego el original cambia, la traducción se marca como
  desactualizada. Antes no pasaba nunca. Re-sangrar el original no cuenta.
- **Lo que traduce la máquina queda como borrador de verdad.** Se escribía
  solo el texto, y el motor lo contaba como traducido: desaparecía de «Sin
  revisar» aunque no lo hubiera leído nadie. Ahora el estado va en el mismo
  commit.
- **Erratas**: en valenciano el entorno de cuestión dice «Qüestió»; ordenar por
  título ya no deja «Álgebra» detrás de la Z; «Ver en el Finder» se llama
  como toca en Windows y en Linux; y dos textos corregidos, uno que remitía a
  un botón que no existe.
- **`\sen`, `\tg`, `\arcsen` y compañía compilan en todos los idiomas.** Solo
  existían en castellano, y una traducción que copiaba las fórmulas no
  compilaba en valenciano. Cada idioma las escribe con su nombre.
- **En diapositivas con pausas, los teoremas ya no se numeran de más.** El
  ejemplo de después de una pausa salía 1.3 en lugar de 1.2, y todo lo que
  venía detrás, uno más.
- **Compilar un tema desde la lista del curso saca sus versiones, no las
  siete.** Las que declara cada documento; todas, manteniendo pulsado.
- **La consola de compilación ya no enseña la marca verde cuando LaTeX
  falla**: dice «Terminada con errores», en rojo.
- **Los filtros de la biblioteca funcionan también sin buscar nada.**
  Traducción, Tipo y Orden se ponían en verde pero solo actuaban con texto en
  el buscador; ahora recortan y ordenan el árbol, y la cabecera dice cuántas
  quedan.
- **Traducir con la máquina ya no pisa lo corregido a mano.** De salida solo
  traduce lo que no tiene texto, y en el idioma que estás mirando; rehacer
  borradores y desactualizadas es una casilla aparte que avisa de lo que
  sustituye.
- **Quitar una asignatura o un curso ya no promete que se puede revertir**,
  que desde la aplicación no se puede, y avisa de que se lleva sus versiones
  congeladas.
- **Una asignatura repartida entre dos repositorios se duplica, se quita y se
  congela entera.** Las tres cosas actuaban solo en el primero: el curso nuevo
  salía sin los problemas, o la asignatura quitada seguía en la lista por la
  otra mitad.
- **Mirando una versión congelada, lo que se compila es de aquella versión.**
  «Compilar» y «Ver PDF» usaban lo de hoy mientras la pantalla enseñaba el
  material de entonces; ahora trabajan sobre su árbol, con sus propios PDF.
- **Corregir una lección deja viejo el PDF del tema que la lleva.** Antes solo
  contaba la composición, y se podía proyectar un tema de antes de la
  corrección sin que la pestaña lo marcara.
- **Una lección que se da en varios cursos lo dice encima del texto**: «Se da
  en 2 cursos: lo que guardes aquí cambia en todos», con cuáles, y un botón
  para separar una copia si solo quieres cambiarla en uno.
- **Exportar ya no reparte las soluciones.** De salida solo sale lo que puede
  ver un estudiante: los enunciados y, como mucho, los resultados. Las
  resoluciones completas se piden con una casilla, y las copias del profesor
  --la plantilla de corrección del examen, las diapositivas con notas-- con
  otra aparte y en rojo. Lo que se queda fuera se dice. Y exportar desde la
  aplicación vuelve a funcionar: fallaba siempre con «El motor falló».
- **Modo oscuro.** El sol y la luna, abajo en la columna de la izquierda,
  pasan de claro a oscuro; en Ajustes → Apariencia se elige también «como el
  sistema», que es lo que viene. Los colores de los entornos son los mismos
  del PDF, aclarados para leerse sobre oscuro, y los PDF se siguen
  compilando en claro.
- **Ajustes, por secciones.** Una columna a la izquierda con cada sección
  --la cuenta y los repositorios, los idiomas, las herramientas, la
  apariencia…-- y se ve una a la vez, en lugar de una lista de catorce
  apartados. Los avisos que mandan a Ajustes llevan a la sección que toca.
- **Una interfaz más cuidada**: los filtros de la biblioteca son botones que
  dicen cuál está puesto, la flecha de volver ya no ocupa una fila para ella
  sola, y los menús y los diálogos tienen sombras más suaves.
- **Un repositorio de ejemplo para probar Didacta.** «Probar con un ejemplo»,
  en la bienvenida y en Ajustes, crea en tu cuenta de GitHub un repositorio
  privado con una asignatura pequeña: un tema, una hoja de problemas, un
  parcial, lecciones traducidas y otras por traducir, y un README que cuenta
  cómo está organizado. Es tuyo para tocarlo sin miedo.
- **El recorrido guiado enseña la aplicación entera**, no solo el carril: una
  asignatura y su curso por dentro --con dónde se congela una versión--, un
  documento con sus pestañas y sus salidas, la biblioteca con sus filtros, y
  una lección con sus idiomas y lo que se compila. Va de pantalla en
  pantalla, se puede ir hacia atrás y al acabar te deja donde estabas.
- **La bienvenida, renovada**: centrada, con los dibujos en movimiento y un
  paso para elegir cómo empezar. Si el sistema pide menos movimiento, se
  queda quieta.
- **Los idiomas de cada repositorio, más claros en Ajustes.** Los que tiene se
  ven como etiquetas, los demás se añaden desde un desplegable, y quitar uno
  pregunta antes. Los que no se pueden quitar llevan un candado y dicen por
  qué.
- **Snippets de LaTeX, en Ajustes.** Lo que la barra del editor escribe
  alrededor de lo que marcas --un teorema, un «solo diapositivas», una caja
  tuya-- tiene ahora su propio gestor: se buscan, se filtran, se ordenan
  arrastrando y cada uno dice en qué repositorios se ofrece. Los de Didacta
  siguen ahí y se pueden retocar; los tuyos se crean con un editor que
  **compila la vista previa mientras escribes**, en apuntes o en diapositivas,
  y avisa antes de guardar una definición que no compila.
- **Cajas propias sin escribir LaTeX.** «Caja de teorema» crea un entorno con
  el mismo aspecto que los de Didacta --su pestaña, su número, su color--
  eligiendo solo el título y el color. Lo que define un snippet llega a todo
  lo que se compila en su repositorio, y en ningún otro.
- **El desplegable de entornos es un selector con buscador.** Se escribe para
  filtrar, se elige con las flechas y se aplica con Intro. Ofrece los snippets
  del repositorio del fichero, y arriba del todo, **quitar** el que rodea al
  cursor sin tocar lo de dentro.
- **Un snippet que deja de cuadrar se avisa en la barra**: uno de otro
  repositorio, que ahí compila y aquí no, o uno que ha perdido los argumentos
  que lleva.
- **Los snippets que no coinciden entre dos repositorios** salen en «Entre
  repositorios», con en qué difieren y un botón para quedarse con uno.
- **Traducir en tanda cuesta lo que dice antes de pulsar.** El diálogo
  cuenta los caracteres que se van a mandar y lo que costarían a la tarifa del
  proveedor, sin contar lo que ya está en la memoria. **Detener** para antes
  de la siguiente lección y guarda lo ya traducido, y toda la tanda queda en
  un solo cambio por repositorio (antes, dos por lección). También traduce el
  título de cada lección.
- **Dos estados a la vista**: una traducción está **sin revisar** o
  **revisada**. «Traducida» y «original» se eligen solo con la interfaz
  completa.
- **Aprobar y siguiente.** Encima de una traducción sin revisar, un botón la
  da por revisada --con lo corregido, en un solo cambio-- y abre la siguiente
  sin revisar en el mismo idioma.
- **Lado a lado, el original no se toca por error**: mientras se revisa una
  traducción es de solo lectura, y se desplaza a la vez que ella.
- **Las fórmulas que no coinciden con el original se avisan** en la traducción,
  con su línea. Es lo único que tiene que ser idéntico en los dos idiomas, y un
  error ahí compila y dice otra cosa.
- **Una traducción desactualizada dice qué ha cambiado en el original**:
  encima del texto, un botón enseña la diferencia entre el original que se
  revisó y el de ahora.
- **Valenciano de verdad, y gratis, con Apertium.** Google y Azure traducen
  a catalán central; Apertium distingue el valenciano («seua», «duració»), no
  pide clave y no cuesta nada. Se enciende en Ajustes → Traducción
  automática.
- **Un glosario de traducción**, en Ajustes → Traducción automática: los
  términos que una traducción tiene que respetar. Lo que no sale así se avisa
  al traducir con la máquina.
- **La memoria de traducción aprende de quien revisa**: al aprobar una
  traducción corregida, lo corregido sale corregido la próxima vez.
- **Los PDF dicen qué son**: el título, el autor, la asignatura y el idioma
  van en sus propiedades, que es lo que enseña el lector de PDF, lo que indexa
  un buscador y lo que necesita un lector de pantalla para pronunciar bien.
- **La letra, siempre nítida.** Latin Modern en lugar de Computer Modern: es la
  misma letra, pero en una máquina sin el paquete cm-super ya no sale en mapas
  de bits borrosos.
- **Una lección que falta en un idioma sale en su original.** Si no existe en
  el idioma que se compila, se usa el suyo --el `reference:` de la lección-- y
  no el primero de una lista fija, y se prueban todos los idiomas de Didacta.
- **La frase que sigue a una fórmula destacada ya no empieza sangrada**: sin
  línea en blanco, continúa el párrafo, como detrás de una ecuación.
- **La coma decimal en todos los idiomas que la usan.** El castellano y el
  gallego ya escribían «3,14»; el valenciano, el catalán, el francés, el
  alemán, el italiano, el portugués y el euskera salían con «3.14». Ahora
  solo el inglés lleva punto. Y «25 %», con su espacio, donde la norma lo
  pide. El punto entre letras --«$f.g$»-- sigue siendo un punto.
- **La comprobación de herramientas avisa si falta `biber`**, que es lo que
  compone la bibliografía de un documento que cita, con la orden para
  añadirlo. Y al instalar TinyTeX, Didacta ya se lo pide a `tlmgr`.
- **Un curso nuevo sin sorpresas.** Al crearlo copiando otro, una casilla
  marcada congela antes el de origen «tal como quedó», en todos sus
  repositorios; y si tiene documentos vinculados, el diálogo avisa de que el
  nuevo los comparte y de que lo que se cambie en uno cambia en los dos.
- **Copiar un curso académico se lleva sus temas.** Antes los documentos del
  curso nuevo llegaban sueltos, fuera de los temas en que estaban.
- **Un examen o una hoja, a partir de los problemas, de una vez.** En el curso,
  «Examen u hoja de problemas»: el título, el tema y los problemas --solo
  problemas, por carpeta, con los que ya salieron en un examen de la asignatura
  marcados y, si se quiere, fuera de la lista-- y un solo guardado. Antes eran
  más de quince pasos y dos commits.
- **Los documentos creados desde Didacta compilan.** Al guardarlos se escribe
  también su `.tex`, en el mismo cambio; sin él el motor los saltaba y no
  salía ningún PDF.
- **«Examen» es un tipo de documento**, con sus dos salidas: el examen y la
  hoja de corrección.
- **Congelar desde el menú del curso congela todos sus repositorios.** Antes,
  desde ahí, solo el primero, y la otra mitad de una asignatura repartida
  seguía cambiando por debajo.
- **Comparar dos versiones enseña solo las lecciones del curso.** Antes metía
  las de todo el repositorio, y lo que había cambiado en las del curso se
  perdía; las demás se cuentan al pie.
- **Añadir una lección a un tema sin abrir el editor.** Debajo de la
  composición, «Añadir una lección» la pone al final en un solo guardado.
- **«Compilar ahora» al guardar una composición**, en el aviso de guardado:
  abre la pestaña de compilar y compila el tema.
- **Exportar avisa de lo que está viejo**, con sus nombres, y compila antes
  solo eso: repartir un PDF de antes de la última corrección ya no pasa sin
  que se note.
- **Exportar recuerda la carpeta de cada asignatura**, y la abre ahí la
  próxima vez.
- **Un .zip para el aula virtual** al exportar, que Moodle descomprime en un
  recurso Carpeta. También desde la terminal, con `--zip`.
- **Los PDF exportados se llaman en el idioma del reparto**: «Tema 1 -
  Apunts.pdf», y no «Tema 1 - notes - va.pdf». La carpeta de lo que no tiene
  tema, también: «Sense tema».
- **Menos iconos por fila.** Un documento enseña el PDF, ▶ y «…»; exportarlo,
  cambiarle el título, darlo en otro sitio y quitarlo están en «…». Ocultar
  una asignatura o un curso, también en su «…»; el ojo solo se ve en lo que
  está oculto, para volver a enseñarlo. Y la papelera de la cabecera de un
  curso académico pasa a su «…», junto a congelarlo.
- **«Duplicar» cumple lo que dice.** Un tema vinculado deja de estarlo en la
  copia, que antes seguía siendo el mismo tema; «Duplicar también las
  lecciones» le da las suyas; y el nombre que se elige para la copia se usa.
- **El historial, para quien no usa git.** «Recuperar esta versión» enseña qué
  cambiaría y lleva el texto de entonces al editor como un cambio sin
  guardar; «Comparar con ahora» dice qué ha cambiado desde entonces; dentro de
  cada línea cambiada se marcan las palabras que cambiaron --también al
  guardar--; y el hash de cada versión solo sale con la interfaz completa.
- **Deshacer.** Quitar una asignatura, un curso académico o un documento, y
  cualquier otro guardado de un curso, se deshace desde el aviso de después.
  Y «Cambios recientes», en la cabecera de Asignaturas, lista lo último que se
  ha guardado con un «Deshacer» en cada cambio, que solo actúa si nadie ha
  vuelto a tocar esos ficheros.
- **Una carpeta de reparto**, opcional, en Ajustes → Guardar y sincronizar:
  una de OneDrive, Drive o Nextcloud. Con ella, cada curso académico tiene
  «Publicar» en su «…», que exporta lo del estudiante a su carpeta dentro de
  esa sin preguntar dónde.
- **El motor va con la versión de la aplicación.** El que descarga Didacta
  es el de su misma versión, y al actualizar la aplicación se pone en la
  nueva: los arreglos de LaTeX llegan con ella. Ajustes dice de qué versión es
  el motor y, si es uno propio que no coincide, ofrece ponerlo en la de la
  aplicación.
- **Revisar**, en la biblioteca y antes de exportar: busca lo que compila mal
  o no compila --una orden del castellano en el valenciano, un entorno que no
  define nadie, una figura que falta, un «??», una diapositiva que se sale,
  una traducción desactualizada-- y lleva a cada cosa con **Abrir**. Se
  pueden pedir más: fórmulas distintas entre idiomas, lecciones sin usar,
  líneas que se salen y coma decimal.
- **Guardar y traer, más ligeros.** El catálogo se recarga una vez aunque lo
  pidan varios a la vez, y sin volver a comprobar el índice que la operación
  acaba de dejar hecho: es un proceso del motor menos por repositorio en cada
  guardado. Y después de traer de GitHub ya no se regeneran a la fuerza todos
  los índices ni se lee el catálogo dos veces.
- **La ventana ya no se congela al leer el catálogo.** El índice se lee en otro
  hilo, y con varios repositorios, todos a la vez: se tarda lo que el más
  grande y no la suma.
- **Arrancar sin esperas.** Con quien entró la última vez apuntado, Didacta
  abre sin esperar a GitHub --esperaba hasta seis segundos en cada arranque--
  y se lo pregunta después; si dice que la credencial ya no vale, se cierra la
  sesión entonces. Los repositorios se abren todos a la vez. Y la pantalla de
  carga dice qué está haciendo.
- **Menos trabajo en cada redibujado.** La aplicación ya no se reconstruye
  entera con cada aviso de la sesión, el tema se hace una vez por paleta, el
  contador de Traducción no reordena dos mil lecciones cada vez, y buscar una
  lección por su ruta va por un índice en lugar de recorrerlas todas. Y lo
  que solo le importa a una parte de la pantalla ya no redibuja las demás:
  plegar un tema, marcar una asignatura, cambiar un ajuste, guardar o que
  empiece y acabe una compilación repintan lo que lo enseña y nada más.
- **Preparada para entrar como GitHub App**: llegar solo a los repositorios
  que elijas, con una sesión que se renueva sola cada ocho horas. Las
  sesiones de ahora siguen valiendo tal cual. Ajustes → Cuenta y
  repositorios dice además, por fin, qué repositorio no se pudo abrir y por
  qué.
- **Apuntes accesibles.** Con *PDF accesibles* en Ajustes, los apuntes, las
  hojas y los exámenes salen etiquetados (PDF/UA): con su estructura, su
  idioma y el texto alternativo de las figuras, para leerlos con un lector de
  pantalla. Y al exportar un curso, *También: los apuntes en HTML* deja al lado
  de cada PDF una página que se agranda y se lee en voz alta, fórmulas
  incluidas, con lo mismo que lleva su PDF y nada más. Los PDF muestran su
  título en la barra del visor, y no el nombre del fichero.
- **El texto alternativo de las figuras**, `alt={…}`, en una imagen o en un
  dibujo de TikZ: el editor lo propone al escribir `\includegraphics`, se
  traduce con la lección, y la revisión dice qué figuras no lo tienen.
- **Compilar en GitHub en cada cambio.** Desde Ajustes → Cuenta y
  repositorios, un clic hace que GitHub compile todo el material de un
  repositorio en cada envío, lo compruebe y ponga el índice al día, y deje los
  PDF en dos paquetes separados: lo que se reparte, sin soluciones, y lo del
  profesor. El repositorio de ejemplo lo trae de salida.
- **Crear el repositorio de ejemplo ya no falla al enviarlo.** GitHub
  rechazaba su primer envío porque trae un workflow, y Didacta no pedía el
  permiso para eso. Ahora lo pide al entrar; con una sesión de antes, el
  ejemplo se crea sin sus workflows, y para añadirlos basta con volver a
  entrar.
- **La paleta de órdenes: ⌘K (Ctrl+K).** Escribe y ve a una lección, a un
  curso, a un documento o a una sección de Ajustes, o lanza una orden
  --actualizar, enviar, la apariencia, el tamaño del texto-- sin buscar el
  botón. Lo de la pantalla en la que estás sale primero: en una lección,
  guardar, compilar, editar en otro idioma o moverla; en un curso, compilar
  lo desactualizado o crear un tema.
- **Buscar con una errata.** «nomrados» o «difrenciales» encuentran lo mismo
  que bien escritas, en la biblioteca y al añadir lecciones o problemas: una
  letra de más, de menos, cambiada o dos intercambiadas, en palabras de cinco
  letras o más que no estén tal cual en ningún sitio. Lo parecido va al
  final, y se cuenta aparte.
- **La biblioteca, más fluida al buscar.** El texto de búsqueda de cada lección
  se prepara una vez, la lista espera 120 ms a que se deje de teclear, y un
  tema con cuatrocientos problemas construye solo las tarjetas que se ven.
- **La carpeta de compilación, a la vista**: Ajustes → Herramientas dice cuánto
  ocupa la de cada repositorio y la vacía de un botón. En el material de
  Análisis eran 440 MB. Y `didacta clean`, lo mismo desde el terminal.
- **Versiones de prueba**, en Ajustes → Actualizaciones: quien las pide recibe
  cada versión antes de publicarla para todos, marcada como de prueba, y pasa
  a la final en cuanto sale.
- **Una web del curso**: `didacta site curso@año` deja en una carpeta los PDF
  que se reparten y una página que los enseña por idioma y por tema, lista
  para GitHub Pages. El repositorio de ejemplo trae el workflow que la
  publica.
- **Mejor en Windows y en Linux.** Los ficheros guardan siempre el fin de
  línea `\n`, así que un cambio hecho en Windows ya no sale como si hubiera
  cambiado la lección entera; Didacta usa el git que encuentra la
  comprobación de herramientas y no el primero del PATH; y en Linux se entera
  de los cambios hechos en otro programa también dentro de las subcarpetas.
- **Un informe de diagnóstico**, en Ajustes → Ayuda: la versión, el sistema,
  cada orden del motor y de git con su resultado, lo que contestó GitHub y los
  errores que Didacta se tragó para seguir, sin claves ni contraseñas, listo
  para pegar en una incidencia. También queda en un fichero, dos de un mega
  como mucho.
- **Reordenar los documentos de un curso ya no cambia de más el
  `year.yaml`.** Un documento de una línea pegado al siguiente ganaba una línea
  en blanco al moverlo, y el cambio guardado enseñaba algo que nadie había
  hecho.
- **Ayuda en la web**: una página, «Cuando algo falla», con los errores que
  más se ven y qué hacer con cada uno --«Undefined control sequence», un
  `.sty` que falta con la orden de cada distribución, MiKTeX sin Perl, la
  carpeta ocupada, OneDrive, los cambios que chocan--, y un glosario de las
  palabras de Didacta para quien no es técnico. La página de Ajustes sigue
  ahora las secciones de la aplicación, en el mismo orden y con las mismas
  direcciones.
- **La ortografía, en «Revisar».** Una comprobación más de las que se piden:
  las palabras que el diccionario de cada idioma no conoce, con su lección, su
  línea y la sugerencia, sin mirar dentro de las fórmulas ni de las órdenes de
  LaTeX. Usa hunspell y los diccionarios que haya en el sistema --el
  valenciano, con el suyo o con el catalán--, y si faltan lo dice. Las
  palabras buenas que el diccionario no sabe, como «Banach», se apuntan en
  `shared/palabras.txt`. Desde el terminal, `didacta check --with spelling`.
- **El tamaño del texto**, en Ajustes → Apariencia: del 85 % al 150 %, para
  el proyector del aula o una pantalla pequeña. Y desde cualquier pantalla con
  ⌘+ y ⌘− (Ctrl en Windows y Linux, y también el «+» de un teclado español);
  ⌘0 lo deja en el normal.
- **Un aviso al terminar de compilar**, si se enciende en Ajustes →
  Herramientas: una notificación del sistema cuando acaba, con si ha salido
  bien o cuántos documentos tienen errores. Solo si mientras tanto estabas en
  otra ventana.
- **La interfaz Esencial, más ligera.** Lo de quien mantiene el repositorio
  del departamento pasa a la Completa (Ajustes → Apariencia → Interfaz): los
  apartados Bloques y plantillas y Servidor MCP, poner los ids, mover un tema
  y gestionar su vinculación, copiar el comando de compilar y «Entre repos» en
  la columna de la izquierda, que con la Esencial sale solo cuando hay algo
  que mirar. Las herramientas, si están todas, se enseñan en una línea; y la
  ventana de compilar y sincronizar dice qué está haciendo y cómo ha acabado,
  con el registro entero detrás de «Ver detalles» --y a la vista si algo
  falla sin decir por qué--.
- **Las barras de la biblioteca enseñan lo traducido.** Salían siempre grises,
  como si no hubiera nada hecho, aunque la leyenda de al lado dijera «58 al
  día»: el tramo verde y el ámbar medían cero de alto.
- **Un aviso que sobraba al lado de la composición.** Las salidas de un tema
  decían que compilar necesita LaTeX y que un navegador no lo tiene, también
  en la aplicación de escritorio, que compila. Ahora solo lo dice la web.

## 0.2.1

- **Quitar un repositorio pregunta qué hacer con su carpeta.** Se puede dejar
  en el disco, como siempre, o mandarla a la Papelera con todo lo que tiene
  dentro. Antes de tirarla dice si tiene cambios sin guardar o sin enviar a
  GitHub, y nunca la borra del todo: desde la Papelera se recupera.
- **La carpeta de cada repositorio se abre en el Finder** desde Ajustes, con
  el botón que hay al lado de su nombre.
- **Se puede empezar de cero**: Ajustes → Empezar de cero → Restablecer. Borra
  de este ordenador la sesión de GitHub, los ajustes y la lista de
  repositorios, y la bienvenida vuelve a salir. Tirar la aplicación a la
  Papelera no lo hace, porque el sistema guarda los ajustes aparte.
- **Didacta se identifica como `io.github.franjfal.didacta`**, el nombre de su
  web, y no como `es.uv.didacta`. Los ajustes y las plantillas se traen solos
  la primera vez; en Linux hay que volver a entrar en GitHub una vez. En
  Windows, el editor que sale en «Aplicaciones instaladas» pasa a ser Javier
  Falcó.

## 0.2.0

- **Clonar un repositorio dice por dónde va.** Hasta ahora ponía «Clonando…» y
  se quedaba así hasta el final, que en un repositorio grande son minutos y
  desde fuera parece una aplicación colgada. Ahora se ve una barra con la fase
  --contando, recibiendo, resolviendo--, cuánto se lleva bajado y a qué
  velocidad, y cuánto tiempo lleva. Con varios repositorios, cuál va de
  cuántos. Lo mismo al descargar el motor.

## 0.1.0 — 2026-09-17

- **Didacta abre por las asignaturas.** Abría por la biblioteca, que contesta
  «¿qué tengo de esto?» -- una pregunta que se hace a ratos. Al abrir se viene
  a preparar una clase, y eso empieza en la asignatura que se da mañana.
- **Las asignaturas y los cursos académicos se pueden ocultar**, uno a uno.
  Ocultar no es quitar: siguen en el repositorio, siguen compilando y siguen en
  la biblioteca; lo que cambia es la lista, que después de unos años son veinte
  asignaturas de las que se dan tres. Arriba se elige qué se mira: las que doy,
  las ocultas --para deshacerlo-- o todas.
- **Y se pliegan**: el título de una asignatura es un botón, y plegada enseña
  cuántos cursos lleva dentro sin ocupar la pantalla con ellos.
- **Marcar ya no reordena.** Lo marcado subía al principio y era peor: la lista
  dejaba de estar donde se aprendió que estaba, y marcar una asignatura movía
  otras cuatro de sitio. La estrella dice «esta me importa»; para no ver lo que
  no se da está ocultarla. De paso, «el primer curso» vuelve a querer decir «el
  último que se dio», que es de lo que se fía la pantalla para marcarlo.
- **Lo que se está mirando se queda puesto**, y viaja de un ordenador a otro
  con el resto de preferencias. Quien se pone a ordenar la lista se queda un
  rato en «las ocultas»; volver de un curso y encontrarse otra vez «las que
  doy» convertía esa tarde en un baile de clics.

- **Exportar deja de estar escondido detrás de unos puntos suspensivos.** El
  botón está en la fila del curso, al lado de la estrella: entrar, darle y
  decir en qué carpeta.
- **Y se puede exportar un documento suelto**, desde su fila del listado del
  curso, para cuando lo que hay que subir al aula virtual es solo el Tema 3.
  Aparece si tiene algo compilado, que es cuando hay algo que copiar.
- **El visor de PDF guarda una copia** de lo que se está mirando, con el
  nombre que le pone el motor. Antes había que abrirlo en el visor del sistema
  y guardarlo desde allí.
- Exportar **no pide permiso de escritura**: copia lo compilado y no toca el
  repositorio, así que también se lleva material quien solo lo tenga para leer.

- **Un botón para contar un problema**, abajo a la derecha, al lado del de
  actualizar. Abre las incidencias de Didacta en GitHub con la versión y el
  sistema ya escritos: un informe sin eso necesita un viaje de ida y vuelta
  antes de poder mirarse, y quien lo escribe no tiene por qué saber cuál es su
  versión. Está ahí y no en Ajustes porque el momento en que se encuentra un
  fallo es el momento en que se está usando la aplicación.

- **Guardar decía que había guardado y la pantalla seguía igual.** Cambiar el
  título de un grado --o de un tema, o de un documento-- escribía el fichero y
  no se veía: lo que Didacta escribe son ficheros YAML y lo que lee son los
  índices que el motor saca de ellos, y nadie los regeneraba. Ahora recargar
  el catálogo pone el índice al día primero, así que lo que se guarda se ve. El
  cambio estaba en el disco todo el tiempo; lo que faltaba era enseñarlo.
- **Un grado se puede declarar y dejar de declarar en cada repositorio**, desde
  la misma pantalla de grados, con una casilla por repositorio. Quitarlo del
  último no pierde nada: sus asignaturas salen enteras, sin agrupar, y la
  pantalla las enseña como «nombradas y sin declarar».

- **Las quince salidas dejan de estar escritas en el programa.** Cambiar el
  margen de los apuntes o meter un paquete propio era editar el LaTeX de
  Didacta. Ahora un repositorio puede declarar sus **plantillas**: una salida
  con su clase de documento, sus opciones, sus ejes y **su propio preámbulo**,
  que se lee al final del de Didacta y por tanto puede redefinir lo que
  Didacta acaba de definir.
- **Cada bloque dice con qué se compila lo suyo**, y cada documento y cada
  lección pueden quedarse con menos sin tocar el bloque. Una lista vacía
  siempre quiere decir «lo que toque» y nunca «nada»: no hay forma de dejarse
  material sin salidas sin haberlo pedido.
- **Una plantilla se puede apagar sin borrarla.** Deja de compilarse y se
  queda declarada, con su cabecera, para el curso que vuelva a hacer falta.
- **Nada de esto cambia lo que ya compilaba.** Un repositorio que no declara
  ninguna plantilla sigue sacando las quince salidas de siempre, y una
  plantilla que se llame como una de ellas la sustituye solo cuando compila
  Didacta: `pdflatex master.tex` a mano, en un editor y con SyncTeX, sigue
  dando lo mismo que daba.
- Y se declaran en un repositorio y las usan todos, como los bloques: la
  teoría y los problemas están repartidos en dos, y el bloque de uno puede
  compilarse con la plantilla que declara el otro.
- **Todo eso se toca desde Ajustes → Plantillas**: ver las que hay, apagar las
  que no se sacan, renombrarlas, duplicarlas y **escribir su cabecera de LaTeX
  a mano**. Editar una de las que trae Didacta la escribe en el repositorio que
  elijas, y lo dice antes de hacerlo: a partir de ahí manda la tuya.
- **Una plantilla puede guardarse en el programa** en vez de en un repositorio,
  para lo que es tuyo y no de la asignatura, o para cuando el material es de
  otra persona. Lo que se guarda ahí **no lo protege nadie** --ni git, ni la
  sincronización-- así que Ajustes lo dice y trae los dos botones que hacen
  falta: copiar las plantillas a una carpeta y traerlas de una.
- **Cada bloque elige con qué se compila lo suyo**, y cada tema y cada lección
  pueden apartarse desde su propia pantalla. Lo que viene marcado al compilar
  ya no sale de una tabla escondida en el motor: sale de lo que hayas
  configurado.

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
- **Lo que se añade a la composición sale en el PDF.** Un apartado o un
  subapartado nuevo se guardaba, se veía en la pantalla de composición y el PDF
  seguía sin él: la composición vive en `year.yaml` y lo que compila LaTeX es el
  `.tex` de al lado, y nadie los ponía de acuerdo. Ahora compilar lo hace, y
  `didacta check` avisa cuando el `.tex` se ha quedado atrás. El fichero se
  respeta: sólo se reescribe la lista de unidades y apartados, lo desactivado
  sigue desactivado, y si alguien había escrito LaTeX ahí en medio no se toca y
  se dice.
- **Un icono de información en cada lección y en cada tema.** Contesta las dos
  preguntas que se hacen con algo delante y que no son de su contenido: dónde
  más se da esto, y qué versiones tengo guardadas. Lo primero estaba enterrado
  en el panel de la derecha de una lección --que se puede tener cerrado, y que
  no existe en un tema-- y lo segundo estaba en la pantalla de Asignaturas, a
  dos pantallas de donde te lo preguntas. Desde ahí se salta a cada sitio, se
  ven y se crean versiones congeladas, se da una lección en otro tema y se
  parte en dos lo que esté vinculado en varios sitios. Las versiones congeladas
  son de una asignatura y no de un fichero, así que una lección que se da en
  cuatro sale con los cuatro juegos y el nombre de cada asignatura delante.
- **Los botones de vinculación de una lección ya no se salen del panel.** Con
  la lección dada en dos sitios eran dos, no cabían en los trescientos y pico
  píxeles del panel, y el que decía «Gestionar vinculación» quedaba fuera de la
  pantalla. Ahora viven en el icono de información, que es donde se buscan.
- **El visor de PDF es un visor de verdad.** Trae un lateral con el índice del
  documento --los apartados, para saltar a uno-- y las miniaturas de las
  páginas; el número de página se escribe en lugar de llegar a la 84 a base de
  flechas; y están el zoom y los tres ajustes de siempre: al ancho, al alto y
  página entera. A la derecha, una barra de desplazamiento que se arrastra y va
  diciendo por qué página pasa. Con dos idiomas abiertos lado a lado, todo eso
  mueve los dos a la vez, que es lo que permite compararlos.

- **Los teoremas y las definiciones vuelven a ir en una caja.** Con su marco de
  color, su fondo teñido y el nombre --«Definición 1.2 (Espacio normado)»-- en
  una etiqueta montada sobre el borde de arriba, que es como se veían antes de
  la migración. En los apuntes la caja va suave, porque una página lleva ocho
  seguidas y se lee durante una hora; proyectada va con más contraste y una
  sombra corta, para que se lea desde el fondo del aula. La caja se parte entre
  páginas: un teorema largo ya no se sale del papel.
- **Las notas del profesor, los objetivos y los recuadros sin etiqueta van
  igual**, cada uno con su color. Una página donde el teorema lleva marco y la
  nota didáctica lleva una raya se lee como dos documentos pegados.
- **Las presentaciones tienen portada.** Una banda de color de canto a canto
  con el título de la asignatura en blanco, el logotipo y los datos del curso
  abajo: es la diapositiva que está proyectada mientras la gente entra y se
  sienta. Las páginas de apartado dicen además de qué apartado se trata, y el
  pie remata con las franjas escalonadas de siempre.
- **La portada de los apuntes ya no lleva el encabezado puesto** --repetía el
  título dos centímetros por encima del título-- ni el número de página. Y la
  institución se compone debajo de la ficha del curso, no a su derecha.

- **Los apartados de un documento salen en el idioma que se compila.** El
  valenciano de un tema venía con el contenido traducido y los encabezados en
  castellano: media traducción, que en clase es peor que ninguna porque no se
  ve hasta que está proyectada. Los títulos estaban escritos en los dos
  idiomas desde el principio; lo que pasaba es que el documento se quedaba con
  uno. Ahora los lleva todos y elige al compilar, así que el mismo documento da
  el castellano con encabezados castellanos y el valenciano con valencianos, y
  no hay dos ficheros que mantener de acuerdo.

- **Traer, enviar y confirmar abren el terminal**, el mismo que se abre al
  compilar. Un envío con setecientos ficheros esperando tarda un rato largo, y
  hasta ahora eso era un botón apagado y nada más: desde fuera no se distingue
  de una aplicación colgada, así que se pulsa otra vez. Ahora se ve lo que está
  haciendo --qué repositorio va, cuántos objetos lleva contados, cuánto lleva
  subido-- y la ventana se quita sola cuando termina bien. Si algo falla se
  queda, que es cuando hay que leerla.
- **Lo que falta por confirmar se cuenta aparte de lo que falta por enviar.**
  La insignia de enviar sumaba las dos cosas y decía «697 sin enviar» sobre un
  repositorio que no tenía ni un commit pendiente: lo que había eran 697
  ficheros que no estaban todavía dentro de ningún commit. Ahora cada botón
  lleva su número, y dicen cosas distintas porque son cosas distintas.
- **Y confirmar está siempre que haya algo que confirmar**, también con los
  commits automáticos puestos. Se daba por hecho que con ellos no quedaba
  nunca nada suelto, y no es verdad: lo que se escribe fuera de Didacta --otro
  editor, una carpeta de lecciones copiada, material traído de otro sitio--
  llega al disco sin pasar por aquí, y ahí se quedaba, sin botón que lo
  arreglara.
- **El diálogo de confirmar deja elegir qué entra.** Lo pendiente puede ser un
  fichero o pueden ser setecientos, y meter setecientos en un commit que dice
  una sola cosa es tirar su historial antes de tenerlo. Salen agrupados por
  repositorio, con un filtro por ruta --escribe «taylor» y quedan los de
  Taylor-- y la casilla del repositorio marca y desmarca lo que se ve. Así una
  tarde de trabajo sale en cinco commits que se pueden leer, en vez de uno que
  no.
- **Compilar funciona en Windows.** No había funcionado nunca: la aplicación
  lanzaba el motor como en macOS y en Linux, y Windows no sabe ejecutar un
  script de Python sin decirle con qué. Ahora busca el intérprete --el
  lanzador `py`, o `python`-- también donde lo deja el instalador de
  python.org cuando no se marca la casilla del PATH. Y si lo único que hay es
  el `python.exe` que trae Windows, que no es un Python sino un acceso directo
  a la Microsoft Store, lo dice en lugar de abrir la tienda.
- **«Abrir en el visor» y «Enseñar en la carpeta» funcionan en Windows y en
  Linux.** Sólo estaban hechos para macOS, y en los otros dos el botón estaba
  pero daba un error.

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
