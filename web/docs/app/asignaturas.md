---
title: Asignaturas y cursos
description: Crear, duplicar y borrar asignaturas, cursos académicos y documentos.
---

# Asignaturas y cursos

![La pantalla de asignaturas](../img/app/asignaturas.png)

Es la pantalla que se abre cada día. Tres niveles:

```
Asignatura            Análisis Matemático III
└── Curso académico   2025-2026, grupo A
    └── Documento     Tema 1 · Hoja 1 · Parcial
```

## Qué se ve, y qué no

Es la pantalla por la que se entra: al abrir Didacta lo que se viene a hacer es
preparar una clase, y eso empieza en la asignatura que se da mañana.

Después de unos años, la lista son veinte asignaturas de las que se dan tres.
Dos formas de arreglarlo, y ninguna toca el material:

- **ocultar** una asignatura o un curso académico, en el `⋯` de su fila:
  **Ocultar de esta lista**. Sigue en el repositorio, sigue compilando y sigue
  en la biblioteca: lo que cambia es esta lista. Lo oculto lleva un ojo a la
  vista, que es el camino de vuelta;
- **plegar** una asignatura pulsando su título. Plegada dice cuántos cursos
  lleva dentro.

Arriba se elige qué se mira: **las que doy** --lo de todos los días--, **las
ocultas** --para volver a enseñar algo-- o **todas**, donde lo oculto sale
marcado. Sin la segunda, ocultar sería un viaje sin vuelta.

Lo elegido **se queda puesto**, y viaja con el resto de preferencias. Quien se
pone a ordenar la lista se queda un rato en «las ocultas», y volver de un curso
para encontrarse otra vez «las que doy» convertiría esa tarde en un baile de
clics.

!!! info "La estrella no reordena"

    Marcar una asignatura o un curso dice «esta me importa», y nada más. Subían
    al principio y era peor: la lista dejaba de estar donde se aprendió que
    estaba, y marcar una movía otras cuatro de sitio. Para no ver lo que no se
    da está ocultar.

## La asignatura

`course.yaml` guarda lo que **no cambia de un año a otro**: el título en cada
idioma, el código, la titulación, la institución, a qué idiomas se traduce.

Las asignaturas y los cursos se pueden marcar con la estrella. Marcar dice
«esta me importa» y no cambia el orden: para que en una cuenta con diecisiete
asignaturas queden a la vista las tres de este cuatrimestre, lo que se hace es
ocultar las demás.

## El curso académico

![Un curso académico y sus documentos](../img/app/curso.png)

`year.yaml` guarda **la selección y el orden de este año**: qué documentos hay,
qué unidades lleva cada uno y en qué orden, con sus apartados.

### Llevarse un curso

En la fila de cada curso académico, al lado de la estrella, está el botón de
**exportar**: pregunta la carpeta y deja allí los PDF compilados, con nombres
que se leen. Y en el listado de documentos, cada documento tiene el suyo, para
cuando lo que hay que subir al aula virtual es solo el Tema 3.

Exportar **copia**: el repositorio no se toca, y no hace falta poder escribir
en él. Y de salida solo se lleva lo del estudiante: las resoluciones y las
copias del profesor se piden aparte. Los detalles, en
[Exportar un curso](exportar.md).

### Duplicar un año

El botón **Duplicar**, o desde el terminal:

```bash
didacta new year am-iii 2026-2027
```

Copia la estructura. **No copia contenido**, porque no hay contenido que
copiar: las unidades siguen siendo las mismas. Lo que corrijas este año lo
hereda el siguiente, y el PDF del año pasado sigue exactamente como se dio,
porque sigue en su commit.

Copiando de un curso, el diálogo trae marcada la casilla **Congelar
2025-2026 tal como quedó**: antes de copiar, deja una versión congelada del
curso de origen --«Tal como quedó»-- para poder volver a verlo y compilarlo
como se dio, pase lo que pase después. Se copian también sus temas, y los
documentos quedan agrupados bajo ellos igual que estaban.

!!! warning "Los documentos vinculados se comparten, no se copian"

    Si el curso de origen tiene documentos vinculados, el nuevo los comparte:
    lo que cambies en ellos en 2026-2027 cambia también en 2025-2026. El
    diálogo lo dice, con cuántos son. Para separarlos, en el curso nuevo,
    **Crear copia independiente** en el menú de cada uno. La congelación es la
    que guarda 2025-2026 como se dio, en cualquier caso.

En una asignatura repartida entre varios repositorios, duplicar, quitar y
congelar se hacen **en todos** los que tienen algo de ella, con una sola
espera. Si uno falla a medio camino, el aviso dice en cuáles sí se hizo.

Y hay una variante que es la de septiembre: crear el curso nuevo **a partir de
una versión congelada**, de modo que el punto de partida sea el curso tal como
quedó en junio y no como está hoy.

[:octicons-arrow-right-24: Versiones congeladas](congelaciones.md)

### Guardar cómo quedó

En el menú de cada curso académico, **Crear versión congelada…** y **Ver
versiones congeladas…**. Una versión congelada es el estado exacto del
material en un momento —«Inicio curso 2026-27», «Antes del primer parcial»—
que después se puede abrir, comparar con el de ahora y restaurar.

No es una copia: es un commit con nombre, así que tener diez no ocupa diez
veces más y quitar una no borra nada.

[:octicons-arrow-right-24: Versiones congeladas](congelaciones.md)

### Borrar

Borrar dice **qué se lleva, contado**: «esta asignatura tiene dos años y
setenta y siete documentos» es lo que permite decidir; «¿seguro?» no lo es. El
recuento lo da el motor en seco, sin borrar nada.

