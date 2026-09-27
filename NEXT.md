# Siguiente fase

Esta carpeta contiene el sistema LaTeX, el modelo de contenido, el motor de
compilación, la herramienta, el migrador, los índices derivados y la aplicación
completa: las nueve rutas, el editor multilingüe, la edición de `unit.yaml` y el
constructor de composiciones, sobre clones locales de varios repositorios a la
vez, con la identidad de GitHub. Las 15 salidas funcionan; hay unos 800 tests de
Python y unos 2100 de Dart, y `./build.command todo` los pasa todos.

Lo hecho está al principio con lo que se aprendió haciéndolo, y lo que queda,
en «Pendiente», al final. La lista detallada de mejoras que faltan, con su
tamaño y su orden, está en [`PLAN-DE-MEJORAS.md`](PLAN-DE-MEJORAS.md).

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
| `manifest.json` | cuentas, idiomas, los 15 perfiles y lo que falló al leer |

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

`app/`. Flutter, siete rutas con URL propia, y **varios repositorios de
contenido a la vez**: se entra en GitHub, se eligen cuáles abrir y cada uno se
clona en su carpeta. La biblioteca y las asignaturas se ven juntas; cada
fichero sigue siendo de su repositorio.

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
- **ver el diff** de cualquiera de las dos cosas antes de hacer el commit;
- **crear una unidad** desde cero, con su `unit.yaml`, o a partir de otra;
- **compilar** una unidad, un documento o un curso, y ver el PDF al lado.

Tres reglas que impone siempre: todo cambio es un commit con autor y mensaje; una escritura es compare-and-set contra el `sha` con el que se leyó;
y un conflicto se cuenta y se ofrece recargar, nunca reintentar.

Lo que se aprendió construyéndola, y que está en las decisiones D39–D63:

- **editar un YAML reserializándolo borra el fichero.** Los `TODO` de la
  migración son la lista de trabajo de dos mil unidades, y las 905 entradas
  comentadas de los `year.yaml` son material que existe y que este año no se
  da. Las dos cosas sobreviven porque se reescribe *la línea*, no el fichero;
- **un commit local no necesita token.** Solo el envío. Exigirlo habría roto el
  camino sin conexión, que es la razón de que el clon exista;
- **el sandbox de macOS y un clon de git son incompatibles.** Una app en
  sandbox no puede ejecutar `git` ni volver a abrir una carpeta elegida en otra
  sesión.

## Hecho: compilar desde la interfaz

Se lanza `didacta build` o `didacta preview` desde la aplicación, en una cola
que se puede detener, y la consola enseña el log. Lo que importa de él sale
arriba: cada error con el fichero y la línea **de la unidad** --no la del
`.tex` de arranque que la incluye--, un enlace que abre el editor en esa línea
y, en diapositivas, qué transparencias se salen por abajo. Del PDF se vuelve a
la fuente con ⌘ o Ctrl y clic, por SyncTeX.

Qué PDF están desactualizados se sabe **sin compilar**: al compilar bien se
apunta junto al PDF la huella (sha256) de cada fichero que entró, y basta
compararlas. Cambiar una lección marca el tema que la incluye.

## Hecho: la bibliografía

`latex/didacta-bibliography.sty`. El material citaba con `\cite` y `\cites`
de biblatex, y sin biblatex esas unidades no compilaban. Ahora el `.bib` vive
en `shared/bibliography.bib` del repositorio de contenido (o donde diga
`didacta.yaml`), biblatex se carga solo si existe, y `didacta check` avisa
antes de compilar de las citas que no tienen dónde resolverse.

## Pendiente

### El CI del material

*Hecho.* `.github/workflows/material.yml` es un workflow reutilizable: comprueba,
pone el índice al día, compila y reparte en dos paquetes --lo que se reparte y
lo del profesor-- con `didacta export`. Cada repositorio de contenido lo llama
con dos líneas fijando la versión; el ejemplo lo trae y Ajustes lo añade a los
que ya existen (D81). Queda probarlo contra GitHub la primera vez que se
publique una versión con él: aquí solo se ha probado lo que no depende de
Actions.

### Lo demás

En [`PLAN-DE-MEJORAS.md`](PLAN-DE-MEJORAS.md): terminar de dividir `Session`
--que las pantallas lean de cada pieza y no de la fachada-- y firmar la
aplicación, que necesita los certificados de Apple y de Windows.
