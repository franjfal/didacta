---
title: Versiones congeladas
description: Guardar el estado de un curso en un momento concreto, abrirlo, compararlo y restaurar desde él.
---

# Versiones congeladas

«¿Cómo estaba este curso el día que empezó?» «¿Qué he cambiado desde el
parcial?» «Quiero el Tema 3 tal como lo di el año pasado.»

Una **versión congelada** es el estado exacto del material de un curso en un
momento concreto, con un nombre que se lee:

```
Inicio curso 2026-27
Antes del primer parcial
Versión final 2026-27
```

Un curso puede tener tantas como quieras.

![Las versiones congeladas de un curso](../img/app/congelaciones-lista.png)

## Es un commit con nombre

Esto es lo primero que hay que saber, porque contesta las dos preguntas que
llegarían si no se dijera.

**No hay ninguna copia detrás.** git ya guarda el contenido de cada commit;
lo que Didacta guarda es lo que git no sabe: que ese commit concreto es «Antes
del primer parcial» y que pertenece a este curso. Tener diez versiones
congeladas no ocupa diez veces más.

**Quitar una no borra nada.** Ni un commit, ni una rama, ni la historia, ni el
curso, ni otra versión congelada — tampoco las que apunten al mismo commit.

!!! info "Entonces, ¿esto es una copia de seguridad?"

    No, y conviene no confundirlo. **La copia de seguridad es el repositorio
    en GitHub**: mientras envíes los commits, tu material está en otro sitio.
    Una versión congelada es un marcador sobre un commit que ya tienes.

    Si nunca envías, una versión congelada no te salva de perder el portátil.
    Lo que te salva es el botón de enviar, y la barra de arriba dice cuántos
    commits llevas sin mandar.

    [:octicons-arrow-right-24: Cómo se guarda y se envía](ajustes.md)

## Congelar

En el menú de un curso académico, **Crear versión congelada…**. Pide un nombre
y, si quieres, una descripción.

Apunta al commit que hay en ese momento. Y ahí está la única regla que hay que
tener en cuenta:

!!! warning "Lo que está sin guardar no entra"

    Una versión congelada apunta a un commit, así que lo que tengas escrito y
    sin confirmar **no forma parte de ella**. El diálogo lo dice antes y
    cuenta cuántos ficheros son: si quieres que entren, guárdalos primero.

## Abrir una

Desde el menú de la versión, **Abrir**. Didacta comprueba si tiene el commit;
si no lo tiene, lo trae —lo mínimo, no la historia entera— y prepara un árbol
de trabajo aparte.

![Mirando una versión congelada](../img/app/congelaciones-mirando.png)

A partir de ahí, **la aplicación entera enseña aquel día**: las asignaturas,
los temas, las lecciones, y también qué estaba vinculado con qué. La banda de
arriba está en todas las pantallas para que sea imposible olvidarlo.

**Es de solo lectura.** Los editores no dejan escribir, y lo dicen con esas
palabras en lugar de fallar al pulsar guardar.

En la misma banda, **Volver a la versión actual** y, detrás de **Qué puedo
hacer**, las dos cosas que tienen sentido desde una foto:

- restaurar este curso desde aquí;
- crear un curso académico nuevo a partir de aquí.

Y en cada tema y en cada lección hay un botón para restaurar solo eso.

!!! info "Tu trabajo no se toca"

    Abrir una versión congelada **no mueve el curso actual**: ni su rama, ni
    sus ficheros, ni lo que tengas a medio escribir. Se mira en otra carpeta.

## Comparar

Desde el menú de una versión: **Comparar con la versión actual** o
**Comparar con…** otra congelada.

![El menú de una versión congelada](../img/app/congelaciones-menu.png)

La comparación la calcula git, pero se lee en términos del material:

```
1 tema nuevo · 1 tema quitado · 6 lecciones

TEMAS DEL CURSO
  + Tema 5: sucesiones          tema nuevo
  − Tema 2: continuidad         ya no está
  · Tema 4: series numéricas    cambiado · ahora está vinculado

LECCIONES
  · countable                   el texto en es
  · countable                   los metadatos de la lección
  → cantor-diagonalization      movido desde analisis/viejo/…
```

Un fichero movido sale **como movido**, que es la diferencia entre
«reorganizaron la carpeta» y «perdimos treinta lecciones». Y un tema que entra
o sale se ve aunque no salga de ninguna ruta: quitar un tema de un curso es
borrar unas líneas de un fichero.

