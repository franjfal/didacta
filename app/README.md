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
| `/unit/content/…` | una unidad, con su editor multilingüe |
| `/courses` | las asignaturas y los cursos de cada una |
| `/courses/:curso/:año` | la composición de un curso |
| `/courses/:curso/:año/:doc` | un documento, sus unidades en orden y sus salidas |
| `/translations` | qué falta traducir, por orden de cuánto se usa |
| `/settings` | acceso, sesión, token, diagnóstico |

### Los dos caminos al repositorio

`data/content_gateway.dart` es una interfaz con dos implementaciones, y **ninguna
pantalla sabe cuál está en uso**. Esa es la razón de que exista.

- **escritorio**: un token de permisos limitados en el llavero del sistema,
  directo a GitHub. El clon está en disco, así que se trabaja sin conexión.
- **web**: el Worker. Un navegador no puede guardar un secreto —lo que la página
  puede leer lo puede leer cualquiera con las herramientas de desarrollo—, así
  que aquí no hay token: la app demuestra quién es con un token de Firebase de
  vida corta y el Worker aplica `access.json`.

Tres reglas que la interfaz impone en los dos caminos:

- **todo cambio es un commit**, con autor y mensaje. No hay un «guardar» que
  haga algo menos rastreable;
- **una escritura es compare-and-set**: se manda el `sha` con el que se leyó, y
  si el fichero se movió, falla y lo dice en lugar de sobrescribir a quien
  llegó antes;
- **un conflicto no se resuelve reintentando.** El editor ofrece recargar.

## Ejecutar

Necesita un catálogo generado. Desde el repositorio de contenido:

```bash
didacta index
```

Y luego:

```bash
flutter run -d chrome \
  --dart-define=DIDACTA_INDEX=/ruta/al/contenido/generated \
  --dart-define=DIDACTA_API=https://didacta-api.<sub>.workers.dev
```

Sin `DIDACTA_API` la aplicación arranca igual y la biblioteca funciona: solo
queda en modo lectura hasta que se configure una API o se guarde un token en
Ajustes. Eso es deliberado — una publicación estática del repositorio de
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
- **el editor de un idioma que no existe arranca con el original debajo**, para
  que quien traduce tenga el texto delante en vez de una página en blanco.

## Qué no hace todavía

- **compilar.** Necesita LaTeX y un navegador no lo tiene. La pantalla del
  documento dice qué se compilaría y da el comando; no finge poder hacerlo.
- **editar `unit.yaml` y `year.yaml` desde la interfaz.** El editor escribe los
  `.tex`; los metadatos y las composiciones se editan en el repositorio. El
  constructor por arrastre es lo siguiente.
