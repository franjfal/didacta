# Plan de mejoras de Didacta

*Análisis del 25 de septiembre de 2026, sobre la versión 0.2.1 más lo que hay sin
publicar (modo oscuro, Ajustes por secciones, bienvenida nueva, recorrido
guiado y repositorio de ejemplo).*

Se revisó la aplicación entera en cinco frentes: el arranque, la navegación y
Ajustes; escribir y traducir; asignaturas, cursos y compilación; la arquitectura
y la robustez; y el motor, LaTeX, la documentación y la publicación. Los fallos
marcados con **✔** se han comprobado a mano en el código; el resto sale de la
lectura del código y conviene confirmarlo al ponerse con cada uno. Las líneas
citadas son las de hoy y se moverán.

**Leyenda.** Esfuerzo: **S** (horas), **M** (días), **L** (semanas).
Dónde vive: **Todos** (por defecto), **Opcional** (un interruptor en
Ajustes, apagado de salida), **Avanzado** (detrás del modo avanzado) e
**Invisible** (no cambia nada que se vea).

---

## 1. El criterio: no abrumar

Didacta tiene ya más funciones que las que un profesor usa en una semana normal,
y cada mejora de este plan añade algo. Si todo se enseña a la vez, la aplicación
se vuelve la herramienta de quien la construyó y deja de ser la de quien da
clase. Por eso cada propuesta lleva su capa, con cuatro reglas:

1. **Tres capas visibles y una invisible.**
   - **Lo esencial**: lo que necesita quien da clase para preparar, corregir,
     compilar y repartir. Es lo que se ve sin tocar nada.
   - **Opcional**: funciones que ayudan a algunos y estorban a otros.
     Interruptores con nombre de lo que hacen, repartidos en la sección de
     Ajustes a la que pertenecen, apagados de salida. **Diez como mucho** en
     toda la aplicación.
   - **Avanzado**: lo de quien mantiene el repositorio del departamento
     (plantillas, bloques, catálogo, servidor MCP, identificadores, rutas, el
     YAML en bruto, el terminal). **Un solo interruptor** lo enseña todo:
     Ajustes → Apariencia → *Interfaz: Esencial · Completa*.
   - **Invisible**: robustez, rendimiento y seguridad. No suman nada a la
     pantalla.
2. **Lo que protege no es opcional.** No perder trabajo, no repartir soluciones
   por error y no romper una asignatura que se da en otro curso son de todos,
   siempre.
3. **Lo opcional nunca hace falta para terminar una tarea básica**, y apagado
   no deja huecos: la pantalla se ve completa sin ello.
4. **Presupuesto por pantalla.** Una fila de lista, tres acciones a la vista
   como mucho (el resto, en su menú «…»). Una cabecera, una acción principal y
   un menú.

**La migración de quien ya usa Didacta.** Las instalaciones nuevas empiezan en
*Esencial*. Las que ya tienen repositorios abiertos empiezan en *Completa*, para
no esconderle a nadie lo que ya usa, y se les dice una vez que pueden
simplificarla.

---

## 5. Fase 3: por dentro (invisible)

En este orden, porque cada uno prepara el siguiente.

7. **Dividir `Session`.** *Hecho el 27 de septiembre de 2026.* Es una
   fachada de trece piezas --`LibraryPrefs`, `AuthState`, `WorkSettings`,
   `Repositories`, `RepoSync`, `CatalogueStore`, `CatalogueEditor`,
   `BuildService`, `TranslationService`, `EngineService`, `FreezeService`,
   `LanguageChoices` y `Startup`-- con los mismos nombres de antes, y de
   unas 5000 líneas ha pasado a 1850. Por la sesión solo avisa lo que
   cambia todas las pantallas; lo demás avisa por su pieza y lo escucha la
   pantalla que lo enseña (`test/session_pieces_test.dart`).

---

## 6. Fase 4: lo que estaba aparcado y ahora se hace

*Decidido el 27 de septiembre de 2026.* Lo que la §8 dejaba para más adelante
se hace, salvo lo que la §8 sigue diciendo que no. En este orden:

1. ~~**Terminar de dividir `Session`**~~ (§5, punto 7). *Hecho.*
2. ~~**Mover y renombrar lecciones para todos**~~, no solo en *Completa*:
   con el aviso de qué cursos se reescriben antes de confirmar. *Hecho.*
3. ~~**Tolerancia a erratas en la búsqueda**~~: una letra de más, de menos,
   cambiada o dos intercambiadas en las palabras de cinco letras o más que no
   estén tal cual en ningún sitio, y siempre por detrás de lo que coincide de
   verdad. *Hecho* (`model/fuzzy.dart`).
