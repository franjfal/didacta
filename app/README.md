# Didacta — la aplicación

Flutter, con rutas y edición. Lee el catálogo que genera el motor
(`didacta index`) y escribe en el repositorio de contenido como commits.

## Cómo está organizado, y por qué

```
lib/
├── model/      Dart puro, sin Flutter. Parseo, filtros, cuentas.
├── data/       De dónde vienen los datos y por dónde salen los cambios.
├── state/      Session: lo único que sabe el estado del mundo.
├── router.dart Las rutas.
├── ui/         Pantallas.
└── main.dart   Arranque.
```

El corte entre `model/` y `ui/` no es decorativo. El requisito era «Flutter Web
primero, escritorio después sin reescribir la lógica», y eso solo se cumple si
la parte que merece la pena reutilizar —y probar— no toca un widget. Los tests
de `test/` corren sin superficie de render.

### Las rutas

Cada pantalla tiene una URL, y eso es un requisito, no un adorno: esto es una
aplicación web, así que «mándame el enlace de esa unidad» tiene que funcionar,
el botón de atrás tiene que significar algo, y recargar tiene que dejarte donde
estabas.

| | |
|---|---|
| `/` | la biblioteca: 2147 unidades con filtros y búsqueda |
| `/unit/content/…` | una unidad: su editor multilingüe y su `unit.yaml` |
| `/courses` | las asignaturas y los cursos de cada una |
| `/courses/:curso/:año` | la composición de un curso |
| `/courses/:curso/:año/:doc` | un documento, su composición editable y sus salidas |
| `/translations` | qué falta traducir, por orden de cuánto se usa |
| `/settings` | acceso, sesión, token, diagnóstico |

### Los tres caminos al repositorio

`data/content_gateway.dart` es una interfaz con tres implementaciones, y
**ninguna pantalla sabe cuál está en uso**. Esa es la razón de que exista.

- **un clon local** (escritorio): el repositorio en disco, llevado por la propia
  aplicación —clonar, traer, commit y enviar— con el token que se pegó una vez.
  Nada que configurar a mano: ni `gh auth login`, ni credential helper, ni clave
  SSH. La biblioteca y el editor funcionan sin conexión, y el catálogo se lee del
  propio clon para que no pueda discrepar de los ficheros que el editor escribe.
- **directo a GitHub** (escritorio, sin clon): un token de permisos limitados en
  el llavero del sistema, contra la API de GitHub.
- **el Worker** (web): un navegador no puede guardar un secreto —lo que la página
  puede leer lo puede leer cualquiera con las herramientas de desarrollo—, así
  que aquí no hay token: la app demuestra quién es con un token de Firebase de
  vida corta y el Worker aplica `access.json`.

Se eligen en ese orden, y el orden no es arbitrario: cada paso está más lejos de
la máquina, y quien ha clonado el repositorio en este equipo ya ha dicho lo que
quiere.

Dos detalles del clon que no son evidentes:

- **un commit no necesita token; solo el envío.** Escribir en un clon que está en
  tu propio disco no necesita credencial, y exigirla rompería el camino sin
  conexión. El autor sale de la sesión o de la identidad de git de este equipo.
- **el token no pasa por `argv` ni por `.git/config`.** Va en el entorno del
  proceso hijo y lo lee de ahí un credential helper de una línea. Meterlo en la
  URL del remoto lo dejaría escrito dentro del clon, y `ps` enseña la línea de
  órdenes de todo el mundo.

Tres reglas que la interfaz impone en los dos caminos:

- **todo cambio es un commit**, con autor y mensaje. No hay un «guardar» que
  haga algo menos rastreable;
- **una escritura es compare-and-set**: se manda el `sha` con el que se leyó, y
  si el fichero se movió, falla y lo dice en lugar de sobrescribir a quien
  llegó antes;
- **un conflicto no se resuelve reintentando.** El editor ofrece recargar.

### Editar los metadatos y las composiciones sin borrar los comentarios

`model/yaml_patch.dart` y `model/composition_file.dart` editan un campo de un
YAML **sin tocar el resto del fichero**. No es purismo: un `unit.yaml` migrado
lleva el fichero del que salió y un `TODO` en cada campo que el material legado
no registraba, y eso es la lista de trabajo de dos mil unidades. Un round trip
por un parser la borra entera, en silencio, en la primera edición.

Lo mismo con las 905 entradas comentadas de los `year.yaml`: material que existe
y que este año no se da. Son un estado que una entrada puede tener, no basura, y
volver a activar algunas es la edición más común después de una migración.

Cuando no reconocen una forma, **rechazan en lugar de adivinar**, y la pantalla
lo dice y ofrece el editor de texto. Y antes de cada commit se ve el diff.

## Ejecutar

Necesita un catálogo generado. Desde el repositorio de contenido:

```bash
didacta index
```

En web:

```bash
flutter run -d chrome \
  --dart-define=DIDACTA_INDEX=/ruta/al/contenido/generated \
  --dart-define=DIDACTA_API=https://didacta-api.<sub>.workers.dev
```

En escritorio no hace falta decir nada: la aplicación busca el clon en el
disco al arrancar.

```bash
flutter run -d macos
```

Sin nada de eso la aplicación arranca igual y la biblioteca funciona: queda en
modo lectura hasta que se configure una API, se guarde un token o se elija un
clon en Ajustes. Eso es deliberado — una publicación estática del repositorio de
contenido es una configuración legítima.

## Compilar

```bash
flutter build web --release \
  --dart-define=DIDACTA_INDEX=generated \
  --dart-define=DIDACTA_API=https://didacta-api.<sub>.workers.dev
```

