# Ejemplo de Didacta

Este repositorio es un ejemplo pequeño y completo de material docente escrito
con [Didacta](https://franjfal.github.io/didacta/): una asignatura
(**Cálculo I**), un curso académico (**2026-2027**), tres documentos y nueve
lecciones sobre límites y continuidad.

Está hecho para abrirlo en la aplicación y trastear. Es tuyo: cambia lo que
quieras, compila, rómpelo. Todo queda en el historial de git, así que nada se
pierde.

---

## La idea, en seis frases

**1. La pieza es la lección.** Una microlección: una definición con su
ejemplo, un teorema con su demostración, un problema. Lo bastante pequeña para
poder reutilizarla y lo bastante grande para que signifique algo. Es una
carpeta con sus metadatos (`unit.yaml`) y un `.tex` por idioma.

**2. Los cursos no copian: referencian.** Un documento --un tema, una hoja de
problemas, un examen-- es una lista de lecciones en `year.yaml`, por su ruta.
Aquí el problema de las discontinuidades está en la hoja 1 y en el primer
parcial, y no hay dos copias: corriges una errata una vez y queda corregida en
los dos.

**3. Una fuente, muchas salidas.** El mismo `.tex` da las diapositivas para
proyectar, las mismas sin pausas para colgar en el aula virtual, los apuntes y
la copia del profesor. Una lección no sabe a qué salida va: la demostración
envuelta en `notesonly` sale en los apuntes y no en las diapositivas, y una
nota `teaching` solo existe en la copia del profesor.

**4. Un curso nuevo copia la estructura, no el contenido.** Empezar el
2027-2028 es duplicar el `year.yaml` --qué se da y en qué orden-- y retocar la
lista. Las lecciones son las mismas.

**5. Cada idioma es un fichero.** `es.tex`, `va.tex`, `en.tex`, dentro de la
misma lección. Lo que falta no lo apunta nadie: Didacta lo ve, lo pone en la
cola de traducción y, mientras tanto, compila con el original en su sitio y
avisa. Un tema con una lección sin traducir se puede dar igual.

**6. Todo vive en git.** Son ficheros de texto en un repositorio de GitHub,
con su historial. Guardar el estado de un curso («Antes del primer parcial»)
es ponerle nombre a un commit.

---

## Qué hay dentro

```
.
├── README.md             esto
├── didacta.yaml          el nombre del repositorio y sus idiomas
├── taxonomy.yaml         cómo se llaman las categorías y los temas de la biblioteca
├── .gitignore            deja fuera lo compilado
│
├── content/              la teoría: una carpeta por lección
│   └── calculo/
│       ├── limites/
│       │   ├── definicion-de-limite/
│       │   │   ├── unit.yaml     título, tipo, idiomas, prerrequisitos
│       │   │   ├── es.tex        el contenido, en castellano
│       │   │   ├── va.tex        el mismo contenido, en valenciano
│       │   │   └── en.tex        y en inglés
│       │   ├── limite-por-definicion/
│       │   ├── algebra-de-limites/
│       │   └── historia-del-epsilon/
│       └── continuidad/
│           ├── funcion-continua/
│           └── teorema-de-bolzano/
│
├── problems/             los problemas, con la misma forma
│   └── calculo/
│       ├── limites/limites-de-cocientes/
│       └── continuidad/
│           ├── discontinuidades-evitables/
│           └── tres-raices-por-bolzano/
│
└── courses/              las asignaturas: aquí no hay materia, solo referencias
    └── calculo-i/
        ├── course.yaml   lo que no cambia de un año a otro: título, grado, profesor
        └── 2026-2027/
            ├── year.yaml     qué se da este año, en qué orden y en qué salidas
            ├── tema-1.tex    de cada documento, la portada y la lista de lecciones
            ├── hoja-1.tex
            └── parcial-1.tex
```

Y dos carpetas que aparecen solas y que no se escriben a mano:

- `.didacta-build/` guarda los PDF. Está en `.gitignore`: se regeneran a
  partir de los `.tex`, y guardarlos en git sería tener lo mismo dos veces.
- `generated/` es el índice que la aplicación escribe para enseñar la
  biblioteca sin abrir cada fichero. Es derivado --se regenera cuando hace
  falta, y siempre sale igual-- pero se guarda en git, como en cualquier
  repositorio de Didacta: un cambio ahí es que el contenido cambió.

Todos los `.yaml` y los `.tex` de los documentos llevan comentarios que
explican para qué sirve cada cosa. Merece la pena abrirlos.

---

## El curso de ejemplo

| Documento | Qué es | Salidas |
|---|---|---|
| **Tema 1: límites y continuidad** | teoría, en dos apartados | diapositivas, diapositivas sin pausas, apuntes, y las dos copias del profesor |
| **Hoja 1: límites y continuidad** | tres problemas | enunciados, con resultados, y la del profesor con soluciones y corrección |
| **Primer parcial** | dos problemas de la hoja | el examen, y su corrección |

Y las lecciones, con los idiomas que tienen:

| Lección | Tipo | es | va | en | Dónde se usa |
|---|---|:---:|:---:|:---:|---|
| Límite de una función en un punto | definición | ✓ | ✓ | ✓ | tema 1 |
| Límites por la definición | ejemplo | ✓ | ✓ | | tema 1 |
| Álgebra de límites | proposición y demostración | ✓ | ✓ | | tema 1 |
| Una breve historia de la épsilon | nota histórica | ✓ | ✓ | | ninguno (comentada en `year.yaml`) |
| Funciones continuas | definición, nota y ejemplos | ✓ | ✓ | | tema 1 |
| El teorema de Bolzano | teorema, demostración y corolario | ✓ | | | tema 1 |
| Límites de cocientes | problema | ✓ | ✓ | ✓ | hoja 1 |
| Discontinuidades evitables | problema | ✓ | ✓ | | hoja 1 y parcial |
| Tres raíces con el teorema de Bolzano | problema | ✓ | | | hoja 1 y parcial |

Los huecos están a propósito: son lo que la pantalla de Traducción tiene que
enseñar. (Y en la vida real el parcial llevaría problemas nuevos; aquí repite
dos de la hoja para que se vea que una lección puede estar en dos sitios sin
estar copiada.)

---

## Qué probar

1. **Abre la asignatura.** En *Asignaturas*, Cálculo I, curso 2026-2027: los
   tres documentos. Antes que nada, pon tu nombre en `course.yaml`, que ahora
   dice «Tu nombre».
2. **Compila el tema 1 en diapositivas y en apuntes.** Es el mismo fichero.
   Fíjate en el teorema de Bolzano: en las diapositivas está el enunciado y en
   los apuntes, además, la demostración. Compila la copia del profesor y
   aparecen las notas didácticas y los errores frecuentes, en rojo.
3. **Compila la hoja 1 en sus tres versiones.** Del mismo fichero salen la
   hoja para repartir, la hoja con los resultados y la del profesor, con la
   solución completa y los criterios de corrección. Luego el parcial: sin
   pistas y con espacio para contestar.
4. **Abre una lección y mira sus idiomas.** «Límite de una función en un
   punto» está en los tres; «El teorema de Bolzano», solo en castellano.
   Compila el tema 1 en valenciano: sale entero, con Bolzano en castellano, y
   Didacta avisa de lo que falta.
5. **Traduce la que falta.** En *Traducción*, la primera de la cola es «Tres
   raíces con el teorema de Bolzano»: la cola se ordena por cuántos documentos
   usan cada lección, y ésta la usan dos. Tradúcela, compila la hoja en
   valenciano y el aviso desaparece.
6. **Reutiliza una lección.** Añade «El teorema de Bolzano» a la hoja 1,
   delante del tercer problema, como recordatorio. O vuelve a dar la nota
   histórica en el tema 1: está comentada en `year.yaml`, y darla es quitar
   una almohadilla. En la biblioteca, cada lección dice en qué documentos
   está.
7. **Corrige una errata una sola vez.** Cambia algo de «Discontinuidades
   evitables» y compila la hoja y el parcial: el cambio está en los dos.
8. **Congela el curso.** En el menú del curso 2026-2027, *Crear versión
   congelada…*, con un nombre como «Antes de tocar nada». Cambia lo que
   quieras y compara después con esa versión, o vuelve a ella.

---

## Una web del curso

Con el curso compilado, desde el terminal:

```bash
didacta site calculo-i@2026-2027
```

deja en `site/` los PDF que se reparten --lo del estudiante: sin las copias
del profesor ni las plantillas de corrección-- y un `index.html` que los
enseña por idioma y por tema. Se sube a GitHub y el workflow
`.github/workflows/web-del-curso.yml` lo publica en GitHub Pages: hay que
encenderlo una vez en *Settings → Pages → Source: GitHub Actions*.

---

## Para seguir

- [La documentación de Didacta](https://franjfal.github.io/didacta/), con la
  aplicación explicada pantalla a pantalla.
- [Todo lo que se puede escribir en una lección](https://franjfal.github.io/didacta/escribir/referencia/):
  `\onlynotes`, `\bymedium`, `teaching`, los entornos de teorema, los cuatro
  niveles de un problema.

Cuando quieras empezar con tu propio material, puedes crear lecciones nuevas
en este mismo repositorio o empezar otro desde cero. Este ejemplo se puede
borrar sin miedo: no hay nada aquí de lo que dependa otra cosa.
