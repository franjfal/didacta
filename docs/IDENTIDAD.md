# Identidad, vínculos y congelaciones

Cómo Didacta distingue **qué es** un contenido de **dónde aparece**, y cómo
guarda el estado de un curso en un momento concreto.

Este documento es la referencia de dos cosas que se construyeron juntas
porque se necesitan mutuamente: el contenido vinculado (un mismo material en
varios cursos, sincronizado de verdad) y las versiones congeladas (ese
material tal como estaba un día). La segunda no tiene sentido sin la primera:
una congelación que no supiera qué estaba vinculado con qué enseñaría una
foto incompleta.

---

## 1. Lo que ya era cierto antes de esto

Conviene empezar por aquí, porque la mitad del trabajo ya estaba hecho y
rehacerlo habría sido el error.

Didacta nunca ha guardado contenido dentro de un curso. Un `year.yaml` es
**selección y orden**, y cada entrada es una referencia:

```yaml
documents:
  - id: tema-1-numeros-reales
    kind: theory
    themes: [tema-1]
    structure:
      - section: {es: "¿Qué es la matemática?"}
      - unit: analisis-real-una-variable/que-son-las-mates/que-son-las-matematicas
```

Esa línea `- unit:` **no es una copia**. La lección vive una sola vez en
`content/`, y los treinta cursos que la llaman llaman a la misma. Corregir
una errata es corregirla una vez. Eso ya funcionaba, y el índice ya lo
registraba: cada unidad publica su `usedBy`, que es exactamente la lista de
ubicaciones donde aparece.

Así que **una lección ya era contenido vinculado**. Lo que faltaba era tres
cosas:

1. poder **decirlo** desde la interfaz —vincularla a otro curso, ver dónde
   está, separarla— en lugar de tener que editar el `year.yaml`;
2. que un **documento entero** —un tema, con su orden, sus apartados y sus
   lecciones— pudiera compartirse igual, porque copiarlo sí duplicaba;
3. que la identidad no dependiera de la **ruta**, que es lo que se rompe el
   día que alguien reorganiza `content/`.

---

## 2. El vocabulario, fijado

Didacta tiene palabras propias y conviene no mezclarlas con las de otros
sistemas.

| En la interfaz | En el repositorio | Qué es |
|---|---|---|
| Asignatura | `courses/<id>/course.yaml` | La materia, a lo largo de los años |
| Curso académico | `courses/<id>/<año>/` | Un año de esa asignatura |
| Documento (tema, práctica…) | una entrada de `documents:` + su `.tex` | Lo que se compila a PDF: título, orden y apartados |
| Bloque de temas | `themes.yaml` | La tarjeta bajo la que se agrupan documentos |
| Lección (unidad) | `content/<área>/<...>/` | El material: un `.tex` por idioma, sus figuras y su `unit.yaml` |

Cuando este documento dice **«tema»** sin más se refiere al **documento**: es
lo que tiene hijos, orden interno, apartados y subapartados, y es lo que se
comparte entre cursos. El `themes.yaml` es otra cosa —una etiqueta de
agrupación— y viaja detrás del documento que la nombra, como ya hacía.

---

## 3. Dos identidades, y por qué tienen que ser dos

El error que este modelo evita es tener N copias y propagar cambios entre
ellas. Eso siempre acaba divergiendo. En su lugar hay **una entidad y varias
ubicaciones**.

### 3.1 Identidad de contenido

Un identificador estable que dice **qué** es algo. No cambia si el fichero se
mueve, se renombra o se reordena.

* Una **lección** lo declara en su `unit.yaml`:

  ```yaml
  id: u-6f3a2c91d4e7
  ```

  El campo ya existía y el motor ya lo leía; lo que faltaba era que estuviera
  puesto en todas y que fuera el que manda.

* Un **documento compartido** lo declara en su propio fichero, en la raíz del
  repositorio:

  ```
  shared/documents/d-8a41f0c27b53.yaml
  ```

Los ids son opacos a propósito. Un id legible es un id que alguien acaba
editando para que «se entienda mejor», y ese día dos entidades distintas
comparten identidad.

