---
title: Las quince salidas
description: Qué es un perfil, cuáles hay y sobre qué ejes se combinan.
---

# Las quince salidas

Un **perfil** es una salida: qué PDF se produce a partir de una composición.
Se eligen al compilar, y un documento declara cuáles son los suyos.

```bash
didacta profiles
```

| id | clase | medio | soluciones | audiencia | pausas |
|---|---|---|---|---|---|
| `slides` | beamer | diapositivas | — | alumno | sí |
| `slides-flat` | beamer | diapositivas | — | alumno | no |
| `slides-teacher` | beamer | diapositivas | todas | profesor | no |
| `notes` | article | documento | — | alumno | — |
| `notes-solutions` | article | documento | todas | alumno | — |
| `notes-teacher` | article | documento | todas | profesor | — |
| `book` | book | documento | — | alumno | — |
| `handout` | article | documento | — | alumno | — |
| `handout-answers` | article | documento | resultados | alumno | — |
| `handout-teacher` | article | documento | todas | profesor | — |
| `problems` | article | documento | — | alumno | — |
| `problems-answers` | article | documento | resultados | alumno | — |
| `problems-teacher` | article | documento | todas | profesor | — |
| `exam` | article | documento | — | alumno | — |
| `exam-marking` | article | documento | todas | profesor | — |

## No son quince plantillas

Son cinco ejes independientes, y cada perfil es un preajuste sobre ellos:

| Eje | Qué decide | Valores |
|---|---|---|
| **medio** | si el PDF son diapositivas o un documento | `slides` · `document` |
| **clase** | la clase de LaTeX | `beamer` · `article` · `book` |
| **audiencia** | si existe el canal del profesor | `student` · `teacher` |
| **soluciones** | cuánto de un problema se revela | nada · resultados · todas |
| **pausas** | si las apariciones progresivas se respetan | sí · no |

Eso importa por una razón muy concreta: **añadir una salida nueva es una
línea** en `latex/didacta-profiles.tex`, y nada más en el sistema necesita
enterarse. Ni el motor, ni la aplicación, ni las unidades.

??? abstract "Por qué `beamerarticle` es la línea que lo sostiene"

    El problema de fondo es que `\begin{frame}` es de beamer y no existe en
    `article`. Sin resolverlo, un fichero que sirva para las dos cosas tendría
    que estar lleno de condicionales, que es exactamente lo que se quería
    evitar.

    `beamerarticle` es el paquete de beamer que define su vocabulario --
    `frame`, `\pause`, los overlays-- dentro de una clase normal. Así el mismo
    `\begin{frame}` produce una diapositiva con `beamer` y un bloque de texto
    con `article`, sin que el contenido diga nada.

    Está contado entero en la [arquitectura](../proyecto/arquitectura.md).

## Las pausas

`slides` respeta `\pause` y las apariciones progresivas; `slides-flat` no.

Las dos hacen falta y no son la misma cosa: las de clase se proyectan y las
apariciones ayudan; las que se suben al aula virtual se imprimen, y una
diapositiva con cuatro apariciones se convierte allí en cuatro páginas casi
iguales.

## Las copias del profesor

Los perfiles `-teacher` abren un canal que en los demás **no existe**:

- lo que esté en un entorno `teaching` --ritmo, avisos, por dónde se atascan--;
- lo que esté en `\onlyteacher{...}`;
- todas las soluciones de todos los problemas;
- y en `exam-marking`, además, los criterios de corrección.

Que no exista, y no que esté oculto, es la diferencia importante: no hay
ninguna forma de que un descuido reparta la copia del profesor con el texto
dentro pero invisible.

## Qué perfiles tiene un documento

Se declaran en `year.yaml`:

```yaml
documents:
  - id: tema-1
    profiles: [slides, slides-flat, notes, notes-teacher]
```

Si no se dice nada, el motor usa los que correspondan al tipo del documento:
un `kind: problems` sale en los tres de problemas, un `kind: theory` en
diapositivas y apuntes.

En la aplicación, la pantalla del documento lista lo que se compilaría y
permite elegir. Desde el terminal:

```bash
didacta build tema-1                 # todos los suyos
didacta build tema-1 -p slides -l va # uno, en un idioma
didacta build --all --list           # qué haría, sin hacerlo
```