4. ~~**La paleta de órdenes (⌘K)**~~: ir a una lección, un curso o una
   pantalla y lanzar las acciones de la pantalla en la que se está,
   escribiendo. *Hecho* (`ui/command_palette.dart`, `model/palette.dart`).
5. ~~**El CI del material**~~: compilar en cada push en el repositorio de
   contenido, publicar los PDF como artefactos y regenerar los índices. El
   repositorio de ejemplo lo trae, y Ajustes lo ofrece a los que ya existen.
   *Hecho* (D81); falta verlo correr en GitHub con una versión publicada.
6. ~~**Apuntes accesibles**~~: los metadatos del PDF (título, autor, idioma),
   el texto alternativo de las figuras y, para lo que no es beamer, el PDF
   etiquetado con LuaLaTeX y un HTML de los apuntes. *Hecho* (D82). Lo que
   queda es de LaTeX, no de Didacta: el etiquetado todavía no admite las
   opciones de las listas, y esos documentos salen sin etiquetar.
7. ~~**Una GitHub App en lugar del token de `repo`**~~: permisos por
   repositorio y tokens que caducan y se renuevan solos. Las cuentas que ya
   entraron con el token siguen funcionando. *Hecho* (D83): la App es «Didacta App»
   (`github.com/apps/didacta-app`), registrada el 28 de septiembre de 2026.
8. ~~**La interfaz en castellano, valenciano e inglés**~~, *Idioma de
   Didacta* en Apariencia, siguiendo al del sistema. *Hecho* (D84): cada texto
   pasa por `tr()`, y `tests/test_l10n.py` no deja que uno nuevo se quede sin
   decidir.

---

## 7. Lo opcional, en un solo sitio

Diez interruptores como mucho, cada uno en la sección de Ajustes a la que
pertenece. Todos apagados de salida. Lo que tenía pendiente esta sección --el
aviso al terminar de compilar, el tamaño del texto y llevar a la interfaz
*Completa* lo de quien mantiene el repositorio-- está hecho. El Client ID de
GitHub no pasa a *Completa*: se pide en la pantalla de entrar, antes de poder
elegir interfaz, y ya va detrás de un enlace.

**Lo que no es un interruptor porque no debe serlo:** los avisos de soluciones
al exportar, de lecciones compartidas y de trabajo sin guardar; los errores
comprensibles; la accesibilidad.

**El idioma de la propia interfaz** (castellano, valenciano, inglés) va en
Apariencia como *Idioma de Didacta*, siguiendo al del sistema (§6, punto 8).

---

## 8. Lo que no se hace

- **Firmar la aplicación** (macOS, Windows y el manifiesto de
  actualizaciones). *Decidido el 27 de septiembre de 2026.*
- **Subir a Moodle por sus servicios web.** No solo porque cada universidad
  tiene el suyo: repartir tiene que valer para cualquier plataforma, no
  centrarse en una. El `.zip` y la carpeta de reparto son eso. *Decidido el
  27 de septiembre de 2026.*

---

## 9. Orden recomendado

| Tramo | Qué | Tiempo aproximado |
|---|---|---|
| 1 | **Fase 0** entera: seguridad, trabajo que se pierde, soluciones al exportar, traducción que miente, menús | 2 semanas |
| 2 | **Fase 3**, puntos 1–5 (rendimiento invisible) y **Fase 1**, puntos 1, 2, 6 y 7 (no perder trabajo, errores, accesibilidad) | 2–3 semanas |
| 3 | El interruptor **Esencial · Completa** y el reparto de lo avanzado; **Fase 1**, puntos 3–5 (lenguaje, estados vacíos, atajos) | 2 semanas |
| 4 | **Compilar** (§4.3): detener, cola, errores a la línea, incremental, paralelo, desactualizados por hash | 3 semanas |
| 5 | **Escribir y traducir** (§4.1, §4.4): crear unidad, avisos previos, revisión lado a lado, fórmulas entre idiomas | 3 semanas |
| 6 | **Cursos y repartir** (§4.5): asistente de examen, exportar a zip, deshacer, historial | 2–3 semanas |
| 7 | **Fase 4**: motor con la aplicación, `didacta check` en la app, firma | 2–3 semanas |
| 8 | **Dividir `Session`** y el resto de la Fase 3 | continuo |

Con cada tramo:
- tests de regresión de lo que se arregla;
- el modo oscuro revisado con `DIDACTA_SHOTS_DARK=1`;
- las capturas de la web regeneradas;
- su entrada en el CHANGELOG.