Y dice qué **no** se lleva: las unidades no se tocan. Lo que se pierde es la
selección y el orden. Sin esa frase, borrar una asignatura parece borrar el
material, y nadie lo pulsaría.

Si tiene versiones congeladas, también lo dice: viven en la carpeta del curso y
se van con él. Sus commits siguen en la historia, pero dejan de tener nombre.

### Deshacer

**El aviso de después trae «Deshacer».** Quitar una asignatura, un curso
académico o un documento --y cualquier otro guardado de un curso: reordenar,
cambiar un título-- se deshace desde el aviso que sale al terminar. Deshacer
es un cambio más, con su mensaje: lo que había vuelve y lo deshecho sigue en la
historia.

**Cuando el aviso ya se fue, «Cambios recientes».** El botón con el reloj, en
la cabecera de Asignaturas, enseña lo último que se ha guardado en cada
repositorio, con quién y cuándo, y un **Deshacer** en cada uno. Solo deshace
si nadie ha vuelto a tocar esos ficheros después: si alguno cambió, lo dice y
no hace nada, porque deshacer encima se llevaría también lo de después. Para
eso está el [historial](historial.md) de cada fichero.

## Los documentos

Un documento es un tema, una hoja de problemas, un guion de prácticas o un
examen. Se crea vacío --sin unidades-- porque elegirlas es el paso siguiente y
tiene su propia pantalla.

El identificador se deduce del título, y se puede cambiar a mano. Al guardar
se escribe también su `<documento>.tex`, el fichero que compila LaTeX, en el
mismo cambio que `year.yaml`.

En su fila, a la vista, lo de cada día: **el PDF** y **▶** para compilarlo. Lo
demás está en `⋯`: exportarlo, cambiarle el título, darlo en otro sitio y
quitarlo del curso. Quitar el curso académico entero está en el `⋯` de su
cabecera, junto a congelarlo.

### Un examen o una hoja, a partir de los problemas

Abajo, **Examen u hoja de problemas** lo hace de una vez: el tipo, el título,
el tema al que va y los problemas, y un solo guardado. La lista ofrece solo
problemas, con un buscador y un filtro por carpeta, y marca los que ya
salieron en un examen de la asignatura --«examen 2024-2025»--; la casilla
**Sin los que ya salieron** los quita de la lista.

Van en el orden en que se eligen, y se reordenan después en la composición.
El repositorio no se pregunta: lo dicen los problemas, porque un documento y
lo que llama viven en el mismo. Al guardar se abre el documento, listo para
compilar el examen y su hoja de corrección.

!!! note "Qué exámenes cuenta"

    Los de los cursos que siguen en el repositorio. Un curso que se quitó no
    cuenta: su versión congelada es la que guarda qué salió entonces.

### Qué salidas tiene un tema

En la pantalla del tema, en el panel de la derecha. Por defecto compila lo que
digan los bloques de las lecciones que lleva dentro --un tema con su teoría y
sus ejercicios hereda de los dos-- y el botón **Elegir salidas** lo aparta:

```yaml
documents:
  - id: tema-1
    templates: [notes]
```

Volver a «lo que toque» quita la línea. Y una lista vacía no significa
«ninguna» en ningún sitio: sin lista se compila lo que toque, que es lo que
evita quedarse sin salidas sin haberlo pedido.

### Filtrar por bloque

Cuando el curso tiene documentos de más de un [bloque](ajustes.md#bloques)
--teoría y problemas, o esos y prácticas-- aparece una tira discreta encima de
la lista para quedarse con uno.

Un documento no declara bloque: lo **hereda** de las lecciones que compone,
así que un tema con su teoría y sus ejercicios sale con los dos filtros. Es lo
correcto, porque está en los dos. Y uno todavía sin lecciones no se esconde
nunca: es el que se acaba de crear.

Con un solo bloque la tira no aparece.

[:octicons-arrow-right-24: La composición](composicion.md)

### Darlo también en otro sitio

En el menú `⋯` de cada tema: **Mover a…**, **Añadir vinculado a…** y
**Duplicar en…**, con la asignatura actual elegida por defecto y cualquier
otra a un desplegable.

**Duplicar** es una copia de la composición con identidad propia: cambiar el
orden o los apartados de una no toca la otra, y un tema vinculado deja de
estarlo en la copia. Las lecciones siguen siendo las mismas --corregir una se
ve en las dos-- salvo que se marque **Duplicar también las lecciones**, que
copia cada una con su propia identidad.

Vinculado quiere decir que es **el mismo tema**: lo que se edite desde
cualquiera de los cursos que lo dan se ve desde todos. Un eslabón con un
número en la fila dice en cuántos sitios está, y desde ahí se ve dónde y se
separan cuando dejen de ir juntos.

[:octicons-arrow-right-24: Temario compartido](vinculos.md)

## Las titulaciones

Cada grado enseña **en qué repositorios está declarado**, con una casilla por
repositorio: se declara en otro de un toque, y se deja de declarar igual.
Quitarlo del último no pierde nada --sus asignaturas salen enteras, sin
agrupar-- y la propia pantalla las enseña abajo como «nombradas y sin
declarar».

Un grado agrupa asignaturas, y se gestiona desde aquí y no desde Ajustes: es
una clasificación del material, como un tema, no una preferencia de la
persona.

**Quién declara qué importa.** Un grado lo declara un repositorio y las
asignaturas de cualquier otro lo nombran; con que uno lo declare, todos lo ven
agrupado. Declararlo en dos no rompe nada --se juntan por identificador-- pero
es lo que hace que luego discrepen, así que al crear uno se pregunta dónde.

Y nada de esto puede romper nada: un grado que no declara ningún repositorio
abierto no agrupa, y sus asignaturas salen sueltas.
