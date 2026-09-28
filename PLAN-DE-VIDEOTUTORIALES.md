# Plan de videotutoriales de Didacta

*28 de septiembre de 2026, sobre la versión 0.2.1 más lo que hay sin publicar
(la sección «Próxima» del CHANGELOG). Sale de recorrer la documentación de la
web pantalla por pantalla y del repositorio de ejemplo.*

Una colección de vídeos cortos para que alguien que no ha abierto nunca
Didacta aprenda a usarla **y entienda por qué funciona como funciona**. No es
un curso para verlo de principio a fin: es una biblioteca en la que cada vídeo
contesta una pregunta concreta, con tres puertas de entrada para encontrar el
que hace falta en menos de un minuto.

**Las cifras.** 77 vídeos en 12 rutas, de uno a tres minutos, unas dos horas y
media en total. Nadie los ve todos: la ruta del primer día son **quince
minutos**, y cada perfil tiene la suya, de treinta y cinco minutos a dos
horas.

---

## 1. El criterio

Ocho reglas. Todo lo demás del plan sale de ellas.

1. **Un vídeo, una tarea.** El título es la tarea en infinitivo --«Corregir
   una errata y guardarla»--, que es lo que se escribe al buscar. Si el título
   necesita un segundo verbo que no sea parte de la misma tarea, son dos
   vídeos.
2. **De uno a tres minutos; ninguno pasa de cuatro.** Si pasa, se parte. Un
   vídeo corto se termina, se busca mejor, y cuando cambia la pantalla se
   vuelve a grabar en una tarde.
3. **Primero el resultado.** Los cinco primeros segundos enseñan lo que habrá
   al acabar --el PDF, la lista ordenada, la carpeta exportada-- y dicen «al
   terminar sabrás…». Nada de presentaciones.
4. **Todo sobre el repositorio de ejemplo.** *Cálculo I, 2026-2027*: el que
   crea **Probar con un ejemplo**. Cualquiera puede repetir lo que ve con lo
   mismo que ve, y cada vídeo dice de qué pantalla parte.
5. **Con las palabras de la aplicación.** «Cambio guardado», no *commit*;
   «la copia en tu ordenador», no *clon*; «traer» y «enviar». Los botones se
   nombran exactamente como están escritos. El [glosario](web/docs/ayuda/glosario.md)
   manda.
6. **Esencial primero.** Se graba con la interfaz *Esencial*, que es la de
   salida. Lo de *Completa* va en su propia ruta y lleva la marca.
7. **Cada vídeo deja un porqué, en una frase.** Didacta toma decisiones que
   no son las de otros programas --quitar comenta en lugar de borrar, la copia
   del profesor no existe en la del alumno, desactualizada es peor que sin
   traducir--. Contarlas es la diferencia entre saber pulsar un botón y
   entender la aplicación. Es la línea **La idea** de cada ficha.
8. **Accesibles.** Subtítulos en castellano, valenciano e inglés, transcripción
   publicada al lado, y nada dicho solo con un color: «en ámbar,
   desactualizada».

---

## 2. Cómo se encuentra un vídeo

### Tres puertas

**La ruta del primer día.** Siete vídeos seguidos, quince minutos, de
instalar a tener un PDF delante. Es lo que se ofrece a quien llega.