### 3.2 Identidad de ubicación

Dónde aparece ese contenido. Una ubicación es siempre **una línea de un
fichero de curso**, que es donde ya estaba:

* la ubicación de una **lección** es una entrada de `structure:` dentro de un
  documento: `(asignatura, año, documento, posición)`;
* la ubicación de un **documento** es una entrada de `documents:` dentro de
  un `year.yaml`: `(asignatura, año, id local)`.

### 3.3 El grupo de sincronización no se guarda

Es **derivado**: el grupo de un contenido es el conjunto de ubicaciones que
nombran su id. No hay una tabla de vínculos en ningún sitio, y eso es una
decisión, no un descuido: una tabla aparte sería una segunda fuente de verdad
que puede contradecir a los ficheros, y reconciliar las dos después de un
`git merge` es exactamente el problema que este modelo existe para no tener.

Consecuencia directa: **un `clone` limpio reconstruye todos los vínculos**
sin más que leer los ficheros, porque los vínculos *son* los ficheros.

---

## 4. Documentos compartidos

Un documento no compartido sigue exactamente como estaba —ni una línea
cambia, y los repositorios existentes no se tocan hasta que alguien vincule
algo.

Cuando se comparte, su contenido se muda a la raíz y el curso se queda con la
ubicación:

`shared/documents/d-8a41f0c27b53.yaml`

```yaml
# El Tema 1, compartido por varios cursos.
id: d-8a41f0c27b53
kind: theory
title:
  es: "Tema 1: el número y la recta real"
themes: [tema-1]
structure:
  - section: {es: "¿Qué es la matemática?"}
  - unit: analisis-real-una-variable/que-son-las-mates/que-son-las-matematicas
```

y en cada `year.yaml` que lo usa:

```yaml
documents:
  - id: tema-1-numeros-reales
    link: d-8a41f0c27b53
```

El `id` local se conserva porque es el nombre del `.tex` que compila y el de
la carpeta de salida; el resto —título, tipo, temas, estructura— viene del
fichero compartido. Editar la composición desde cualquiera de los cursos
escribe en el fichero compartido, así que los demás la ven **en la misma
lectura**, no por propagación.

El `.tex` maestro de cada ubicación se sigue generando de la composición
—`compose.py` ya lo hacía—, así que cada curso tiene su master con su portada
y su año, y el cuerpo sale del contenido compartido.

---

## 5. Las cuatro operaciones, que no son la misma

Están separadas en la interfaz y en el código porque confundirlas es cómo se
pierde material.

| Operación | Qué hace con la entidad | Qué hace con las ubicaciones |
|---|---|---|
| **Mover** | nada | quita una y pone otra |
| **Añadir vinculado** | nada | añade una |
| **Duplicar** | crea una nueva, con id nuevo | la nueva ubicación apunta a la nueva |
| **Dividir vinculación** | clona la entidad para un subconjunto | reparte las existentes entre las entidades |

«Duplicar» es «dividir» con un solo elemento en el grupo nuevo, y así está
implementado: una sola operación debajo, cuatro nombres arriba porque lo que
alguien quiere hacer es distinto en cada caso.

### Dividir

Antes: `A, B, C, D` apuntan a `X`.
Se pide: `{A, B}` y `{C, D}`.
Después: `A, B` siguen en `X`; `C, D` apuntan a `Y`, que es una copia de `X`
en el estado actual. Los dos grupos siguen sincronizados **por dentro** y ya
no entre sí.

Es atómica: se preparan todos los ficheros y se escriben juntos, en un solo
commit. Si algo falla, no se escribe nada.

### Dividir un tema, con sus hijos

Un documento lleva lecciones dentro, y separarlo no tiene por qué separarlas.
Lo normal —y lo que se ofrece marcado por defecto— es **quedarse con las
mismas lecciones**: el tema se separa, el material sigue siendo uno. Quien
quiera la rama entera independiente marca «duplicar también las lecciones», y
entonces sí se clona cada una.

Por defecto no se generan ids nuevos para los hijos. Un tema de cuarenta
lecciones dividido en dos asignaturas no debe producir cuarenta lecciones
nuevas que nadie pidió.

