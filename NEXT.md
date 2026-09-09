# Siguiente fase

Esta carpeta contiene el sistema LaTeX, el modelo de contenido, el motor de
compilación, la herramienta, el migrador, los índices derivados y la biblioteca
de la aplicación. Las 14 salidas funcionan; 253 tests de Python y 33 de Dart.

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

## 1. Bibliografía

13 unidades del material citan con `\cite` y 5 de ellas con `\cites` de
biblatex. Didacta no tiene nada de eso: ni `\addbibresource`, ni estilo, ni un
sitio para el `.bib` en el modelo de contenido. Las que usan `\cites` no
compilan, y el informe de migración lo dice unidad por unidad.

Lo que hay que decidir: dónde vive la bibliografía (una por asignatura, una
compartida, o las dos), y si se usa biblatex — que es lo que el material ya
supone — o algo más simple.

## 2. La API

`api/`. Un Worker que:

- verifica la identidad (Firebase Auth: alta, inicio de sesión, recuperar
  contraseña, verificación de correo);
- aplica una política de acceso **versionada en el repositorio**, no en la
  consola del proveedor, para que cada cambio de permisos sea un diff
  revisable;
- guarda el token de GitHub, que un navegador no puede guardar;
- cachea los catálogos en el borde.

Roles y ámbito por carpeta, categoría, curso e idioma. La combinación que
importa es *traductor sin permiso de escritura*: puede crear y editar el
`va`/`en` de una unidad y no puede tocar el original.

## 3. La aplicación

`app/`. Flutter Web, y **la biblioteca ya funciona**: carga el índice y muestra
las 2147 unidades con filtros por árbol, categoría, tipo, etiqueta y estado de
traducción, búsqueda por palabras y cuatro órdenes. La lista está virtualizada,
así que 2147 filas cuestan lo que 20.

El corte entre `lib/model/` (Dart puro, 33 tests, sin un solo widget) y
`lib/ui/` es lo que hace que «escritorio después sin reescribir la lógica» sea
cierto: la parte con reglas — parseo, filtros, cuentas — no toca la superficie
de render. `lib/data/` es una interfaz por lo mismo: en web el índice se pide
por HTTP, en escritorio se leerá del disco.

Lo que falta:

- editor multilingüe con pestañas y vista dividida;
- constructor de composiciones por arrastre, que escribe el `structure:` del
  `year.yaml`;
- compilación por perfil e idioma, con los errores de LaTeX localizados en el
  fichero y la línea correctos;
- indicador de qué PDF están desactualizados, calculado por hashes sin
  compilar.

Los tres últimos necesitan `api/`: escribir en el repositorio y compilar exigen
identidad y un token que un navegador no puede guardar.

## 4. CI

Compilar en cada push, publicar los PDF como artefactos, regenerar los índices.
Los PDF no se versionan: se generan a partir del origen que está al lado.
