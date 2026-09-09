# Siguiente fase

Esta carpeta contiene el sistema LaTeX, el modelo de contenido, el motor de
compilación, la herramienta, el migrador, los índices derivados y la aplicación
completa: las siete rutas, el editor multilingüe, la edición de `unit.yaml` y el
constructor de composiciones, con un clon local en escritorio y el Worker en
web. Las 14 salidas funcionan; 255 tests de Python y 213 de Dart.

Lo hecho está al principio con lo que se aprendió haciéndolo, y lo que queda
después, en orden de dependencia.

## Hecho: la migración

`engine/didacta/legacy.py` y `engine/didacta/migrate.py`, con
`didacta migrate <origen> <destino>`.

Medido sobre el repositorio actual:

| | |
|---|---|
| unidades | 2147 |
| ficheros de origen | 2438 |
| asignaturas | 17 |
| cursos académicos | 30 |
| documentos | 784 |
| referencias a unidades | 6137 |
| sin resolver | 4 |

Lo que hace, y por qué cada paso está donde está:

1. **agrupa los ficheros por unidad lógica.** Cuatro convenciones de idioma
   (`CAS`, `CAST`, `VAL`, `ENG`, más 606 ficheros sin token) colapsan en una
   unidad con `es.tex` / `va.tex` / `en.tex`;
2. **borra el preámbulo** de cada fichero, que es lo que `docmute` estaba ahí
   para descartar. Es el paso que más ruido elimina;
3. **renombra** entornos y macros donde el alias es peor que el nombre real
   (`ndefn` → `definition`, `shownto{solution}` → `solution`, `\onlybook` →
   `\onlynotes`, `\pause` → `\dpause`, `\frametitle` → `\didactatitle`);
4. **reescribe cada composición**: la lista ordenada de
   `\import{../../../../00classnotes/…}` de un master antiguo se convierte en
   el `structure:` de un `year.yaml`, y el `.tex` que queda son dos líneas de
   arranque. Los apartados pasan a la composición, donde pueden estar en los
   tres idiomas;
5. **genera un `unit.yaml`** con lo que la ruta permite deducir, y marca con
   `TODO` lo que no.

Tres cosas que la migración **no** hace, deliberadamente:

- **no modifica el origen.** Está comprobado con un test que compara el tamaño
  de cada fichero seguido por git antes y después. El material antiguo sigue
  compilando con sus propios Makefiles todo el tiempo que haga falta;
- **no escribe nada sin `--apply`.** Por defecto es un plan;
- **no inventa metadatos.** El título por idioma, las etiquetas más allá de la
  carpeta, los prerrequisitos, los objetivos y la duración no están en ninguna
  parte del material antiguo. `MIGRATION-REPORT.md` dice qué falta y en qué
  unidad, en lugar de rellenarlo con algo plausible.

Lo que sigue pendiente aquí es criterio, no código: leer el informe y decidir.

## Hecho: los índices derivados

`engine/didacta/index.py`, con `didacta index`. Tres ficheros JSON con lo que
una interfaz necesita para navegar y nada más:

| | |
|---|---|
| `units.json` | 2147 unidades · 2 MB · **77 KB comprimido** |
| `courses.json` | asignaturas, años y documentos en orden de composición |
| `manifest.json` | cuentas, idiomas, los 14 perfiles y lo que falló al leer |

Se generan en menos de un segundo sobre la biblioteca entera. Dos propiedades
que los hacen fiables:

- **derivados, nunca autoridad.** Borrarlos y regenerarlos da los mismos
  bytes. No hay ningún dato aquí que no esté ya en el repositorio, así que no
  hay un segundo sitio donde un hecho pueda quedarse obsoleto — la misma regla
  que hace que `missing` y `outdated` no se declaren nunca;
- **deterministas.** Sin marca de tiempo en ninguna parte. Hubo una en el
  manifest y rompía exactamente eso: `--check` decía que el índice estaba
  obsoleto justo después de escribirlo. `didacta index --check` es lo que CI
  ejecuta para que un índice desincronizado sea un fallo de build.

Lo que resuelve y el repositorio no: **en qué documentos se usa cada unidad**.
Es la respuesta a «¿puedo cambiar esto?», y contestarla exige recorrer todas las
composiciones — algo que un navegador no puede hacer.

## Hecho: la aplicación

`app/`. Flutter, siete rutas con URL propia, y tres formas de llegar al
repositorio detrás de una interfaz que no sabe cuál está en uso: un clon local
en escritorio, un token directo a GitHub, o el Worker en web.