**El índice por pregunta** ([§ 6](#6-índice-por-pregunta)). «Quiero hacer un
examen», «la traducción sale en ámbar», «sale un aviso raro». Agrupado por el
momento en que se hace la pregunta: al empezar, preparando clase, traduciendo,
repartiendo, cuando algo va mal, a final de curso.

**La ayuda de cada pantalla.** El vídeo se encuentra donde surge la duda, no
en otro sitio (ver [§ 8](#8-dónde-viven)).

### Cómo se nombran

Cada vídeo tiene un código --una letra por ruta y un número-- y un título:

```
Didacta · E4 · Componer un tema
```

El código es para referirse a él («mira el E4») y para ordenar; el título es
lo que se busca. El fichero sigue el mismo patrón: `E04-componer-un-tema.mp4`.

### Tres marcas de nivel

| Marca | Qué quiere decir |
|---|---|
| *(sin marca)* | Para todos, con la interfaz de salida |
| **Opcional** | Enseña un interruptor de Ajustes que viene apagado |
| **Completa** | Necesita *Ajustes → Apariencia → Interfaz: Completa*; es de quien mantiene el repositorio del departamento |

Son las mismas capas que usa la aplicación (ver
[PLAN-DE-MEJORAS.md § 1](PLAN-DE-MEJORAS.md)): quien no ha visto nunca
Didacta no tiene por qué tropezar con plantillas o con el servidor MCP.

---

## 3. Qué vídeos ve cada uno

| Si tú… | Mira | Tiempo |
|---|---|---|
| **Das clase con material que ya existe** --el del departamento, el de otro compañero-- | A · C1 · C2 · E1 · F1–F4 · H1 · I1 | unos 35 min |
| **Traduces o revisas traducciones** | A · B4 · C3 · D1 · D2 · G | unos 35 min |
| **Escribes tus apuntes y preparas tus asignaturas** | A · B · C · D · E · F · H · I · J | casi dos horas, en varios días |
| **Coordinas el repositorio del departamento** | Todo, y la ruta L | dos horas y media |

La ruta **A** es de todos, y la **K** (ajustes) se consulta cuando hace falta.

---

## 4. El mapa

| Ruta | Contesta | Vídeos | Min | En la web |
|---|---|:---:|:---:|---|
| **A · Empezar** | ¿Cómo lo instalo y tengo mi primer PDF? | 7 | 15 | [Empezar](web/docs/empezar/index.md) |
| **B · Cómo piensa Didacta** | ¿Por qué funciona así? | 5 | 10 | [Cómo funciona](web/docs/conceptos/index.md) |
| **C · Encontrar material** | ¿Dónde está lo que escribí? | 3 | 6 | [La biblioteca](web/docs/app/biblioteca.md) |
| **D · Escribir una lección** | ¿Cómo edito, y qué pongo dentro? | 12 | 22 | [La unidad](web/docs/app/unidad.md) · [Escribir](web/docs/escribir/index.md) |
| **E · Preparar una asignatura** | ¿Cómo monto un tema, una hoja, un examen? | 8 | 14 | [Asignaturas](web/docs/app/asignaturas.md) · [Composición](web/docs/app/composicion.md) |
| **F · Compilar y revisar** | ¿Cómo saco los PDF, y qué hago si fallan? | 8 | 16 | [Compilar](web/docs/app/compilar.md) |
| **G · Traducir** | ¿Qué falta, y cómo lo traduzco? | 7 | 15 | [Traducción](web/docs/app/traduccion.md) · [Idiomas](web/docs/conceptos/idiomas.md) |
| **H · Repartir** | ¿Cómo lo subo al aula virtual? | 4 | 7 | [Exportar](web/docs/app/exportar.md) |
| **I · No perder nada** | ¿Dónde está mi trabajo, y cómo vuelvo atrás? | 6 | 13 | [Historial](web/docs/app/historial.md) · [Congelaciones](web/docs/app/congelaciones.md) |
| **J · El curso que viene y el temario compartido** | ¿Cómo reutilizo sin copiar? | 4 | 10 | [Temario compartido](web/docs/app/vinculos.md) |
| **K · A tu manera** | ¿Cómo la ajusto a mí? | 4 | 7 | [Ajustes](web/docs/app/ajustes.md) |
| **L · Para quien mantiene el repositorio** | ¿Cómo organizo el material de todos? | 9 | 23 | [Ajustes · Completa](web/docs/app/ajustes.md#interfaz) |
| | | **77** | **~157** | |

El orden de las rutas es el de la primera semana: instalar, entender, buscar,
tocar, montar, compilar, traducir y repartir; lo de proteger el trabajo y
reutilizarlo, cuando ya hay trabajo que proteger.

---

## 5. Los vídeos, ruta por ruta

Cada ficha dice qué se aprende (**Sabrás**), desde qué pantalla empieza la
grabación (**Parte de**), el guion en pasos, **la idea** que hay que llevarse
en una frase, lo que suele salir mal (**Ojo**) cuando lo hay, y dónde seguir
leyendo. Los pasos son lo que se ve; la locución no lee la pantalla, cuenta
por qué.

### A · Empezar

La ruta del primer día. Se ve entera y en orden: de un ordenador sin nada a un
PDF compilado dentro de Didacta.

#### A1 · Didacta en dos minutos · 2 min

**Sabrás** qué problema resuelve Didacta y qué vas a poder hacer con ella.

**Parte de** Asignaturas, con el ejemplo abierto.

1. El problema, en diez segundos: las mismas diapositivas, apuntes y exámenes
   copiados en una carpeta por año y por idioma.
2. «Definición de límite», compilada: diapositivas, apuntes y copia del
   profesor, una al lado de otra.
3. La misma lección en inglés, al lado del castellano.
4. El Tema 1 es una lista de lecciones que se reordena arrastrando.
5. Cierre: «se escribe una vez; lo demás se genera».

**La idea:** el contenido se escribe una vez, las asignaturas son
composiciones, los idiomas son variantes de lo mismo y los PDF se generan.

**Más:** [la portada de la web](web/docs/index.md) · sigue en A2.

#### A2 · Instalar Didacta · 1,5 min · tres versiones: macOS, Windows y Linux

**Sabrás** instalarla y abrirla la primera vez sin desactivar ninguna
protección del sistema.

**Parte de** la página de descargas.

- **macOS:** abrir el `.dmg`, arrastrar a Aplicaciones, y la primera vez
  botón derecho → **Abrir**, porque Didacta aún no está firmada por Apple.
- **Windows:** el instalador se instala para tu usuario, sin contraseña de
  administrador; SmartScreen → **Más información** → **Ejecutar de todas
  formas**. Instalar Python desde python.org: el `python.exe` que trae Windows
  solo abre la Microsoft Store.
- **Linux:** `chmod +x` al AppImage y dejarlo donde se quiera, porque es ahí
  donde se actualizará.
- Las tres: se actualiza sola y **pregunta antes**.

**La idea:** el aviso del sistema es por la firma que falta, no por la
aplicación; basta con abrirla una vez desde el menú.

**Ojo:** no hay que desactivar Gatekeeper ni quitar la cuarentena a mano.

**Más:** [Instalar Didacta](web/docs/empezar/index.md).

#### A3 · Entrar con tu cuenta de GitHub · 1,5 min

**Sabrás** entrar sin darle tu contraseña a Didacta.

**Parte de** la bienvenida, recién instalada.

1. **Entrar en GitHub**: sale un código corto, ya copiado.
2. En el navegador, `github.com/login/device`: pegar y autorizar.
3. La ventana se cierra sola; la barra de arriba dice quién ha entrado.
4. Si GitHub pide instalar la aplicación, se eligen los repositorios a los que
   llega.

**La idea:** la contraseña solo se escribe en github.com, y quién puede leer o
escribir cada repositorio lo decide GitHub, no Didacta. Una vez dentro, se abre
también sin conexión.

**Más:** [Entrar y abrir el primer repositorio](web/docs/empezar/primer-repositorio.md).

#### A4 · Abrir tu primer repositorio · 2,5 min

**Sabrás** elegir entre los cuatro caminos, y empezar por el ejemplo para
practicar sin miedo.

**Parte de** el paso de la bienvenida que pregunta cómo empezar.

1. Qué es un repositorio de contenido: `didacta.yaml` y las carpetas
   `content/`, `problems/` y `courses/`, en un esquema.
2. **Probar con un ejemplo**: crea `didacta-ejemplo`, privado, en tu cuenta,
   y lo abre. Es tuyo para romperlo.
3. Los otros tres, diez segundos cada uno: ya está en GitHub (se pueden marcar
   varios), ya está en el disco (se elige la carpeta), empezar de cero (un
   repositorio vacío que Didacta prepara).
4. Dónde queda: `~/Didacta/<nombre>`.

**La idea:** Didacta no guarda tu material; lo guarda GitHub, y tú trabajas en
una copia en tu ordenador.

**Ojo:** nunca dentro de una carpeta de OneDrive, Dropbox o iCloud Drive.

**Más:** [Repositorios de contenido](web/docs/conceptos/repositorios.md).

#### A5 · Dejar el ordenador listo para compilar · 2,5 min

**Sabrás** comprobar git, Python, LaTeX y el motor, e instalar lo que falte.

**Parte de** Ajustes → Herramientas.

1. La lista: para qué sirve cada uno y qué pasa sin él.
2. Falta LaTeX: el botón enseña las opciones con su tamaño. TinyTeX (~100 MB,
   sin contraseña) frente a MacTeX (~5 GB). Lo que termina en otra ventana deja
   un **Volver a comprobar**.
3. **El motor**, de un botón; va siempre en la versión de la aplicación.
4. Con todo en su sitio, la lista se queda en una línea.

**La idea:** Didacta no lleva LaTeX dentro a propósito: tú eliges qué
distribución, y con el tamaño delante.

**Ojo:** si LaTeX está instalado y no lo ve, es el PATH de las aplicaciones;
la pantalla dice dónde ha mirado y deja escribir la ruta.

**Más:** [La distribución de TeX](web/docs/empezar/latex.md).

#### A6 · Conocer la ventana · 2 min

**Sabrás** para qué sirve cada parte de la ventana y dónde está el recorrido
guiado.

**Parte de** Asignaturas.

1. El carril: **Asignaturas** (lo de cada día), **Biblioteca** (cómo se
   busca), **Traducción**, **Ajustes**; los números que llevan; y los dos que
   aparecen solo cuando hacen falta.
2. La barra de arriba: el repositorio con su color, lo que falta por enviar,
   lo que hay en GitHub con **Traerlos**, y el idioma que se mira.
3. La barra de abajo: «Guardado en GitHub · al día».
4. El sol y la luna.
5. Ajustes → Ayuda → **Ver el recorrido guiado**.

**La idea:** dónde va a parar lo que escribes está siempre a la vista.

**Más:** [La aplicación](web/docs/app/index.md).

#### A7 · Tu primer PDF · 2,5 min

**Sabrás** ir de una asignatura a un PDF abierto dentro de Didacta.

**Parte de** Asignaturas → Cálculo I → 2026-2027.

1. Abrir «Tema 1: límites y continuidad».
2. **Compilar**; la tira de abajo dice qué se compila, y la consola lo que va
   haciendo.
3. El PDF se abre como una pestaña más.
4. Manteniendo pulsado **Compilar**: los apuntes en valenciano, lado a lado con
   los de castellano.
5. El aviso: «Teorema de Bolzano» no está en valenciano, así que sale en
   castellano y se dice.

**La idea:** un tema con una lección sin traducir se puede dar igual, y nadie
deja de enterarse.

**Más:** [Los primeros diez minutos](web/docs/empezar/primeros-pasos.md) · sigue
en B1.

### B · Cómo piensa Didacta

Cinco vídeos de ideas, con el ejemplo en pantalla y un esquema sencillo encima.
Son los que convierten «sé dónde está el botón» en «sé qué va a pasar al
pulsarlo». Los vídeos de tareas los enlazan en lugar de volver a explicarlo.

#### B1 · Lecciones, documentos y cursos: nada se copia · 2 min

**Sabrás** qué es una lección, un documento, un curso académico y una
asignatura, y cómo se relacionan.

**Parte de** la Biblioteca del ejemplo.

1. Una lección es una carpeta: sus metadatos y un fichero por idioma.
2. Un documento --el Tema 1, la Hoja 1, el Primer parcial-- es una lista
   ordenada de lecciones.
3. «Discontinuidades evitables» está en la Hoja 1 y en el Parcial: el panel
   **Se da en** lo enseña. Es una sola lección en dos sitios.
4. El curso académico guarda qué se da y en qué orden; la asignatura, lo que
   no cambia de un año a otro.

**La idea:** corriges una errata una vez y queda corregida en todos los
documentos que usan esa lección.

**Más:** [Cómo funciona](web/docs/conceptos/index.md) · [Microlecciones](web/docs/conceptos/unidades.md).

#### B2 · Una lección, quince PDF · 2,5 min

**Sabrás** qué sale en cada versión y por qué la copia del profesor nunca llega
al alumno.

**Parte de** el Tema 1 compilado en sus cinco versiones.

1. Diapositivas y diapositivas sin pausas: la misma diapositiva con `\pause`
   se proyecta por partes y se cuelga entera.
2. Apuntes: aparece el párrafo que era solo para los apuntes.
3. Copias del profesor: aparecen las notas didácticas.
4. Los cinco ejes --medio, clase, audiencia, soluciones y pausas--, en una
   tabla sobre la imagen.

**La idea:** el fichero no elige su formato; lo elige la versión con la que se
compila. Y en las versiones del alumno el canal del profesor no existe, que es
distinto de estar oculto.

**Más:** [Las quince salidas](web/docs/conceptos/perfiles.md).

#### B3 · Los niveles de un problema · 1,5 min

**Sabrás** qué enseña cada versión de una hoja y de un examen.

**Parte de** la Hoja 1 y el Primer parcial compilados.

1. «Límites de cocientes» abierto: enunciado, pista, resultado, solución y
   corrección.
2. La hoja en sus tres versiones, lado a lado: solo enunciados, con
   resultados, del profesor.
3. El examen y su corrección: sin pistas, y con espacio para contestar.

**La idea:** todo en un fichero, así que el enunciado y su solución no se
pueden desincronizar.

**Más:** [Los cuatro niveles de un problema](web/docs/conceptos/problemas.md).

#### B4 · Un fichero por idioma · 2 min

**Sabrás** cómo sabe Didacta qué está traducido, qué falta y qué se ha quedado
viejo.

**Parte de** «Definición de límite», con sus tres pestañas.

1. Castellano, Valencià, English: tres ficheros de la misma lección.
2. Los estados, dichos con su nombre y su color: original, al día, sin revisar,
   desactualizada (ámbar) y sin traducir (rojo).
3. Se cambia una frase del original, y la traducción pasa a desactualizada.

**La idea:** nadie escribe el estado; Didacta lo calcula. Y desactualizada es
peor que sin traducir: compila sin quejarse y dice algo que ya no es cierto.

**Más:** [Los idiomas](web/docs/conceptos/idiomas.md).

#### B5 · Todo vive en GitHub · 1,5 min

**Sabrás** dónde está tu material, quién lo ve y por qué no se pierde.

**Parte de** Ajustes → Cuenta y repositorios.

1. La copia en tu ordenador y el repositorio en GitHub; guardar es un cambio
   con tu nombre.
2. Varios repositorios, cada uno con su color: el del departamento y el tuyo,
   en una sola biblioteca.
3. Quién entra en cada uno lo dice GitHub.

**La idea:** la copia de seguridad es GitHub, siempre que envíes.

**Más:** [Repositorios de contenido](web/docs/conceptos/repositorios.md).

### C · Encontrar material

#### C1 · Recorrer la biblioteca · 2 min

**Sabrás** llegar a cualquier lección en tres clics y leer lo que dice cada
fila.

**Parte de** Biblioteca → Explorar.

1. Las columnas: categoría, tema, lecciones, con cuánto hay y cuánto está
   traducido.
2. Una fila: el título en el idioma que se mira; en cursiva y gris si no
   existe en ese idioma; el estado de cada idioma.
3. Ojear el PDF de una lección encima de la lista, sin entrar.
4. Abrir una lección y volver con **Atrás**: todo sigue como estaba. **Abiertas
   hace poco**, en la raíz.

**La idea:** la biblioteca respeta la organización que el material ya tiene en
lugar de enseñar una lista de miles.

**Más:** [La biblioteca](web/docs/app/biblioteca.md).

#### C2 · Buscar una lección · 2 min

**Sabrás** encontrarla aunque no recuerdes el título o lo escribas mal.

**Parte de** la Biblioteca.

1. «limite», sin tilde: la lista se aplana y encuentra «Límite».
2. Dos palabras estrechan; con una errata --«continudad»-- sale igual, contada
   aparte como parecida.
3. **En el texto**: «Bolzano» dentro de las lecciones, con la línea que lo
   dice. Al pulsar, se abre en ese idioma.
4. El atajo del buscador: ⌘F (Ctrl+F).

**La idea:** «¿dónde usé el teorema de Bolzano?» se contesta aunque la lección
se llame de otra forma.

**Más:** [La biblioteca](web/docs/app/biblioteca.md#dos-vistas-dos-preguntas).

#### C3 · Filtrar lo que falta, por tipo o por bloque · 1,5 min

**Sabrás** quedarte con lo que te interesa y saber cuánto queda.

**Parte de** la Biblioteca, mirando en valenciano.

1. «Falta en este idioma»: el árbol y sus números se recortan, y la cabecera
   dice cuántas quedan.
2. Por tipo, por bloque (Teoría, Problemas), por etiqueta y por repositorio.
3. **Orden**, y quitar los filtros.
4. **Completa:** *Guardar esta búsqueda*.

**La idea:** los filtros recortan también el árbol, no solo la búsqueda.

**Más:** [Los filtros](web/docs/app/biblioteca.md#los-filtros).

### D · Escribir una lección

#### D1 · La pantalla de una lección · 2 min

**Sabrás** qué hay en cada pestaña y en el panel de la derecha.

**Parte de** «Definición de límite».

1. Las pestañas: un idioma por pestaña, con su color y un punto si hay algo
   sin guardar; **Compilar**; los metadatos; el historial; un PDF por pestaña.
2. El panel: en qué documentos se usa, los prerrequisitos y los avisos.
3. La **ⓘ**: dónde se da, versiones congeladas, duplicar, mover, darla en otro
   tema.
4. La vista lado a lado.

**La idea:** el orden de las pestañas dice cuánto se usa cada una: compilar va
antes que los metadatos.

**Más:** [La unidad](web/docs/app/unidad.md).

#### D2 · Corregir una errata y guardarla · 2 min

**Sabrás** editar, guardar y enviar el cambio a GitHub.

**Parte de** «Límite por definición», en castellano.

1. Cambiar una palabra; aparece el punto en la pestaña.
2. **Guardar** (⌘S): se guarda con el mensaje que propone Didacta, y el aviso
   ofrece **Ver cambios**.
3. La barra de arriba cuenta un cambio sin enviar; **Enviar** (⌘⇧U).
4. **Descartar**, para lo que no se quiere guardar.

**La idea:** cada guardado queda en el historial con tu nombre. Guardar no
necesita conexión; enviar, sí.

**Ojo:** si la lección se da en más de un curso, una franja lo dice encima del
texto: el cambio llega a todos (J2). Quien prefiera ver el diff y escribir el
mensaje antes lo enciende en Ajustes → Guardar y sincronizar.

**Más:** [Guardar es un commit](web/docs/app/unidad.md#guardar-es-un-commit).

#### D3 · Escribir para diapositivas, apuntes o profesor · 2,5 min

**Sabrás** hacer que un trozo salga solo en las diapositivas, solo en los
apuntes o solo en tu copia.

**Parte de** «Función continua», en castellano.

1. Seleccionar un párrafo → **Apuntes**, en la barra de formato.
2. Una frase corta → **Diapositivas**.
3. Una nota → **Profesor**: «aquí se atascan».
4. Compilar las tres versiones lado a lado y señalar dónde sale cada trozo.

**La idea:** lo que no dice nada sale en todas partes; lo marcado, solo en su
canal.

**Más:** [Los tres canales](web/docs/escribir/index.md#los-tres-canales).

#### D4 · Definiciones, teoremas y snippets · 2 min

**Sabrás** poner un entorno de Didacta y quitarlo sin tocar lo de dentro.

**Parte de** una lección de teoría, en castellano.

1. Seleccionar el texto → el selector de snippets → «defi» → Intro.
2. Escribir `\begin{`: salen los entornos, y al elegir uno se escribe también
   su `\end`.
3. **Quitar** el snippet que rodea al cursor.
4. Compilar: la caja con su nombre y su número.

**La idea:** el nombre de la caja lo pone el idioma del documento:
«Definición», «Definició», «Definition».

**Más:** [El editor](web/docs/app/unidad.md#el-editor) · [Los teoremas](web/docs/escribir/index.md#los-teoremas).

#### D5 · Fórmulas y símbolos sin saberse las órdenes · 1,5 min

**Sabrás** escribir fórmulas con las paletas y evitar los caracteres que LaTeX
se reserva.

**Parte de** una lección de teoría.

1. **Símbolos** → buscar «≤»: escribe `\leq`, y en mitad de un párrafo lo mete
   entre `$…$` con el cursor dentro.
2. **Matemáticas**: una fracción, un sumatorio.
3. Un `%` suelto en el texto: el aviso.

**La idea:** un `\alpha` suelto en el texto no compila, y la paleta lo sabe.

#### D6 · Arreglar lo que no va a compilar, antes de compilar · 1,5 min

**Sabrás** leer el panel «Esto no va a compilar» y saltar a cada línea.

**Parte de** una lección de teoría.

1. Borrar una llave de cierre: sale el panel con la línea; al pulsar, el cursor
   va allí.
2. Una fórmula sin cerrar y un entorno sin su `\end`.
3. Una orden de otro idioma: `\lgem` en castellano.
4. Se puede guardar igual: un fichero a medias no se pierde.

**La idea:** solo avisa de lo que sabe seguro; si sale algo, es que no va a
compilar.

**Más:** [Lo que no va a compilar](web/docs/app/unidad.md#lo-que-no-va-a-compilar-antes-de-compilar).

#### D7 · Buscar y reemplazar en una lección · 1 min

**Sabrás** encontrar dentro del texto que editas y cambiarlo de una vez.

**Parte de** una lección larga.

1. ⌘F en el editor: todas las coincidencias pintadas, «2 de 4», Intro o ⌘G
   para la siguiente.
2. **Aa** para mirar mayúsculas; **.\*** para una expresión regular.
3. **Completa:** **Reemplazar** y **Todas**, que es un solo cambio y se deshace
   de una vez.

#### D8 · Escribir un problema · 2 min

**Sabrás** rellenar el enunciado, la pista, el resultado, la solución y la
corrección.

**Parte de** «Tres raíces por Bolzano».

1. El editor por campos, en lugar de un `.tex` con órdenes que recordar.
2. El resultado, en una línea: para que el alumno se corrija solo.
3. La corrección: cuánto vale cada parte. Nunca sale en un documento del
   alumno.
4. Compilar la Hoja 1 en sus tres versiones.

**La idea:** la solución vive con su enunciado, así que renumerar o mejorar el
enunciado no la deja resolviendo otra cosa.

**Más:** [Un problema se edita distinto](web/docs/app/unidad.md#un-problema-se-edita-distinto) · B3.

#### D9 · Poner una figura · 2 min

**Sabrás** dónde va una imagen, cómo se llama desde la lección y por qué lleva
texto alternativo.

**Parte de** «Teorema de Bolzano».

1. La imagen va en la carpeta `figures/` de la lección: se abre la carpeta del
   repositorio desde Ajustes → Cuenta y repositorios y se baja hasta ella.
2. En el editor, `\includegraphics[width=.6\textwidth,alt={…}]{figures/…}`.
3. Compilar.
4. **Revisar** avisa de las figuras que faltan.

**La idea:** la figura vive dentro de su lección, así que moverla o darla en
otra asignatura no la rompe. El texto alternativo es lo que oye quien no la ve.

**Ojo:** hoy no se puede añadir desde la aplicación (ver [§ 11](#11-lo-que-el-guion-destapa)).

**Más:** [Las figuras](web/docs/escribir/index.md#las-figuras).

#### D10 · Rellenar los metadatos de una lección · 2 min

**Sabrás** cambiar el título, la clasificación, los prerrequisitos y en qué se
compila una lección.

**Parte de** la pestaña de metadatos de «Teorema de Bolzano».

1. Un formulario, no YAML: el título en cada idioma.
2. La categoría, el tema y las etiquetas sugieren lo que ya existe; una errata
   avisa: «Categoría nueva: ninguna otra lección la usa».
3. Los prerrequisitos, buscados por título.
4. En qué se compila: lo normal es no elegir; aquí se aparta esta lección de
   las diapositivas.

**La idea:** cambiar un campo cambia solo esa línea del fichero; los
comentarios y los `TODO` que había siguen ahí.

**Más:** [`unit.yaml`](web/docs/app/unidad.md#unityaml).

#### D11 · Crear una lección nueva · 1,5 min

**Sabrás** crear una lección en el tema correcto.

**Parte de** Biblioteca → Cálculo → Continuidad.

1. **Nueva lección en…** Continuidad: el título, el tema y el tipo.
2. Antes de crearla, enseña dónde va a quedar; el tipo decide si va a
   `content/` o a `problems/`.
3. Se abre vacía, en el idioma de referencia.
4. La otra puerta: **Crear una nueva…** al añadir lecciones a un tema, que la
   deja ya puesta.

**La idea:** el nombre de la carpeta es la dirección con la que la llaman los
documentos.

**Más:** [Crear una lección](web/docs/app/biblioteca.md#crear-una-leccion).

#### D12 · Duplicar, mover o renombrar una lección · 2 min

**Sabrás** empezar una lección a partir de otra, y reorganizar sin romper nada.

**Parte de** la **ⓘ** de «Límites de cocientes».

1. **Duplicar…**: otro título, y desde ese momento son dos lecciones.
2. **Mover o renombrar…**: antes de confirmar dice cuántos documentos toca y
   de qué cursos, y los reescribe en el mismo cambio.
3. La diferencia con **Darla en otro tema…**, que es la misma lección en dos
   sitios (J2).

**La idea:** duplicar da dos lecciones; darla en otro tema da una lección en
dos sitios.

**Más:** [El icono de información](web/docs/app/unidad.md#el-icono-de-informacion).

### E · Preparar una asignatura

#### E1 · La pantalla de Asignaturas · 1,5 min

**Sabrás** moverte entre asignatura, curso y documento, y dejar a la vista solo
lo que das.

**Parte de** Asignaturas.

1. Los tres niveles.
2. La estrella, que no reordena; plegar; `⋯` → **Ocultar de esta lista**;
   arriba, las que doy, las ocultas o todas.
3. En la fila de cada documento, el PDF y ▶.

**La idea:** ocultar no borra: la asignatura sigue compilando y sigue en la
biblioteca.

**Más:** [Qué se ve, y qué no](web/docs/app/asignaturas.md#que-se-ve-y-que-no).

#### E2 · Crear una asignatura y su curso académico · 2 min

**Sabrás** dar de alta una asignatura nueva y su primer curso.

**Parte de** Asignaturas.

1. **Nueva asignatura**: el título, el identificador (sale solo), el idioma en
   que se da y, si se quiere, copiar los datos de otra.
2. Los datos de la asignatura: titulación, profesor, institución y los idiomas
   en que se ofrece, de entre los del repositorio.
3. **Nuevo curso académico**: «2026-2027», y empezar de cero.

**La idea:** la asignatura guarda lo que no cambia entre años; el curso, qué se
da este año y en qué orden.

**Ojo:** una asignatura no puede darse en un idioma que su repositorio no
mantiene: se añade antes en Ajustes (G7).

**Más:** [Asignaturas y cursos](web/docs/app/asignaturas.md).

#### E3 · Crear temas y documentos · 1,5 min

**Sabrás** organizar el curso en temas y crear dentro sus documentos.

**Parte de** Cálculo I → 2026-2027.

1. **Nuevo tema**: un bloque del curso con todo lo suyo dentro.
2. Un documento dentro del tema: el título; el identificador sale solo.
3. **Nuevo documento suelto**, para lo que no es de ningún tema.

**La idea:** el documento se crea vacío porque elegir sus lecciones es el paso
siguiente, y tiene su propia pantalla.

**Más:** [Los documentos](web/docs/app/asignaturas.md#los-documentos).

#### E4 · Componer un tema · 2,5 min

**Sabrás** añadir lecciones a un documento, ordenarlas y guardarlo.

**Parte de** el Tema 1, en su composición.

1. Cada línea apunta a una lección y dice su estado en el idioma que se
   compila.
2. **Añadir**: el buscador de la biblioteca sin salir de la pantalla.
3. Arrastrar para reordenar.
4. Guardar; el aviso ofrece **Compilar ahora**.
5. Una referencia rota se queda en su sitio, marcada, en lugar de desaparecer.

**La idea:** el documento no lleva materia: apunta a lecciones que viven una
sola vez.

**Más:** [La composición](web/docs/app/composicion.md).

#### E5 · Apartados, y lo que este año no se da · 1,5 min

**Sabrás** dividir un tema en apartados y dejar fuera una lección sin borrarla.

**Parte de** el Tema 1, en su composición.

1. Un apartado nuevo, con su título en cada idioma.
2. Quitar «Álgebra de límites»: se queda en gris, desactivada.
3. Volver a activar «Historia del épsilon», que el ejemplo trae desactivada, con
   un clic.

**La idea:** quitar desactiva, no borra; el año que viene se vuelve a activar
con un clic.

**Más:** [Editar](web/docs/app/composicion.md#editar).

#### E6 · Hacer un examen o una hoja a partir de los problemas · 2 min

**Sabrás** montar un examen de una vez, sin repetir problemas de otros años.

**Parte de** Cálculo I → 2026-2027.

1. **Examen u hoja de problemas**: el tipo, el título y el tema.
2. Elegir problemas con el buscador; los que ya salieron en un examen llevan
   la marca, y **Sin los que ya salieron** los quita.
3. Guardar: se abre listo para compilar el examen y su corrección.

**La idea:** un examen es una composición más: una lista de problemas que ya
existen.

**Más:** [Un examen o una hoja](web/docs/app/asignaturas.md#un-examen-o-una-hoja-a-partir-de-los-problemas).

#### E7 · Elegir qué PDF salen de un tema · 1,5 min

**Sabrás** decidir qué versiones se compilan de un tema.

**Parte de** el Tema 1, panel de la derecha.

1. De salida, lo que toca por las lecciones que lleva.
2. **Elegir salidas**: solo diapositivas y apuntes.
3. Volver a «lo que toque».

**La idea:** una lista vacía nunca quiere decir «ninguna»; quiere decir «lo que
toque».

**Más:** [Qué salidas tiene un tema](web/docs/app/asignaturas.md#que-salidas-tiene-un-tema).

#### E8 · Deshacer y borrar sin miedo · 1,5 min

**Sabrás** deshacer lo que acabas de hacer y saber qué se lleva un borrado
antes de hacerlo.

**Parte de** Cálculo I → 2026-2027.

1. Quitar un documento: el aviso trae **Deshacer**.
2. **Cambios recientes**, el reloj: deshacer lo de hace un rato, que se niega
   si alguien lo ha tocado después.
3. Quitar una asignatura dice lo que se lleva, contado, y lo que no: las
   lecciones no se tocan.

**La idea:** deshacer es un cambio más; lo deshecho sigue en el historial.

**Más:** [Deshacer](web/docs/app/asignaturas.md#deshacer).

### F · Compilar y revisar

#### F1 · Compilar una lección o un tema · 2 min

**Sabrás** elegir versiones e idiomas, y compilar todos los idiomas a la vez.

**Parte de** el Tema 1.

1. **Compilar** en una lección da su vista previa; en un documento, sus
   versiones.
2. Manteniéndolo pulsado: versiones e idiomas, o todos los idiomas.
3. Las versiones se compilan a la vez; cada línea de la consola dice de cuál
   es.
4. Compilar otra vez sin cambios es inmediato.

**La idea:** lo que no ha cambiado no se vuelve a compilar.

**Más:** [Compilar](web/docs/app/compilar.md).

#### F2 · Leer los PDF dentro de Didacta · 2,5 min

**Sabrás** comparar versiones, moverte por el documento y buscar dentro.

**Parte de** el Tema 1 compilado en castellano y valenciano.

1. Los dos idiomas lado a lado; pasar página mueve los dos.
2. Escribir el número de página; ajustar al ancho, al alto o entera.
3. El lateral: **Índice** y **Páginas**.
4. La lupa o ⌘F: sin tildes, «2 de 23 · es».
5. Abrir en el visor del sistema, para proyectar a pantalla completa.
6. Una pestaña en ámbar es un PDF de antes del último cambio.

**La idea:** comparar es mirar dos cosas a la vez, sin salir a otra aplicación.

**Más:** [El PDF, dentro](web/docs/app/compilar.md#el-pdf-dentro).

#### F3 · Del PDF a la línea que lo escribe · 1 min

**Sabrás** ir de lo que ves mal en el PDF a su línea en la lección.

**Parte de** las diapositivas del Tema 1.

1. ⌘+clic (Ctrl+clic) en una palabra de una diapositiva.
2. Se abre la lección en ese idioma, con el cursor en esa línea.
3. Corregir y volver a compilar.

**La idea:** lo que se ve mal se arregla donde se ve, sin buscarlo en el
fichero.

**Más:** [Del PDF a la lección](web/docs/app/compilar.md#del-pdf-a-la-leccion).

#### F4 · Cuando la compilación falla · 2 min

**Sabrás** ir directo al error, y ver las diapositivas que se salen.

**Parte de** una lección con una errata puesta a propósito (`\fracc`).

1. La tarjeta: la lección, el idioma, la línea y el error; **Abrir** lleva
   allí.
2. **Ver los N** y la consola entera.
3. «La diapositiva se sale por abajo»: **Abrir** lleva a donde empieza.
4. Un idioma que falta es un aviso, no un error.

**La idea:** el error se dice en la lección que hay que arreglar, no en el
documento que la incluye.

**Más:** [Cuando falla](web/docs/app/compilar.md#cuando-falla) · [Cuando algo falla](web/docs/ayuda/problemas.md).

#### F5 · Compilar un curso entero, o solo lo desactualizado · 2,5 min

**Sabrás** compilar mucho sin quedarte mirando, y rehacer solo lo que ha
cambiado.

**Parte de** Cálculo I → 2026-2027.

1. **Compilar el curso** pregunta antes, con cuántos documentos son.
2. La tira de abajo: por cuál va, **Ver**, **Detener**; lo que se pulsa
   mientras tanto espera su turno.
3. Al acabar: «N bien, M con errores», con los errores agrupados.
4. Corregir una errata: el tema dice «1 desactualizado» → **Compilar lo
   desactualizado**.
5. **Opcional:** avisar al terminar, para irse a otra ventana.

**La idea:** viejo es que haya cambiado lo que entró en el PDF, no su fecha:
traer cambios de GitHub no deja todo viejo.

**Más:** [Compilar lo desactualizado](web/docs/app/compilar.md#compilar-lo-desactualizado).

#### F6 · Vista rápida · 1 min · Opcional

**Sabrás** ver cómo queda un cambio en la mitad de tiempo.

**Parte de** Ajustes → Herramientas.

1. Encender **Vista rápida**.
2. En el tema, el botón dice **Vista rápida**; el PDF lo marca.
3. **Compilar entero** para lo que se reparte.

**La idea:** la mitad de tiempo, a cambio de que el índice y las referencias
puedan ser de la compilación anterior.

**Más:** [Vista rápida](web/docs/app/compilar.md#vista-rapida).

#### F7 · Revisar todo el material de una vez · 2 min

**Sabrás** encontrar lo que está mal antes de que salga en clase.

**Parte de** Biblioteca → **Revisar**.

1. Lo que mira siempre: órdenes de otro idioma, entornos que nadie define,
   figuras que faltan, referencias sin destino, diapositivas que se salen,
   traducciones desactualizadas.
2. Cada cosa con su lección, su línea y **Abrir**.
3. Las que se piden: fórmulas distintas entre idiomas, lecciones sin usar,
   coma y punto mezclados, ortografía.
4. Una palabra buena que el diccionario no conoce se apunta y deja de salir.

**La idea:** busca lo que compila --o casi-- y está mal, que es lo que no se ve
hasta que un alumno pregunta.

**Más:** [Revisar](web/docs/app/biblioteca.md#revisar).

#### F8 · Apuntes accesibles · 2,5 min · Opcional

**Sabrás** sacar los apuntes para quien lee con un lector de pantalla o
necesita el texto grande.

**Parte de** Ajustes → Herramientas.

1. **PDF accesibles**: los apuntes salen etiquetados (y tardan el doble).
2. El texto alternativo de una figura, `alt={…}`.
3. Exportar con **También: los apuntes en HTML**; abrirlo, agrandarlo y
   escucharlo.
4. La comprobación de lo que el PDF accesible no puede leer.

**La idea:** sale todo del mismo origen y con las mismas reglas: el HTML del
alumno no enseña una solución por ser HTML.

**Más:** [Apuntes accesibles](web/docs/app/compilar.md#apuntes-accesibles).

### G · Traducir

#### G1 · El idioma que miras, y con cuáles trabajas · 1,5 min

**Sabrás** cambiar el idioma en que se mira el material y quitarte de delante
los que no usas.

**Parte de** la Biblioteca.

1. El idioma de la barra de arriba manda en toda la aplicación: qué títulos y
   qué estados se enseñan.
2. Ajustes → Idiomas → **con los que trabajas**.
3. Un idioma apagado sigue saliendo donde algo ya lo usa.

**La idea:** elegir con qué idiomas trabajas es solo tuyo y no cambia ningún
fichero.

**Más:** [Idiomas](web/docs/app/ajustes.md#idiomas).

#### G2 · La cola de traducción · 1,5 min

**Sabrás** por dónde empezar a traducir.

**Parte de** Traducción.

1. Ordenada por cuántos documentos usan cada lección.
2. Las desactualizadas, primero.
3. Cada fila abre la lección ya en el idioma que falta.

**La idea:** traducir una lección que usan seis cursos compra seis documentos;
y cuando lo que queda no lo usa nadie, se puede parar.

**Más:** [Traducción](web/docs/app/traduccion.md).

#### G3 · Traducir con el original al lado · 2 min

**Sabrás** traducir una lección sin estropear el original.

**Parte de** «Teorema de Bolzano», pestaña Valencià.

1. La pestaña de un idioma que no existe arranca vacía, en rojo.
2. La vista lado a lado: el original con su candado, y los dos se desplazan a
   la vez.
3. Las fórmulas se copian tal cual; `\sen` funciona en todos los idiomas.
4. Guardar: queda sin revisar.

**La idea:** el original se ve y no se puede guardar por error.

**Más:** [Ver dos idiomas a la vez](web/docs/app/unidad.md#ver-dos-idiomas-a-la-vez).

#### G4 · Revisar y aprobar traducciones · 2,5 min

**Sabrás** revisar traducciones seguidas y ponerlas al día cuando cambia el
original.

**Parte de** una traducción sin revisar.

1. **Aprobar y siguiente**: guarda, la marca como revisada y abre la
   siguiente.
2. «Una fórmula no coincide con el original».
3. Una desactualizada: **El original ha cambiado desde que se revisó**, con la
   diferencia entre el original de entonces y el de ahora.
4. Lo que corriges lo aprende la memoria de traducción.

**La idea:** revisar treinta traducciones es leer treinta y pulsar treinta
veces.

**Más:** [Revisar una traducción](web/docs/app/unidad.md#revisar-una-traduccion).

#### G5 · Traducción automática · 3 min

**Sabrás** pedir un primer borrador sin que se rompa el LaTeX ni te lleves un
susto con la factura.

**Parte de** Ajustes → Traducción automática, con la clave ya puesta.

1. La clave de Google o Azure vive en el llavero y no se vuelve a enseñar;
   **Probar**.
2. Traducir varias lecciones: de salida, solo lo que no tiene texto y en el
   idioma que miras.
3. Antes de pulsar: cuántos caracteres y cuánto costaría.
4. La tanda: **Detener**; un solo cambio por repositorio; el título también.
5. Qué se protege: órdenes, entornos y fórmulas.

**La idea:** la máquina hace el borrador; lo que se firma hay que leerlo.

**Ojo:** **Rehacer también las que ya tienen texto** se lleva por delante lo
corregido a mano.

**Más:** [Traducción automática](web/docs/app/traduccion.md#traduccion-automatica).

#### G6 · El valenciano con Apertium, y el glosario · 2 min

**Sabrás** conseguir un valenciano que no suene a catalán central y que
respete tus términos.

**Parte de** Ajustes → Traducción automática.

1. Por qué Google y Azure dicen «aquest» y «durada».
2. **Traducir el valenciano con Apertium**: gratuito, sin clave.
3. El **Glosario**: «sucesión» es «successió»; «norma» no se traduce.
4. Un término que no ha salido como dice el glosario se avisa en el resumen.

**La idea:** el glosario avisa en lugar de sustituir, porque cambiar la palabra
sola deja frases que no concuerdan y que parecen revisadas.

**Más:** [El glosario](web/docs/app/traduccion.md#el-glosario).

#### G7 · Añadir o quitar un idioma · 2 min

**Sabrás** en qué orden se añade un idioma y por qué a veces no deja quitarlo.

**Parte de** Ajustes → Idiomas.

1. Las cuatro listas, en un esquema: lo que Didacta imprime, lo que traduce el
   repositorio, en lo que se da la asignatura y con lo que trabajas tú.
2. Añadir el inglés al repositorio, y después a la asignatura.
3. El candado: un idioma en el que se da una asignatura no se puede quitar.
4. Quitar no borra ningún fichero; volver a añadirlo los recupera.

**La idea:** cada lista vive dentro de la anterior.

**Más:** [Qué idiomas hay](web/docs/conceptos/idiomas.md#que-idiomas-hay).

### H · Repartir

#### H1 · Exportar un curso para el aula virtual · 2,5 min

**Sabrás** sacar los PDF de un curso a una carpeta sin repartir soluciones por
error.

**Parte de** Asignaturas, fila de 2026-2027.

1. **Exportar**: idiomas, temas y documentos, todo marcado.
2. Solo lo del estudiante; **Con las resoluciones completas**; **También las
   copias del profesor**, en rojo.
3. «Un documento tiene algún PDF desactualizado…» → **Compilar antes solo
   ese**.
4. La revisión de antes de repartir: **Exportar igualmente** o **Cancelar**.
5. La carpeta: una por idioma, una por tema, y nombres que se leen.

**La idea:** de salida no sale nada que no pueda ver un estudiante.

**Más:** [Exportar un curso](web/docs/app/exportar.md).

#### H2 · Exportar un documento o el PDF que miras · 1 min

**Sabrás** llevarte solo el Tema 3, o solo el PDF abierto.

**Parte de** Cálculo I → 2026-2027.

1. `⋯` del documento → exportar; si tiene copias del profesor, **Incluirlas**.
2. En el visor, **Guardar una copia**.

#### H3 · Un .zip para Moodle, y los apuntes en HTML · 1,5 min

**Sabrás** subir un curso entero al aula virtual en un solo fichero.

**Parte de** el diálogo de exportar.

1. **También: un .zip con todo**.
2. En Moodle, un recurso *Carpeta* que lo descomprime.
3. **También: los apuntes en HTML**, que entran en el mismo .zip.

**La idea:** se sube un fichero en lugar de cuarenta.

**Más:** [Un .zip para el aula virtual](web/docs/app/exportar.md#un-zip-para-el-aula-virtual).

#### H4 · Publicar en una carpeta de OneDrive o Drive · 1,5 min

**Sabrás** repartir sin elegir carpeta cada vez.

**Parte de** Ajustes → Guardar y sincronizar.

1. Elegir la **carpeta de reparto**.
2. `⋯` del curso → **Publicar en la carpeta de reparto**.
3. Cada curso va a la suya, y el programa de sincronización hace el resto.

**Ojo:** la carpeta de reparto sí puede estar en OneDrive; los repositorios, no.

**Más:** [Publicar en una carpeta que se sincroniza](web/docs/app/exportar.md#publicar-en-una-carpeta-que-se-sincroniza).

### I · No perder nada

#### I1 · Guardar, enviar y traer · 2,5 min

**Sabrás** dónde está tu trabajo en cada momento y cómo llevarlo a GitHub.

**Parte de** una lección con un cambio sin guardar.

1. Las palabras: cambio guardado, la copia en tu ordenador, enviar, traer.
2. La barra de arriba: lo que falta por enviar y lo que hay en GitHub; ⌘⇧U
   envía y ⌘⇧P trae.
3. Sin conexión se guarda igual; se envía al volver.
4. Ajustes → Guardar y sincronizar: los tres interruptores.

**La idea:** lo que no se envía solo está en tu ordenador; la copia de
seguridad es GitHub.

**Más:** [Guardar y sincronizar](web/docs/app/ajustes.md#guardar).

#### I2 · Ver cómo estaba un fichero, y recuperarlo · 2 min

**Sabrás** mirar cualquier versión anterior de una lección y traer de vuelta lo
que se quitó.

**Parte de** la pestaña de historial de «Definición de límite».

1. Las versiones a la izquierda; el fichero entero a la derecha, con lo
   añadido y lo quitado, y las palabras que cambiaron.
2. **Comparar con ahora**.
3. Copiar tres líneas de una versión antigua.
4. **Recuperar esta versión**: queda como cambio sin guardar; **Descartar** lo
   deja como estaba.

**La idea:** no hay un «revertir» que deshaga meses de trabajo de un clic.

**Más:** [El historial](web/docs/app/historial.md).

#### I3 · Congelar un curso · 1,5 min

**Sabrás** guardar cómo estaba un curso en un momento --«Antes del primer
parcial»--.

**Parte de** Asignaturas, `⋯` de 2026-2027.

1. **Crear versión congelada…**: un nombre y una descripción.
2. Lo que está sin guardar no entra, y el diálogo lo cuenta.
3. **Ver versiones congeladas…**.

**La idea:** es un cambio guardado con nombre: no ocupa, y quitarla no borra
nada. Tampoco es una copia de seguridad: eso es enviar.

**Más:** [Versiones congeladas](web/docs/app/congelaciones.md).

#### I4 · Mirar, comparar y restaurar una versión congelada · 3 min

**Sabrás** volver a ver un curso como estaba, compararlo con el de hoy y
recuperar lo que haga falta.

**Parte de** la lista de versiones congeladas.

1. **Abrir**: la banda de arriba avisa, y toda la aplicación enseña aquel día,
   de solo lectura.
2. Compilar ahí da el PDF que se repartió entonces.
3. **Comparar con la versión actual**: temas nuevos y quitados, lecciones
   cambiadas y movidas.
4. Restaurar una lección, un tema o el curso: primero dice qué cambiará.
5. **Volver a la versión actual**.

**La idea:** restaurar no reescribe la historia; deja un cambio pendiente
encima, que se revisa como cualquier otro.

**Más:** [Abrir, comparar y restaurar](web/docs/app/congelaciones.md#abrir-una).

#### I5 · Cuando sale un aviso al guardar o sincronizar · 2,5 min

**Sabrás** qué hacer con cada aviso, sin saber git.

**Parte de** el ejemplo, con un cambio hecho en github.com y la red cortada.

1. «Hay cambios nuevos en GitHub» → **Traer**.
2. «GitHub no acepta tu sesión» → **Volver a entrar**.
3. «No se llega a GitHub»: lo guardado está a salvo.
4. «Dos cambios chocan»: copiar lo tuyo y recargar.
5. **Detalles**, **Copiar** y **Contar el problema**.

**La idea:** el aviso dice qué ha pasado y qué hacer, y no se va solo.

**Más:** [Cuando algo falla](web/docs/ayuda/problemas.md#al-guardar-y-sincronizar).

#### I6 · Recuperar lo escrito tras un cierre inesperado · 1 min

**Sabrás** que lo escrito sin guardar no se pierde.

**Parte de** una lección con texto sin guardar.

1. Cambiar de pantalla: pregunta, con **Seguir editando** marcado.
2. Forzar el cierre de Didacta y volver a abrirla: **Recuperarlo** o
   **Descartarlo**.

**La idea:** lo escrito se va copiando fuera del repositorio mientras escribes.

### J · El curso que viene y el temario compartido

#### J1 · Preparar el curso que viene · 2,5 min

**Sabrás** empezar 2027-2028 a partir de 2026-2027 sin copiar material.

**Parte de** Asignaturas → Cálculo I.

1. **Duplicar** 2026-2027 en 2027-2028, con **Congelar 2026-2027 tal como
   quedó** marcado.
2. Se copian los temas y los documentos; las lecciones son las mismas.
3. Si hay documentos vinculados, el diálogo avisa de que se comparten.
4. La otra puerta: crear el curso desde una versión congelada.

**La idea:** lo que corrijas este año lo hereda el que viene, y el PDF del año
pasado sigue como se dio.

**Más:** [Duplicar un año](web/docs/app/asignaturas.md#duplicar-un-ano).

#### J2 · Una lección en varios cursos: cambiarla en todos o solo en uno · 2 min

**Sabrás** qué pasa al tocar una lección que se da en varios sitios, y cómo
separarla.

**Parte de** una lección que se da en dos cursos.

1. La franja: «Se da en 2 cursos: lo que guardes aquí cambia en todos».
2. **Separar una copia…**, para cambiarla solo en uno.
3. **Darla en otro tema…**: asignatura, curso y tema; vinculada de salida, o
   **Llevar una copia independiente**.

**La idea:** una lección compartida se corrige una vez; se separa solo cuando
dejan de ir juntas.

**Más:** [Dar una lección en otro tema](web/docs/app/vinculos.md#dar-una-leccion-en-otro-tema).

#### J3 · Dar un tema en otra asignatura sin copiarlo · 2,5 min

**Sabrás** vincular, duplicar o mover un tema, y saber en cuántos sitios está.

**Parte de** el `⋯` del Tema 1.

1. **Añadir vinculado a…** y **Duplicar en…**: el mismo diálogo, con las dos a
   la vista (con la interfaz *Completa*, también **Mover a…**).
2. Añadirlo vinculado a otra asignatura; el eslabón con el número.
3. Pulsar el eslabón: las ubicaciones, y cada una lleva a su sitio.
4. En la composición, la nota dice a cuántos cursos llega lo que cambies.

**La idea:** vincular no copia: es el mismo tema en varios sitios.

**Ojo:** solo dentro del mismo repositorio, porque las lecciones tienen que
estar al alcance del curso de destino.

**Más:** [Temario compartido](web/docs/app/vinculos.md).

#### J4 · Separar temas que iban juntos · 2,5 min · parte en Completa

**Sabrás** separar un tema vinculado cuando las asignaturas dejan de darlo
igual.

**Parte de** un tema vinculado en tres sitios.

1. **Crear copia independiente**: esta ubicación se queda con una copia.
2. **Completa:** **Gestionar vinculación…**: repartir las ubicaciones en
   grupos, con el resumen antes de confirmar.
3. **Duplicar también las lecciones del tema**, apagado, y por qué.

**La idea:** dentro de cada grupo siguen sincronizados; entre grupos, no. Y se
hace entera o no se hace.

**Más:** [Separar lo que estaba junto](web/docs/app/vinculos.md#separar-lo-que-estaba-junto).

### K · A tu manera

#### K1 · Claro u oscuro, tamaño del texto e idioma de Didacta · 1,5 min

**Sabrás** ajustar la aplicación al proyector, a la noche o a tu idioma.

**Parte de** Ajustes → Apariencia.

1. El sol y la luna; «como el sistema».
2. El tamaño del texto, del 85 % al 150 %, y ⌘+ / ⌘− / ⌘0.
3. **Idioma de Didacta**: castellano, valenciano o inglés.
4. **Interfaz**: Esencial o Completa (L1).

**La idea:** el idioma de Didacta no es el del material, y los PDF no cambian
con el modo oscuro: se compilan siempre en claro.

**Más:** [Apariencia](web/docs/app/ajustes.md#apariencia).

#### K2 · Ir más rápido: la paleta y los atajos · 2 min

**Sabrás** ir a cualquier sitio y hacer casi cualquier cosa escribiendo.

**Parte de** cualquier pantalla.

1. ⌘K: «bolzano», «cálculo 2026», «ajustes snippets».
2. Lo de la pantalla en la que estás sale arriba.
3. ⌘1, ⌘2, ⌘3, ⌘[ y ⌘], y ⌘/ para la lista entera.
4. Sin ratón: tabulador, Intro y Espacio.

**La idea:** cada orden de la paleta dice su atajo a la derecha, para
aprenderlo sin estudiarlo.

**Más:** [Los atajos](web/docs/app/index.md#los-atajos).

#### K3 · Trabajar con varios repositorios · 2 min

**Sabrás** tener abierto el material del departamento y el tuyo a la vez.

**Parte de** Ajustes → Cuenta y repositorios.

1. Añadir otro repositorio, desde GitHub o desde una carpeta.
2. Su color, en toda la aplicación; la biblioteca los junta.
3. Una lección nueva pregunta en cuál.
4. Quitar uno: de la lista, o también a la Papelera.
5. Las preferencias que viajan, para encontrarlas iguales en casa.

**La idea:** no hay un repositorio activo: se ven todos juntos y cada cambio va
al suyo.

**Más:** [Varios repositorios](web/docs/empezar/primer-repositorio.md#varios-repositorios-a-la-vez).

#### K4 · Pedir ayuda y tener Didacta al día · 1,5 min

**Sabrás** qué hacer cuando algo no va y cómo se actualiza Didacta.

**Parte de** Ajustes → Ayuda.

1. La presentación, el recorrido guiado, los atajos y la documentación.
2. **Copiar informe de diagnóstico** → **Abrir una incidencia**; va sin
   claves, pero lleva rutas: se mira antes de enviarlo.
3. Ajustes → Actualizaciones: la franja, mirar ahora, las versiones de prueba.
4. **Empezar de cero**, en rojo, y qué se lleva.

**La idea:** actualizar nunca te deja sin aplicación: la versión anterior se
aparta hasta que la nueva arranca.

**Más:** [Ayuda](web/docs/app/ajustes.md#ayuda) · [Actualizaciones](web/docs/app/ajustes.md#actualizaciones).

### L · Para quien mantiene el repositorio

Todo con la interfaz *Completa*. Es la ruta de quien organiza el material de un
departamento; un profesor que da sus clases no la necesita.

#### L1 · La interfaz Completa · 1,5 min · Completa

**Sabrás** qué aparece al encenderla y dónde.

**Parte de** Ajustes → Apariencia → Interfaz.

1. En el editor: la ruta, **ordenar al guardar**, reemplazar, más formato.
2. Copiar la referencia y el `unit.yaml` en bruto; las búsquedas guardadas.
3. **Mover a…** y **Gestionar vinculación…**; **Entre repos**, siempre.
4. En Ajustes: **Bloques y plantillas**, **Servidor MCP**, poner los ids.

**La idea:** un solo interruptor, porque lo que se elige es qué clase de uso se
hace, no cada botón.

**Más:** [Interfaz](web/docs/app/ajustes.md#interfaz).

#### L2 · Un repositorio para el departamento · 3 min · Completa

**Sabrás** repartir el material entre repositorios y comprobar que cuadra.

**Parte de** dos repositorios abiertos: el de ejemplo y otro de problemas.

1. El reparto típico, en un esquema: una colección común de problemas, los
   apuntes de cada uno y una asignatura compartida.
2. Quién entra en cada uno se decide en GitHub.
3. **Entre repos**: metadatos que discrepan, lecciones sin bloque, documentos
   que llaman fuera, snippets que no coinciden; **Quedarse con el de…**.

**La idea:** un documento y sus lecciones viven en el mismo repositorio; si no,
compila en tu máquina y no en la de quien solo tiene uno.

**Más:** [Entre repositorios](web/docs/app/entre-repos.md).

#### L3 · Bloques: teoría, problemas y prácticas · 2 min · Completa

**Sabrás** dividir una asignatura en partes y decidir con qué se compila cada
una.

**Parte de** Ajustes → Bloques y plantillas.

1. Añadir «Prácticas de ordenador», con su nombre en cada idioma.
2. En qué repositorios se declara.
3. Con qué plantillas se compila lo suyo.
4. Quitar uno: mover sus lecciones o dejarlas sin bloque.

**La idea:** renombrar un bloque es cambiar una línea: no se mueve ningún
fichero.

**Más:** [Bloques](web/docs/app/ajustes.md#bloques).

#### L4 · Plantillas: tus propias salidas · 3 min · Completa

**Sabrás** crear una salida propia --unos apuntes en A5-- o retocar una de las
quince.

**Parte de** Ajustes → Bloques y plantillas.

1. Duplicar **Apuntes** → «Apuntes de bolsillo», `10pt,a5paper`.
2. **Cabecera**: el LaTeX que se lee al final del preámbulo.
3. Dónde se guarda: en un repositorio, o en el programa (y **Copiar a una
   carpeta**).
4. Apagar no es borrar. Editar una de serie la escribe en tu repositorio.

**La idea:** la cabecera va al final del preámbulo de Didacta, así que puede
redefinir lo que Didacta acaba de definir.

**Más:** [Plantillas](web/docs/app/ajustes.md#plantillas) · [Las plantillas](web/docs/conceptos/perfiles.md#las-plantillas-tus-propias-salidas).

#### L5 · Snippets propios · 3 min · Completa

**Sabrás** crear una caja propia --«Resumen»-- y ofrecerla en la barra del
editor.

**Parte de** Ajustes → Snippets de LaTeX.

1. La lista: buscar, ordenar arrastrando, una casilla por repositorio.
2. **Nuevo snippet** como *Caja de teorema*: el título y el color.
3. La vista previa compila de verdad, en apuntes, en diapositivas y en la
   versión del profesor.
4. Retocar uno de Didacta, y **Volver al de Didacta**.

**La idea:** una definición va al preámbulo de todo el repositorio; por eso se
prueba antes de guardar.

**Más:** [Snippets de LaTeX](web/docs/app/ajustes.md#snippets).

#### L6 · Titulaciones · 1,5 min · Completa

**Sabrás** agrupar las asignaturas por grado.

**Parte de** Asignaturas.

1. Crear un grado y elegir dónde se declara.
2. La casilla por repositorio.
3. Ver solo las asignaturas de un grado; las «nombradas y sin declarar».

**Más:** [Las titulaciones](web/docs/app/asignaturas.md#las-titulaciones).

#### L7 · Compilar en GitHub y publicar la web del curso · 2,5 min · Completa

**Sabrás** hacer que GitHub compruebe y compile el material cada vez que envías.

**Parte de** Ajustes → Cuenta y repositorios, el icono de la nube.

1. El icono añade el fichero del workflow como un cambio más.
2. En la pestaña *Actions* de GitHub: la comprobación y los PDF en dos
   paquetes, para repartir y del profesor.
3. Los minutos de GitHub Actions.
4. La web del curso: `didacta site` y el workflow que trae el ejemplo.

**La idea:** los dos paquetes van separados con la misma regla que al exportar:
descargar el primero no puede traer una solución.

**Más:** [Compilar en GitHub](web/docs/app/ajustes.md#compilar-en-github) · [Una web del curso](web/docs/cli/index.md#una-web-del-curso).

#### L8 · Un asistente de IA sobre tu material · 3 min · Completa

**Sabrás** conectar Claude u otro cliente MCP a tu material, y ver lo que hace.

**Parte de** Ajustes → Servidor MCP.

1. Encenderlo: solo lee.
2. Dejarle escribir, repositorio a repositorio.
3. Copiar la configuración y pegarla en el cliente.
4. Preguntarle «¿qué lecciones del Tema 1 faltan en valenciano?» y mirar el
   registro en vivo.
5. Lo que escribe es un cambio guardado, en el historial.

**La idea:** dos interruptores: leer es inocuo; escribir se concede repositorio
a repositorio.

**Más:** [El servidor MCP](web/docs/app/mcp.md).

#### L9 · Didacta desde el terminal · 3 min · Completa

**Sabrás** hacer desde el terminal lo mismo que desde la ventana, y en lote.

**Parte de** un terminal en la carpeta del ejemplo.

1. `didacta status`, `didacta units --missing va`, `didacta translations`.
2. `didacta check`.
3. `didacta build tema-1 -p slides -l va`; `didacta build --all --list`.
4. `didacta export`, `didacta new unit`, `didacta new year`.
5. En la aplicación, copiar el comando para compilar un documento.

**La idea:** la aplicación y el terminal usan el mismo motor: lo que se hace en
uno se ve en el otro.

**Más:** [`didacta`, en el terminal](web/docs/cli/index.md).

### Lo que no lleva vídeo

A propósito. Un vídeo sirve para lo que se hace mirando; lo que se consulta se
lee.

- **La referencia de escritura** --todos los entornos, la bibliografía, los
  alias antiguos--: se busca una orden, no se mira un vídeo.
- **Resolver un conflicto de git.** Didacta no lo hace y lo dice; se hace en un
  terminal y está en [Cuando algo falla](web/docs/ayuda/problemas.md#dos-cambios-chocan).
- **Traer material de un sistema anterior** (`didacta migrate`): se hace una
  vez por departamento, y con acompañamiento.
- **La arquitectura, compilar la aplicación y publicar versiones**: son de
  quien desarrolla Didacta.

---

## 6. Índice por pregunta

La tabla que se publica en la web tal cual. Cada pregunta, con las palabras de
quien la hace.

### Al empezar

| Quiero… | Vídeo |
|---|---|
| saber qué es Didacta y qué me ahorra | A1 |
| instalarla | A2 |
| probar sin arriesgar mi material | A4 |
| que compile: no encuentra LaTeX | A5 |
| saber dónde está cada cosa | A6 · K2 |
| entender por qué una lección no pertenece a una asignatura | B1 |
| saber qué PDF salen de una lección | B2 |

### Preparando clase

| Quiero… | Vídeo |
|---|---|
| encontrar una lección que sé que escribí | C2 |
| saber dónde usé un teorema | C2 |
| corregir una errata | D2 |
| que un párrafo salga solo en los apuntes | D3 |
| una nota que solo vea yo | D3 |
| poner una definición o un teorema | D4 |
| escribir una fórmula sin saber la orden | D5 |
| poner una imagen | D9 |
| escribir un problema con su solución | D8 · B3 |
| crear una lección nueva | D11 |
| partir de una lección que ya tengo | D12 |
| cambiar una lección de carpeta sin romper nada | D12 |
| crear una asignatura | E2 |
| preparar el tema 3 | E3 · E4 |
| quitar una lección este año sin borrarla | E5 |
| hacer un examen sin repetir problemas | E6 |
| que un tema no salga en diapositivas | E7 |
| ver el tema en diapositivas y en apuntes a la vez | F1 · F2 |
| arreglar algo que he visto mal en el PDF | F3 |
| comprobar que no hay nada roto antes de clase | F7 |

### Traduciendo

| Quiero… | Vídeo |
|---|---|
| saber qué significa cada color | B4 · G1 |
| saber por dónde empiezo | G2 |
| traducir una lección | G3 |
| revisar lo que tradujo otro, o la máquina | G4 |
| saber por qué una traducción sale en ámbar | B4 · G4 |
| traducir automáticamente | G5 |
| un valenciano que no suene a catalán central | G6 |
| añadir el inglés a mi asignatura | G7 |

### Repartiendo

| Quiero… | Vídeo |
|---|---|
| subir los PDF al aula virtual | H1 · H3 |
| no repartir soluciones por error | H1 · B2 |
| llevarme solo un tema | H2 |
| dejar los PDF en OneDrive o Drive | H4 |
| apuntes para un estudiante con discapacidad visual | F8 |

### Cuando algo va mal

| Quiero… | Vídeo |
|---|---|
| saber por qué no compila | F4 · D6 |
| arreglar una diapositiva que se corta | F4 |
| entender un aviso al guardar o al enviar | I5 |
| recuperar lo que escribí antes de que se cerrara | I6 |
| deshacer algo que he borrado | E8 · I2 |
| contar un fallo | K4 |

### Día a día

| Quiero… | Vídeo |
|---|---|
| saber si mis cambios están en GitHub | I1 |
| trabajar en casa y en el despacho | I1 · K3 |
| ver cómo estaba una lección el año pasado | I2 · I4 |
| letra más grande para el proyector | K1 |
| modo oscuro | K1 |
| Didacta en valenciano o en inglés | K1 |
| tener el material del departamento y el mío | K3 · L2 |

### A final de curso

| Quiero… | Vídeo |
|---|---|
| guardar el curso tal como lo di | I3 |
| comparar el curso con el de hace meses | I4 |
| preparar el curso que viene | J1 |
| dar la misma lección en dos asignaturas | J2 · J3 |
| cambiar una lección solo en un curso | J2 |
| separar un tema que compartían dos asignaturas | J4 |

### Coordinando el departamento

| Quiero… | Vídeo |
|---|---|
| ver todas las opciones | L1 |
| organizar el material de varias personas | L2 |
| añadir «Prácticas» a la teoría y los problemas | L3 |
| unos apuntes con otro formato o con el membrete del departamento | L4 |
| una caja propia en la barra del editor | L5 |
| que GitHub compile solo | L7 |
| usar un asistente de IA con el material | L8 |
| usar el terminal | L9 |

---

## 7. Cómo se graba

**Actualizado con el A1: no se graba, se genera.** El estudio de
[`videos/`](videos/README.md) saca las pantallas de la propia aplicación
(con el repositorio de ejemplo), compila los PDF con el motor, pone la voz
con Qwen3-TTS en local y monta cada fotograma a partir del guion:
`python3 videos/hacer.py A01`. Rehacer un vídeo cuando cambia la interfaz es
volver a ejecutarlo. Lo de este apartado sigue valiendo como criterio --la
ventana fija, el modo claro, la interfaz Esencial, lo que nunca sale en
pantalla, la voz sin prisa-- y el estudio ya lo aplica solo; la grabación a
mano queda para lo que el arnés no puede enseñar (instalar la aplicación,
entrar en GitHub).

### El equipo y la ventana

- **Grabar en macOS**, y decir los dos atajos cuando salen: «⌘K --Ctrl+K en
  Windows y Linux--». La aplicación es la misma en los tres sistemas; lo único
  que cambia es la tecla. La excepción es A2, que tiene una versión por
  sistema.
- **La ventana a 1440×900 y el vídeo a 1080p.** Un tamaño fijo para todos los
  vídeos: un vídeo con la ventana a otro tamaño parece de otra aplicación.
- **Tamaño del texto de Didacta al 125 %** (Ajustes → Apariencia), para que se
  lea en un móvil. Y zoom suave en la edición sobre la parte que se toca.
- **Modo claro**, salvo en K1, que enseña los dos.
- **Interfaz Esencial**, salvo en la ruta L y donde la ficha dice *Completa*.
- **Idioma de Didacta: castellano.** Las otras dos lenguas llegan por los
  subtítulos (ver [§ 9](#9-por-fases)).
- **El cursor grande y los clics marcados**, y las teclas que se pulsan, en una
  esquina.

### El punto de partida

- **Una cuenta de GitHub para grabar**, que no sea la de nadie. Nada personal
  en las listas de repositorios, ni un correo real en la barra.
- **El repositorio de ejemplo recién creado**, y congelado como «Punto de
  partida» nada más crearlo: antes de cada grabación se restaura el curso
  desde ahí. Es usar la propia aplicación para lo que sirve.
- Cuando haga falta empezar de verdad de cero --A3, A4--: **Empezar de cero**
  en Ajustes y borrar `didacta-ejemplo` desde github.com, porque Didacta no
  pide permiso para borrar repositorios.
- **El estado de cada vídeo, escrito en su ficha** (**Parte de**). Si un vídeo
  necesita algo compilado antes, se compila antes de grabar.

### Lo que nunca sale en pantalla

- **El código de entrada a GitHub** (A3): se difumina, aunque caduque.
- **Una clave de traducción** (G5): se pega sin grabar y la pantalla solo
  enseña sus cuatro últimas letras, que también se difuminan.
- **El token del servidor MCP** (L8): va dentro de la configuración que se
  copia; se difumina en la aplicación y en el cliente.
- **Las notificaciones del sistema**: modo concentración mientras se graba.

### El guion y la voz

- **Guion escrito antes**, a partir de la ficha. Frases cortas, de tú, sin
  leer lo que se ve: la imagen dice qué se pulsa, la voz dice por qué.
- **Los botones, con su nombre exacto.** Si en pantalla pone **Compilar lo
  desactualizado**, se dice así.
- **Lo que está, se dice dónde**: «arriba a la derecha», «en la barra de
  abajo». Es para quien no ve la imagen, y ayuda a todos.
- **Sin prisa fingida.** Las esperas largas se cortan, pero no se esconde que
  compilar tarda: la tira de abajo sale al menos un momento. Didacta no
  promete lo que no hace, y sus vídeos tampoco.
- **Voz**: micrófono externo, una sala sin eco, sin música debajo de la voz.

### La forma de cada vídeo

```
0:00  El resultado, con el título y «al terminar sabrás…»        5 s como mucho
0:05  La tarea, hecha de verdad, en el ejemplo
…     La idea, en una frase, sobre la imagen final
      «Siguiente: …» y el código del vídeo                        10 s como mucho
```

Sin cabecera animada, sin «hola, bienvenidos», sin «no olvides suscribirte».
El logotipo, dos segundos al final, si acaso.

### Accesibilidad

- **Subtítulos** en castellano (revisados a mano, no solo automáticos),
  valenciano e inglés.
- **La transcripción, publicada al lado del vídeo** en la web. Sirve a quien
  no puede oír, a quien prefiere leer y al buscador de la web, que así
  encuentra vídeos por lo que se dice en ellos.
- **Nada solo con color**: «en ámbar, desactualizada»; «en rojo, sin
  traducir».
- **Capítulos** en los vídeos de más de dos minutos, con los pasos de la ficha.

---

## 8. Dónde viven

### En la web

- **Una sección nueva, «Vídeos»**, detrás de *Empezar*: la ruta del primer día
  arriba, el índice por pregunta, y las rutas.
- **En cada página de la documentación, un recuadro «En vídeo»** al principio,
  con los de esa página. La página de la biblioteca enlaza C1–C3; la de
  compilar, F1–F8.
- **La transcripción, subtítulos incluidos, en el repositorio**
  (`web/docs/videos/`): se versiona con la documentación y la encuentra el
  buscador.

La web no tiene analítica ni cookies, y los vídeos no pueden cambiar eso.
Si se alojan en YouTube, se incrustan con `youtube-nocookie.com` **y detrás de
una miniatura**: el reproductor de YouTube solo se carga cuando alguien pulsa.
El servicio de vídeo de la universidad, si lo hay, es la otra opción.

### Donde se publiquen

**Una lista por ruta**, en el mismo orden que aquí, y una más con la ruta del
primer día. La descripción de cada vídeo lleva el enlace a su página de la
documentación y la versión de Didacta con la que se grabó.

### Dentro de Didacta

Propuestas, que son trabajo en el código y van aparte de grabar:

- **Ajustes → Ayuda → Vídeos**, al lado del recorrido guiado.
- **La bienvenida ofrece A1** a quien llega.
- **La paleta de órdenes encuentra vídeos**: «examen» ofrece también «Ver el
  vídeo: Hacer un examen o una hoja». Es donde ya se busca todo lo demás.
- **Las pantallas vacías** --sin asignaturas, la biblioteca sin repositorio--
  enlazan el vídeo que las llena.

Para que la web y la aplicación no tengan dos listas, **un solo catálogo**
(`web/docs/videos/catalogo.yaml`): código, título, duración, nivel, enlace,
página de la documentación, pantallas que salen y versión con la que se grabó.

---

## 9. Por fases

Cada fase se publica entera: una ruta a medias no se puede seguir.

### Fase 1 · La primera semana

18 vídeos (20 ficheros, por las tres versiones de A2), unos **40 minutos**.
Con esto, alguien que no ha visto nunca Didacta prepara, compila y reparte un
tema.

A1 · A2 · A3 · A4 · A5 · A6 · A7 · B1 · B2 · C1 · C2 · D2 · D3 · E4 · F1 ·
F4 · H1 · I1

### Fase 2 · El trabajo diario

47 vídeos, unos **90 minutos**. El resto de lo que es para todos.

B3 · B4 · B5 · C3 · D1 · D4–D12 · E1 · E2 · E3 · E5 · E6 · E7 · E8 · F2 · F3 ·
F5 · F7 · G1–G7 · H2 · H3 · H4 · I2 · I3 · I4 · I5 · J1–J4 · K1–K4

### Fase 3 · Lo opcional y quien mantiene

12 vídeos, unos **30 minutos**: la ruta L entera, F6, F8 e I6.

Y en esta fase, **la ruta A grabada en valenciano y en inglés**, con Didacta en
ese idioma: es la que ve todo el mundo y donde más se nota ver la aplicación en
otra lengua que la de los subtítulos.

### Cuánto cuesta

Un vídeo de dos minutos terminado son unas **tres horas y media**: el guion, preparar el
estado, grabar, editar, subtitular en tres idiomas y revisar. La fase 1 son
unas setenta horas; el plan entero, unas doscientas ochenta. Es un orden de
magnitud, para decidir el ritmo, no un presupuesto.

---

## 10. Cómo saber si funcionan

### Antes de publicar una ruta

**Con tres a cinco profesores que no han usado Didacta.** Una tarea real --«la
Hoja 2 con estos tres problemas, en castellano y en valenciano»--, el vídeo, y
se les deja hacerla sin ayuda. Se apunta dónde se paran.

**Una ruta está lista cuando cuatro de cada cinco terminan la tarea solos.**
Si no, se mira dónde se paran: si es el vídeo, se rehace; si es la pantalla, va
al [§ 11](#11-lo-que-el-guion-destapa).

### Después

- **Hasta dónde se ve cada vídeo**, en las estadísticas del servicio donde se
  publiquen: un vídeo que se abandona a los veinte segundos no contesta lo que
  promete su título.
- **Las incidencias y las preguntas que llegan.** Una pregunta que se repite y
  tiene vídeo es un vídeo que no se encuentra; una que no lo tiene es un vídeo
  que falta.
- La web se queda sin analítica, como está.

### Cuando cambia la aplicación

**Con cada versión, se cruza el CHANGELOG con la columna de pantallas del
catálogo.**

- Si cambia **la tarea** --otro botón, otro camino--, el vídeo se vuelve a
  grabar. Por eso son cortos: rehacer uno es una tarde.
- Si cambia **un detalle** --un rótulo, un color--, basta una nota en la
  descripción hasta que toque grabarlo otra vez.
- En pantalla no se enseñan números de versión ni fechas, que caducan solos.

---

## 11. Lo que el guion destapa

Escribir un guion pulsación a pulsación es una prueba de usabilidad barata:
donde el vídeo necesita salir de la aplicación o dar un rodeo, es probable que
quien la usa se atasque igual. Tres casos:

1. **Poner una figura (D9).** No hay forma de añadir una imagen desde la
   lección: el vídeo tiene que abrir la carpeta del repositorio en Ajustes y
   bajar a mano hasta `figures/`. Un **Añadir figura…** en la barra del editor,
   que copiara el fichero a su sitio y escribiera el `\includegraphics` con su
   `alt={…}` vacío para rellenar, quitaría medio vídeo.
2. **La web del curso (L7).** Solo existe como `didacta site`, así que un vídeo
   para profesores tiene que abrir un terminal. Podría estar en el `⋯` del
   curso, al lado de exportar.
3. **Un tema a otro repositorio (J3).** El diálogo de destino ofrece las
   asignaturas de todos los repositorios abiertos, aunque un tema no puede
   salir del suyo --y la razón es buena: sus lecciones quedarían fuera de
   alcance--. Si solo ofreciera las del mismo repositorio, o marcara las demás
   con el porqué, el vídeo no tendría que advertirlo.

Cada uno es para [PLAN-DE-MEJORAS.md](PLAN-DE-MEJORAS.md), no para este plan.
