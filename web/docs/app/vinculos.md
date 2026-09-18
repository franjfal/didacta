---
title: Temario compartido
description: Dar el mismo tema en varios cursos y asignaturas, ver dónde está y separarlo después.
---

# Temario compartido

Dar el mismo tema en el curso que viene, en otra asignatura o en el doble
grado, **sin copiarlo**. Lo que se edita desde cualquiera de ellos se ve desde
los demás, porque es el mismo tema y no tres copias que alguien mantiene
iguales.

![Un curso con un tema que se da en tres sitios](../img/app/vinculos-curso.png)

El porqué del modelo —contenido frente a ubicación, y por qué no hay ninguna
tabla de vínculos— está en [Contenido vinculado](../conceptos/vinculos.md).
Esta página es cómo se hace.

## El indicador

En la fila de un tema, al lado del título: un eslabón y un número. Dice **en
cuántos sitios se da**.

Solo aparece cuando hay más de uno. Un indicador que sale siempre no indica
nada.

Pulsándolo se abre la lista de dónde está:

![Las ubicaciones de un tema](../img/app/vinculos-ubicaciones.png)

**Cada una lleva a su sitio.** Pulsar una abre ese curso en ese tema, que es
el gesto que viene justo después de leer la lista: saber que el tema se da
también en el doble grado y tener que buscarlo a mano por la lista de
asignaturas convierte la respuesta en otra tarea.

La ubicación desde la que preguntas sale marcada como **aquí** y no lleva a
ninguna parte. Sale igual, eso sí: «se da en tres sitios» quiere decir tres, y
quitarla de la lista obligaría a sumar uno de cabeza.

## El menú de un tema

![El menú de un tema](../img/app/vinculos-menu.png)

| | |
|---|---|
| **Mover a…** | cambia de sitio esta ubicación |
| **Añadir vinculado a…** | otra ubicación del mismo tema |
| **Duplicar en…** | una copia con identidad propia |
| **Ver ubicaciones vinculadas** | dónde más se da |
| **Gestionar vinculación…** | partir el grupo |
| **Crear copia independiente** | separar solo esta ubicación |

Las tres primeras abren el mismo diálogo, con la operación ya elegida — y con
las tres a la vista, porque la diferencia entre vincular y duplicar solo
importa **en el momento de elegir**, y ahí es donde tiene que estar escrita.

![El diálogo de destino](../img/app/vinculos-destino.png)

**La asignatura actual viene elegida.** Es lo que se hace casi siempre —volver
a dar el mismo tema el curso que viene— y obligar a elegirla cada vez
convertiría lo corriente en un formulario. Cambiarla es un desplegable, y
entonces el tema se puede llevar a cualquier otra asignatura.

!!! warning "Un tema y sus lecciones viven juntos"

    Un tema se puede llevar a otra asignatura, pero **dentro del mismo
    repositorio**: las lecciones que llama tienen que estar al alcance del
    curso de destino. Llevarlo al repositorio de al lado dejaría sus
    referencias fuera de alcance, y compilaría en la máquina de quien tenga
    los dos abiertos y no en la de quien tenga uno.

## Dar una lección en otro tema

Desde la pantalla de una lección, **Darla en otro tema…**. Pregunta tres
cosas, en el orden en que se piensan: asignatura, curso académico y tema.

![Dar una lección en otro tema](../img/app/vinculos-leccion.png)

Vinculada por defecto: es la misma lección, y corregirla sigue siendo
corregirla una vez. La casilla **Llevar una copia independiente** hace lo otro,
y es una decisión que se toma al añadirla, no después.

Si el tema de destino está vinculado, el diálogo lo avisa: la lección entra en
**todos** los cursos que lo dan.

## Separar lo que estaba junto

### Una ubicación suelta

**Crear copia independiente**, en el menú del tema. Esta ubicación se queda con
una copia tal como está ahora, con identidad propia, y deja de sincronizarse
con las demás. Las otras siguen igual.

### Partir el grupo

**Gestionar vinculación…** cuando hay que repartir varias.

![Dividir un grupo de sincronización](../img/app/vinculos-dividir.png)

Se enseñan todas las ubicaciones y se marca a qué grupo va cada una. Se pueden
crear más de dos. Antes de confirmar, la pantalla dice qué va a quedar:

```
Grupo A (conserva la identidad): Análisis I · 2025-2026 · Análisis I · 2026-2027
Grupo B: Matemáticas · 2026-2027 · Doble Grado · 2026-2027
```

Dentro de cada grupo siguen sincronizados. Entre grupos, no.

La casilla **Duplicar también las lecciones del tema** está apagada por
defecto, y con intención: separar dos temas casi nunca quiere decir separar
las cuarenta lecciones que llevan dentro.

!!! info "O se hace entera, o no se hace"

    Dividir toca varios ficheros. Se prepara todo antes de escribir nada y se
    cierra en un solo commit: una división a medias —unas ubicaciones
    repuntadas y otras no— es el peor estado posible, porque no se ve.

## Separar una lección

En la pantalla de una lección, donde dice en cuántas ubicaciones se usa, está
**Gestionar vinculación…**. Funciona igual: se reparten las ubicaciones en
grupos, y cada grupo que se separa recibe una copia de la lección —su texto,
sus figuras y sus metadatos tal como están ahora— con un id propio.

!!! warning "Dos ubicaciones de un tema vinculado son la misma línea"

    Si dos cursos dan el mismo tema, la lección aparece en los dos por la misma
    línea del mismo fichero: separarla en uno y no en el otro no es algo que se
    pueda escribir. Didacta se niega y lo dice. Para eso hay que dividir antes
    el tema.

## Desde el terminal

```bash
didacta places --document analisis@2025-2026/series   # dónde se da
didacta link  --from analisis@2025-2026/series --to matematicas@2026-2027
didacta move  --from analisis@2025-2026/series --to analisis@2026-2027
didacta use   --unit analisis/series/convergencia --in analisis@2026-2027/series
didacta unlink --at matematicas@2026-2027/series
didacta split --content d-8a41f0c27b53 --group "matematicas@2026-2027/series"
```

[:octicons-arrow-right-24: La herramienta, entera](../cli/index.md)
