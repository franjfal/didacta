---
title: Didacta
template: home.html
hide:
  - navigation
  - toc
---

## Todo tu material, en un sitio

La biblioteca es todo lo que has escrito, de todos tus repositorios, ordenado
por materia. Tres clics hasta cualquier lección, y cada nivel te dice cuánto
hay y cuánto está traducido.

![La biblioteca de Didacta](img/app/biblioteca.png)

## Escribe una vez, reparte en todos los formatos

Una lección se escribe una sola vez. Lo que decide si sale en diapositivas, en
apuntes o en la copia del profesor no es el fichero: es el formato con el que
lo compilas.

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

De ese fichero salen **quince documentos distintos**, sin tocar nada más:

```mermaid
flowchart LR
  U["Una lección<br/>es.tex"] --> S["Diapositivas"]
  U --> A["Apuntes"]
  U --> L["Libro"]
  U --> P["Hoja de problemas"]
  U --> E["Examen"]
  U --> T["Copia del profesor"]
```

El párrafo de `\onlynotes` solo aparece en los apuntes. La nota de ritmo, solo
en tu copia. Y todo eso en castellano, valenciano o inglés, según lo que la
lección tenga escrito.

[Las quince salidas](conceptos/perfiles.md){ .md-button }

## Prepara el curso arrastrando

Un tema es una lista de lecciones en orden. Se reordena arrastrando, se añaden
desde la biblioteca, y lo que este año no das se queda comentado en lugar de
borrarse: el año que viene se vuelve a activar con un clic.

![La composición de un tema](img/app/composicion.png)

**Dar el mismo tema otro año es duplicar el curso.** Las lecciones siguen
siendo las mismas: lo que corrijas una vez sale corregido en todas partes, y el
PDF del año pasado sigue como se dio.

## Compila y compara sin salir

![Elegir qué versiones se compilan](img/app/unidad-compilar.png)

Eliges versiones e idiomas, y los PDF se abren **dentro de la ventana**, uno al
lado del otro: las diapositivas junto a los apuntes, el castellano junto al
valenciano. Mientras compila ves lo que LaTeX va escribiendo, y cuando algo
falla te dice el fichero y la línea.

## Traduce por donde importa

![Lo que falta por traducir](img/app/traduccion.png)

Lo que falta, ordenado **por cuántos documentos usan cada lección**: traducir
una que usan seis cursos te compra seis documentos. Y lo que es peor que no
estar traducido --una traducción cuyo original cambió-- va primero, porque
compila sin quejarse y dice algo que ya no es cierto.

Hay traducción automática para el primer borrador, que protege las fórmulas y
las órdenes de LaTeX antes de mandar nada.

## Nada se pierde

![El historial de un fichero](img/app/historial.png)

Cada cambio queda con tu nombre y su mensaje, y puedes ver cómo estaba
cualquier fichero en cualquier momento, sin salir a un terminal.

Y como todo vive en repositorios de GitHub, **compartes lo que quieras
compartir**: la colección de problemas con el departamento, tus apuntes solo
contigo.

<div class="didacta-latest" markdown>
:material-clock-fast: **Se empieza en diez minutos.** Instalar, entrar en
GitHub y abrir el primer repositorio lo hace la propia aplicación la primera
vez que la abres.
</div>

## Descargar

--8<-- "descargas.md"

## Por dónde seguir

<div class="grid cards" markdown>

-   :material-rocket-launch-outline: __Nunca la he usado__

    ---

    Instalar, entrar en GitHub, abrir el primer repositorio y compilar algo.

    [:octicons-arrow-right-24: Empezar](empezar/index.md)

-   :material-application-outline: __Enséñame la aplicación__

    ---

    Pantalla por pantalla, con capturas: qué hace cada una y cómo se usa.

    [:octicons-arrow-right-24: La aplicación](app/index.md)

-   :material-lightbulb-on-outline: __¿Cómo funciona esto?__

    ---

    Microlecciones, las quince salidas, los idiomas y los repositorios.

    [:octicons-arrow-right-24: Cómo funciona](conceptos/index.md)

-   :material-pencil-ruler: __Quiero escribir contenido__

    ---

    Todo lo que se puede poner en una lección: teoremas, problemas, figuras,
    notas de clase.

    [:octicons-arrow-right-24: Escribir](escribir/index.md)

</div>