---

## 6. Versiones congeladas

Una congelación es **metadatos**, no una copia. Lo que guarda:

`courses/<asignatura>/<año>/freezes.yaml`

```yaml
freezes:
  - id: f-3c07a9e12b64
    name: Inicio curso 2026-27
    description: Como se repartió el primer día.
    created: 2026-09-18T13:41:02+02:00
    commit: 4f2c1d9e8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d
    course: am-i
    year: 2026-2027
```

Está **dentro de git** por la misma razón que todo lo demás: un `clone` en
otro ordenador tiene que ver las mismas congelaciones.

El commit que registra la congelación no puede contener su propio SHA, así
que una congelación apunta al commit que era HEAD cuando se creó. Es lo
correcto: se congela el estado que había, no el de la línea que lo anota.

### Abrirla

1. ¿está el commit en este clon? (`git cat-file -e <sha>^{commit}`)
2. si no, el fetch **mínimo**: primero por SHA, y solo si el servidor no lo
   permite se profundiza la historia por tramos, nunca de golpe;
3. `git worktree add --detach` en una caché fuera del repositorio;
4. se lee el `generated/` **de ese commit**, que ya está versionado, y con él
   se arma un catálogo de solo lectura.

El árbol de trabajo principal no se toca: ni `checkout`, ni `HEAD`, ni el
índice. Una congelación abierta es otra carpeta.

La caché de worktrees vive fuera del repositorio, se reutiliza mientras haga
falta y se puede vaciar entera; ninguna información que importe está solo
ahí.

### Borrarla

Quitar una congelación quita **su entrada del `freezes.yaml`** y su worktree
si lo tenía. No borra commits, no toca la historia, no afecta al curso actual
y no afecta a otra congelación que apunte al mismo commit —el worktree solo
se retira cuando no queda ninguna que lo use.

### Congelaciones y vínculos

Como los vínculos son los ficheros, y los ficheros están en el commit, una
congelación enseña los vínculos **de aquel día**. Si `A+B+C` estaban
vinculados al congelar y después se dividieron en `A+B` y `C`, la congelación
sigue enseñando `A+B+C` y el curso actual enseña la división. Las dos cosas
son ciertas y ninguna se contradice, porque ninguna se guardó dos veces.

---

## 7. Comparar y restaurar

La comparación la calcula git —`git diff --name-status` entre dos árboles— y
la **traduce a términos de Didacta** antes de enseñarla: temas añadidos,
quitados, modificados o movidos; lecciones añadidas, quitadas, modificadas o
movidas; cambios de metadatos; cambios de composición. Desde cualquier fila
se entra al diff del fichero, que es el que ya sabía enseñar el historial.

Restaurar **no reescribe historia**. Nunca hay `reset --hard`, ni force push,
ni commits borrados. Lo que hace es traer el contenido del commit congelado
al árbol de trabajo actual y dejarlo como **un cambio nuevo**, que se confirma
como cualquier otro. Antes de tocar nada dice qué va a cambiar, fichero por
fichero, y avisa si hay cambios locales sin guardar.

---

## 8. Migración

Un repositorio escrito antes de esto no tiene ids de lección. Abrirlo no lo
rompe: sin `id:` declarado, el motor sigue derivándolo de la ruta como
siempre.

Ponerlos al día es una operación **explícita** —`didacta migrate ids`, o el
botón que la lanza— que escribe un `id:` en cada `unit.yaml` que no lo tenga
y lo deja en un commit propio, revisable y reversible. El id se deriva de la
ruta con un hash, así que dos personas que migren el mismo repositorio por su
cuenta escriben **los mismos ids** y el merge no tiene nada que resolver.

Ningún contenido se mueve, ninguna ruta cambia, ninguna historia se pierde.

---

## 9. Lo que las comprobaciones vigilan

`didacta check` mira, además de lo que ya miraba:

* ids duplicados entre entidades distintas;
* ubicaciones que nombran un contenido que no existe;
* ficheros compartidos que no usa nadie;
* ciclos en la estructura;
* un mismo id local repetido dentro de un año;
* restos de una división a medias.