Lo que se puede hacer desde ella:

- **navegar** las 2147 unidades con filtros por árbol, categoría, tipo,
  etiqueta y estado de traducción, búsqueda y cuatro órdenes, en una lista
  virtualizada;
- **editar y traducir** los `.tex`, con una pestaña por idioma; un idioma que
  no existe arranca con el original debajo, para no traducir contra una página
  en blanco;
- **editar `unit.yaml`** con formulario o como texto, sin borrar los
  comentarios ni los `TODO` del fichero;
- **recomponer un documento** arrastrando, activando y desactivando entradas,
  escribiendo el `structure:` del `year.yaml`;
- **ver el diff** de cualquiera de las dos cosas antes de hacer el commit.

Tres reglas que impone en los tres caminos: todo cambio es un commit con autor
y mensaje; una escritura es compare-and-set contra el `sha` con el que se leyó;
y un conflicto se cuenta y se ofrece recargar, nunca reintentar.

Lo que se aprendió construyéndola, y que está en las decisiones D39–D47:

- **editar un YAML reserializándolo borra el fichero.** Los `TODO` de la
  migración son la lista de trabajo de dos mil unidades, y las 905 entradas
  comentadas de los `year.yaml` son material que existe y que este año no se
  da. Las dos cosas sobreviven porque se reescribe *la línea*, no el fichero;
- **un commit local no necesita token.** Solo el envío. Exigirlo habría roto el
  camino sin conexión, que es la razón de que el clon exista;
- **el sandbox de macOS y un clon de git son incompatibles.** Una app en
  sandbox no puede ejecutar `git` ni volver a abrir una carpeta elegida en otra
  sesión.

Lo que falta:

- **compilar desde la interfaz.** En escritorio, con el clon en disco y LaTeX
  instalado, ya es posible: falta lanzar `didacta build`, mostrar el log con
  los errores localizados en el fichero y la línea correctos, y abrir el PDF.
  En web no lo es, y la pantalla del documento no lo finge: dice qué se
  compilaría y da el comando;
- **crear una unidad desde cero.** Hoy se editan las que hay;
- **regenerar el índice** desde la aplicación, en lugar de `didacta index`;
- **indicador de qué PDF están desactualizados**, calculado por hashes sin
  compilar.

## 1. Compilar desde la interfaz

En escritorio ya es posible y es lo que más cambia el día a día: el clon
está en disco y `didacta build` existe, así que falta lanzarlo, mostrar el
log con los errores en el fichero y la línea correctos, y abrir el PDF. Las
19 unidades que hoy no compilan de 2025-2026 se arreglarían leyéndolo.

## 2. Bibliografía

13 unidades del material citan con `\cite` y 5 de ellas con `\cites` de
biblatex. Didacta no tiene nada de eso: ni `\addbibresource`, ni estilo, ni un
sitio para el `.bib` en el modelo de contenido. Las que usan `\cites` no
compilan, y el informe de migración lo dice unidad por unidad.

Lo que hay que decidir: dónde vive la bibliografía (una por asignatura, una
compartida, o las dos), y si se usa biblatex — que es lo que el material ya
supone — o algo más simple.

## 3. Desplegar la API y Firebase

`api/` está **escrito y con tests**: un Worker que verifica la identidad
(Firebase Auth: alta, inicio de sesión, recuperar contraseña, verificación de
correo), aplica una política de acceso **versionada en el repositorio** —no en
la consola del proveedor, para que cada cambio de permisos sea un diff
revisable—, guarda el token de GitHub que un navegador no puede guardar, y
cachea los catálogos en el borde.

Roles y ámbito por carpeta, categoría, curso e idioma. La combinación que
importa es *traductor sin permiso de escritura*: puede crear y editar el
`va`/`en` de una unidad y no puede tocar el original.

Lo que queda no es código, son credenciales que solo tiene el autor:

```bash
cd api
wrangler login
wrangler secret put GITHUB_TOKEN     # un token fine-grained sobre didacta_db
wrangler deploy
```

Y en la consola de Firebase: activar correo/contraseña y Google, y añadir el
dominio de GitHub Pages a los dominios autorizados. Después, editar
`access.json` en `didacta_db` con quién puede qué.

Hasta entonces la web funciona en modo lectura, y en escritorio no hace falta:
el clon local no pasa por el Worker.

## 4. CI

Compilar en cada push, publicar los PDF como artefactos, regenerar los índices.
Los PDF no se versionan: se generan a partir del origen que está al lado.