El resultado en `build/web/` es estático.

## Detalles que no son evidentes

Cosas que salieron de mirar los datos reales, no de suponer:

- **las categorías se ordenan por tamaño.** 51 en orden alfabético entierran las
  que se están dando;
- **un título que se muestra en otro idioma sale en cursiva y gris**, para que un
  título castellano en un listado valenciano no parezca traducido;
- **una referencia rota se muestra en su sitio, no se omite.** Una composición
  que se salta lo que falta parece completa y compila corta;
- **`outdated` va antes que `missing`** en traducción: una traducción cuyo
  original ha cambiado dice algo que ya no es cierto, y compila sin queja;
- **traducción se ordena por cuántos documentos usan cada unidad.** Con más
  huecos de los que nadie va a cerrar, una lista alfabética no es una cola de
  trabajo: es un reproche;
- **el editor de un idioma que no existe arranca vacío y marcado en rojo.**
  Arrancaba con el original debajo, para que quien traduce tuviera el texto
  delante; el efecto era el contrario del buscado, porque abrir la pestaña de
  valenciano y ver castellano se lee como «ya está traducida», y un guardado
  distraído archiva el castellano como si fuera la traducción. El texto
  delante lo da la vista lado a lado, donde el original se ve y no se puede
  guardar por error.

## Compilar en escritorio

```bash
app/tool/install-macos.sh
```

Compila, sustituye `~/Applications/Didacta.app` y la abre. Un script y no una
orden a mano por un fallo que ya ocurrió: la ruta del clon iba dentro del
binario por `--dart-define`, una compilación se hizo sin acordarse, y la
aplicación abrió diciendo «no se pudo cargar el catálogo» con el catálogo
generado y en su sitio. Una configuración invisible que se pierde en silencio
no es una configuración.

Ahora no hace falta ninguna: al arrancar, **la aplicación busca el clon** --una
carpeta con `didacta.yaml` y `.git`-- al lado del motor, hacia arriba desde
donde se ejecuta y en los sitios de siempre del `$HOME`. Lo que se elija en
Ajustes manda sobre eso, y si no encuentra nada la pantalla de fallo tiene un
botón para elegir la carpeta.

Los `--dart-define` siguen valiendo para forzarlo:

```bash
flutter build macos --release \
  --dart-define=DIDACTA_CLONE=$HOME/didacta_db \
  --dart-define=DIDACTA_ENGINE=$HOME/didacta
```

Sale en `build/macos/Build/Products/Release/Didacta.app`. `DIDACTA_ENGINE` es
el repositorio que tiene `cli/didacta`, que es lo que compila una unidad; si
no se pasa, la aplicación lo busca al lado del clon.

El sandbox de macOS queda **desactivado**, y el entitlement explica por qué: una
app en sandbox no puede ejecutar un binario fuera de su bundle ni volver a abrir
una carpeta elegida en otra sesión, así que no puede llevar un clon de git. El
coste es que este build no puede ir a la Mac App Store, que aquí no es un coste.

## El icono y el nombre

La marca la dibuja `lib/ui/brand.dart`, en Dart, con la geometría en
constantes con nombre. El **icono de la aplicación y el logo del carril son el
mismo código**: un icono dibujado aparte se separa de la interfaz en el primer
retoque, y acabas con dos marcas parecidas que no son la misma.

Lo que dibuja es lo que hace la plataforma: tres hojas desplazadas, y en la de
delante un titular y dos líneas. La misma unidad sale en diapositivas, en
apuntes y en libro del mismo `.tex`.

Para cambiarlo: se ajusta un número en `brand.dart` y se regenera.

```bash
flutter test tool/generate_icons.dart
```

Escribe los siete PNG que pide macOS y los cinco de la web. Por debajo de
40 px dibuja solo las siluetas, sin el titular ni las líneas: a ese tamaño
tres píxeles de verde sobre blanco se ven como suciedad y no como un
documento. Es arte por tamaño, que es lo que Apple pide y lo que
`Contents.json` permite dar.

### Por qué no persiste solo, y qué lo garantiza

Los PNG están versionados, así que compilar no depende de haberlos generado.
Lo que **sí** puede pisarlos es `flutter create` —que es lo que se ejecuta
para añadir una plataforma o reparar los ficheros de una—: restaura los iconos
por defecto de Flutter y el nombre `didacta_app`, sin avisar.

Para eso está `test/icons_test.dart`, que corre en CI y falla si:

- falta alguno de los doce ficheros, o no tiene el tamaño que dice su nombre;
- el color del icono no es el verde de la casa (o sea: es el azul de Flutter);
- el «maskable» de la web no llega al borde, o el de macOS no tiene margen
  —el primero lo recorta el sistema y un margen transparente se vería como un
  mordisco; el segundo necesita el hueco donde el sistema pone la sombra—;
- la aplicación ha vuelto a llamarse `didacta_app`, en macOS o en el
  manifiesto de la web.

El mensaje del test dice qué ejecutar para arreglarlo.

## Qué no hace todavía

- **compilar los PDF.** Necesita LaTeX y un navegador no lo tiene. La pantalla
  del documento dice qué se compilaría y da el comando; no finge poder hacerlo.
  En escritorio, con un clon en disco, sí podría — y es lo siguiente.
- **crear una unidad desde cero.** Se pueden editar, traducir, reclasificar y
  recomponer las que hay; para una nueva hace falta crear el directorio y el
  `unit.yaml` en el repositorio.
- **regenerar el índice.** Después de un commit el catálogo se recarga, pero el
  índice lo sigue generando `didacta index`. En escritorio podría lanzarse solo.
