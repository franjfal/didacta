# Didacta — la aplicación

Flutter Web. Lee el catálogo que genera el motor (`didacta index`) y no habla
con el repositorio de contenido directamente: son tres ficheros JSON estáticos,
así que esto se puede servir desde GitHub Pages sin ningún servidor detrás.

## Cómo está organizado, y por qué

```
lib/
├── model/      Dart puro, sin Flutter. Parseo, filtros, cuentas.
├── data/       De dónde viene el catálogo. Una interfaz, varias fuentes.
├── ui/         Widgets.
└── main.dart   Carga y arranque.
```

El corte entre `model/` y `ui/` no es decorativo. El requisito era «Flutter Web
primero, escritorio después sin reescribir la lógica», y eso solo se cumple si
la parte que merece la pena reutilizar —y probar— no toca un widget. Los 33
tests de `test/` corren sin superficie de render.

`data/` es una interfaz por el mismo motivo: en web el índice se pide por HTTP,
en escritorio se leerá del disco, y en un test se pasa a mano. Nada por encima
de esa capa sabe cuál es.

## Ejecutar

Necesita un catálogo generado. Desde un repositorio de contenido:

```bash
didacta index
```

Y luego, apuntando la aplicación a ese directorio:

```bash
flutter run -d chrome --dart-define=DIDACTA_INDEX=/ruta/al/contenido/generated
```

Sin `--dart-define` busca en `generated/` junto a la propia aplicación, que es
lo que hace que una build copiada al lado de un repositorio funcione sin
configurar nada.

## Compilar

```bash
flutter build web --release --dart-define=DIDACTA_INDEX=generated
```

El resultado en `build/web/` es estático.

## Qué hace hoy

La biblioteca: las unidades con filtros por árbol (teoría / problemas),
categoría, tipo, etiqueta y estado de traducción, búsqueda por palabras, cuatro
órdenes, y el panel de detalle de cada unidad.

Dos cosas de ese panel que no son evidentes y son la razón de que el índice
exista:

- **en qué documentos se usa cada unidad.** Es la respuesta a «¿puedo cambiar
  esto?», y contestarla desde el navegador exigiría leer todas las
  composiciones del repositorio;
- **qué unidades no usa nadie.** Después de una migración es material que llegó
  y no se está dando: o falta ponerlo en una asignatura, o se puede quitar.

El estado de traducción viene calculado (`missing` y `outdated` no se declaran
nunca), así que la aplicación lo pinta pero no lo deduce.

## Qué no hace todavía

- editar. El editor multilingüe es una fase posterior, y un panel que parece
  editable sin serlo es peor que uno que lee y lo dice;
- componer. El constructor de composiciones escribe el `structure:` de un
  `year.yaml`, y eso necesita escritura autenticada;
- compilar. Requiere la capa `api/`, que todavía no existe.
