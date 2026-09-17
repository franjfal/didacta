---
title: Los primeros diez minutos
description: Un recorrido completo: encontrar una lección, editarla, compilarla y guardarla.
---

# Los primeros diez minutos

Con Didacta abierta y un repositorio dentro, este es el recorrido entero: de
buscar una lección a tener un PDF y un commit. Si prefieres que te lo cuente
la propia aplicación, el **tour guiado** está en
:material-cog-outline: **Ajustes → Volver a ver la presentación**.

## El armazón

A la izquierda, el carril. Cuatro sitios, y el orden dice para qué sirve cada
uno:

| | | |
|---|---|---|
| :material-school: | **Asignaturas** | lo que estás dando este cuatrimestre. Es lo que se abre cada día |
| :material-library-books: | **Biblioteca** | todo el material, ordenado por materia. Es cómo se busca |
| :material-translate: | **Traducción** | qué falta por traducir, en el orden que merece la pena hacerlo |
| :material-cog: | **Ajustes** | tu cuenta, tus repositorios, LaTeX, actualizaciones |

Arriba, la **barra de sincronización**: en qué repositorio estás trabajando,
cuántos cambios tienes sin enviar y cuántos hay en GitHub que no tienes. Está
en el armazón y no escondida en Ajustes a propósito: dónde va a parar lo que
escribes no debería ser nunca un misterio.

[:octicons-arrow-right-24: El armazón, en detalle](../app/index.md)

## 1. Encontrar una lección

Entra en **Biblioteca**.

![La biblioteca de Didacta, en vista de árbol](../img/app/biblioteca.png)

Al entrar está en **Explorar**: el material en columnas, como está en el
disco. Cada nivel dice cuánto contiene y cuánto está traducido al idioma que
estás mirando. Tres clics hasta cualquier unidad.

En cuanto escribes, cambia a **Buscar** y la lista se aplana: «hilbert» no es
un sitio del árbol, es todo lo que lo menciona.

[:octicons-arrow-right-24: La biblioteca](../app/biblioteca.md)

## 2. Abrirla y editarla

![Una unidad abierta, con su editor](../img/app/unidad.png)

Arriba de la unidad hay una fila de pestañas, y el orden no es casual:

- **un idioma por pestaña** (`es`, `va`, `en`…), con el color de su estado de
  traducción. Solo se carga la que abres;
- **compilar**, delante de los metadatos, porque es lo que se hace entre una
  edición y la siguiente;
- **`unit.yaml`**, los metadatos, que se tocan una vez cada varios meses;
- **historial**, cómo estaba este fichero en cada versión;
- y después, **una pestaña por cada PDF** que tengas abierto.

Escribe algo. El editor conoce LaTeX: resalta la sintaxis, tiene una barra con
los entornos de Didacta y avisa de los caracteres que LaTeX se reserva.

A la derecha, el panel de la unidad dice **en qué documentos se usa**. Es la
respuesta a «¿puedo cambiar esto?», y no es una pregunta retórica: una unidad
que aparece en seis cursos se toca con más cuidado que una que no usa nadie.

[:octicons-arrow-right-24: La unidad y su editor](../app/unidad.md)

## 3. Compilarla

Pulsa **Compilar**. Puedes mantenerlo pulsado para elegir perfiles e idiomas.

El PDF se abre **como una pestaña más**, al lado del original. Dos PDF a la
vez se ponen lado a lado, que es lo que hace falta para comparar «cómo queda
en diapositivas» con «cómo queda en apuntes», o el castellano con el
valenciano.

Mientras compila, la consola enseña lo que el motor va escribiendo. No es
adorno: un botón que pone «Compilando…» durante un minuto no se distingue de
un cuelgue.

[:octicons-arrow-right-24: Compilar](../app/compilar.md)

## 4. Guardarla

Guardar **es hacer un commit**, y pide un mensaje. No es ceremonia: el mensaje
es lo que hace que el historial se pueda leer dentro de un año, y un
«editar x» por defecto produce un registro que no sirve a nadie. Didacta
propone uno que dice qué ha cambiado; se puede sustituir.

Antes de confirmar se ve el diff.

Tres reglas que la aplicación impone siempre:

- **todo cambio es un commit**, con autor y mensaje. No hay un «guardar» que
  haga algo menos rastreable;
- **una escritura comprueba antes que nadie se te ha adelantado**. Si el
  fichero se movió desde que lo abriste, falla y lo dice, en lugar de
  sobrescribir a quien llegó primero;
- **un conflicto no se resuelve reintentando**. El editor ofrece recargar.

Enviar a GitHub es el botón de la barra de sincronización. Un commit **no
necesita conexión**; enviarlo, sí.

## 5. Componer un tema

Entra en **Asignaturas** → tu asignatura → el curso → un documento.

![La composición de un documento](../img/app/composicion.png)

Un documento es una **lista ordenada de referencias** a unidades, con sus
apartados. No contiene materia: la materia está en las unidades. Se reordena
arrastrando, se añaden unidades desde la biblioteca, y las referencias rotas
se ven en su sitio en vez de desaparecer --una composición que se salta lo que
falta parece completa y compila corta.

De ahí salen los PDF del tema entero, en los perfiles que tenga declarados.

[:octicons-arrow-right-24: Asignaturas y cursos](../app/asignaturas.md)

## Y el año que viene

Duplicar un curso es copiar un fichero de estructura: la selección y el orden,
sin tocar el contenido.

```bash
didacta new year am-iii 2026-2027
```

o el botón **Duplicar** en la pantalla de la asignatura. Las unidades siguen
siendo las mismas: lo que corrijas en una este año lo hereda el que viene, y
lo que corrijas el año que viene no rompe el PDF del anterior, porque el
anterior sigue en su commit.

## Por dónde seguir

<div class="grid cards" markdown>

-   :material-lightbulb-on-outline: __Entender la idea__

    ---

    Por qué el contenido no sabe a qué documento va, y qué gana eso.

    [:octicons-arrow-right-24: Cómo funciona](../conceptos/index.md)

-   :material-pencil-ruler: __Escribir contenido__

    ---

    Todo lo que se puede poner en un fichero de unidad: entornos, problemas,
    canal del profesor, figuras.

    [:octicons-arrow-right-24: Escribir](../escribir/index.md)

</div>