Pulsando cualquier fila se abre el diff del fichero, con lo que se añadió en
verde y lo que se quitó en rojo — el mismo visor del
[historial](historial.md).

## Restaurar

Tres alcances:

| Desde | Qué vuelve |
|---|---|
| **Qué puedo hacer › Restaurar este curso** | el curso entero: sus temas, su orden y sus ficheros |
| El botón de restaurar de un tema | su composición, su `.tex` y —si estaba vinculado— el tema compartido |
| El botón de restaurar de una lección | su carpeta: el texto de cada idioma, las figuras y los metadatos |

Antes de tocar nada, la pantalla **dice qué va a cambiar**, fichero por
fichero, y avisa si hay cambios sin guardar que se vayan a perder.

!!! danger "Restaurar no reescribe la historia"

    Nunca hay `reset --hard`, nunca un envío forzado, nunca un commit borrado.
    Lo que hace restaurar es traer el contenido de aquel commit al estado de
    ahora y **dejarlo como un cambio pendiente**, que se revisa y se confirma
    como cualquier otro.

    Lo que sale es un commit más, encima. Todo lo que hay publicado sigue
    publicado.

Restaurar un tema vinculado lo cambia en **todos** los cursos que lo dan,
porque es el mismo tema. El diálogo lo avisa; para que vuelva solo en uno,
hay que [separarlo antes](vinculos.md#partir-el-grupo).

## Empezar un curso desde una versión

**Crear un curso desde aquí…**, en el menú de la versión. Pregunta asignatura
y curso académico, y copia la composición tal como estaba entonces.

Es el flujo de septiembre: la versión final del año pasado es el punto de
partida del que viene.

Copia **la estructura**: qué temas lleva y en qué orden. Las lecciones son las
de ahora, no copias de las de entonces — para recuperar el texto de entonces
está restaurar.

## Renombrar y quitar

**Renombrar…** cambia el nombre y la descripción; el commit no se toca.

**Quitar esta versión…** pide confirmación y dice qué no se lleva. Se va su
entrada y su carpeta de la caché, y nada más.

## La caché

Abrir una versión congelada prepara una carpeta con los ficheros de aquel
commit. Se guarda para no rehacerla cada vez —comparar, volver, comparar otra
vez es lo que más se hace— y vive dentro de `.git`, así que no aparece en los
cambios pendientes ni se cuela en un commit.

**Vaciar la caché**, en la lista de versiones, la borra entera. No se pierde
nada: las carpetas se vuelven a preparar solas al abrir una versión.

## Si tu clon es superficial

Un clon hecho con `--depth` no tiene la historia entera, y el commit de una
versión congelada de hace un año puede no estar en él. Didacta lo resuelve
cavando **lo menos posible**: primero pide ese commit suelto, después
profundiza la historia por tramos, y solo si nada de eso vale la trae entera.

Un repositorio de material son cientos de megas, y nadie pidió descargarlos por
abrir una versión de septiembre.

## Versiones congeladas y temario compartido

Como los vínculos [son los ficheros](../conceptos/vinculos.md#grupo-de-sincronizacion)
y los ficheros están en el commit, una versión congelada enseña **los vínculos
de aquel día**.

!!! example "Antes y después de una división"

    En octubre, Análisis y Matemáticas daban el mismo tema. Congelas.

    En enero los separas.

    Abrir la versión de octubre sigue enseñando los dos vinculados; el curso
    actual enseña la división. Las dos cosas son ciertas, y ninguna se
    contradice — porque ninguna se guardó dos veces.

## Desde el terminal

```bash
didacta freeze list   analisis@2026-2027
didacta freeze add    analisis@2026-2027 --name "Inicio curso 2026-27" --commit <sha>
didacta freeze rename analisis@2026-2027 <id> --name "Otro nombre"
didacta freeze remove analisis@2026-2027 <id>
```

El SHA tiene que ser el entero, los cuarenta caracteres: uno corto que hoy es
único deja de serlo cuando el repositorio crece, y esto se guarda para años.

## Qué hace falta

Un clon local y git, que es lo normal en escritorio. Las versiones congeladas
se guardan en el repositorio —en `courses/<asignatura>/<año>/freezes.yaml`—
así que un `clone` en otro ordenador ve las mismas.
