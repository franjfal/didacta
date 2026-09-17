---
title: Didacta
template: home.html
hide:
  - navigation
  - toc
---

## Qué problema resuelve

Dar una asignatura produce, cada año, el mismo material en cinco formas
distintas: las diapositivas de clase, los apuntes que se reparten, la hoja de
problemas, la hoja con las soluciones y el examen. Y si la asignatura se da en
más de un idioma, otra vez todo.

Lo normal es que esas formas sean **ficheros distintos**. Entonces se corrige
una errata en las diapositivas y no en los apuntes; se mejora una explicación
en los apuntes de este año y la del año que viene sale del fichero de hace
tres; y la versión valenciana se queda diciendo lo que el castellano decía
antes de la última revisión.

Didacta parte de lo contrario:

```
EL CONTENIDO SE ESCRIBE UNA VEZ.
LAS ASIGNATURAS SON COMPOSICIONES.
LOS IDIOMAS SON VARIANTES DE LA MISMA ENTIDAD.
LAS SALIDAS SE GENERAN.
```

## Un fichero, y lo que sale de él

Esto es una unidad --una microlección-- entera:

```latex
\begin{frame}
\didactatitle{Definición de espacio normado}

La métrica usual en $\mathbb{R}$ es $d(x,y) = |x-y|$.

\onlynotes{La idea es generalizar las propiedades útiles de esa distancia.}

\begin{definition}[Espacio normado]
Un par $(E, \|\cdot\|)$ tal que\ldots
\end{definition}

\begin{teaching}[Ritmo]
Quince minutos. Detente en la homogeneidad.
\end{teaching}
\end{frame}
```

El fichero **no sabe a qué documento va**. Lo deciden los interruptores:
`\onlynotes` solo aparece en los apuntes, `teaching` solo en la copia del
profesor, y la clase del documento --beamer o article-- la elige el perfil con
el que se compile. De ahí salen, sin tocar nada más:

| | |
|---|---|
| `slides` | las diapositivas de clase |
| `notes` | los apuntes del alumno, con el párrafo de explicación |
| `notes-teacher` | los apuntes con las notas de ritmo y las soluciones |
| `book` | el mismo contenido encuadernado como libro |
| … | [y once salidas más](conceptos/perfiles.md) |

Y en cada idioma que la unidad tenga.

## Cómo se trabaja

<div class="grid cards" markdown>

-   :material-file-document-multiple-outline: __Se escriben unidades__

    ---

    Un directorio por lección, con un fichero por idioma y sus figuras al
    lado. Ni el año ni la asignatura entran en el nombre.

    [:octicons-arrow-right-24: Qué es una unidad](conceptos/unidades.md)

-   :material-format-list-numbered: __Se componen cursos__

    ---

    Un curso académico es una selección y un orden: qué unidades, en qué
    documentos, en qué idioma. Ningún contenido.

    [:octicons-arrow-right-24: Asignaturas y cursos](app/asignaturas.md)

-   :material-file-pdf-box: __Se compila__

    ---

    Didacta llama a LaTeX y enseña el PDF dentro de la ventana, al lado del
    original y de las demás versiones.

    [:octicons-arrow-right-24: Compilar](app/compilar.md)

-   :material-source-branch: __Se guarda en GitHub__

    ---

    Cada cambio es un commit. El material se comparte por repositorio: la
    colección de problemas común, los apuntes de cada uno.

    [:octicons-arrow-right-24: Repositorios](conceptos/repositorios.md)

</div>

## Descargar

--8<-- "descargas.md"

## Por dónde seguir

<div class="grid cards" markdown>

-   :material-rocket-launch-outline: __Nunca la he usado__

    ---

    Instalar, entrar en GitHub, abrir el primer repositorio y compilar algo.
    Media hora.

    [:octicons-arrow-right-24: Empezar](empezar/index.md)

-   :material-lightbulb-on-outline: __Quiero entender la idea__

    ---

    Microlecciones, perfiles, los cuatro niveles de un problema y cómo se
    tratan los idiomas.

    [:octicons-arrow-right-24: Cómo funciona](conceptos/index.md)

-   :material-application-outline: __Ya la tengo abierta__

    ---

    Pantalla por pantalla, con capturas: qué hace cada una y por qué está
    así.

    [:octicons-arrow-right-24: La aplicación](app/index.md)

-   :material-code-tags: __Vengo por el código__

    ---

    La arquitectura, cómo se publica una versión y cómo contribuir. Todo es
    software libre bajo la GPL-3.0.

    [:octicons-arrow-right-24: El proyecto](proyecto/index.md)

</div>
