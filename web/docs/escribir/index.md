---
title: Escribir contenido
description: Lo esencial de un fichero de unidad, en una página.
---

# Escribir contenido

Un fichero de unidad es LaTeX, con un vocabulario añadido que decide **a qué
salidas va cada trozo**. Esta página es lo esencial; la
[referencia completa](referencia.md) está al lado.

## El esqueleto

```latex
\begin{frame}
\didactatitle{Definición de espacio normado}

Todo lo que no diga nada sale en todas las salidas.

\onlyslides{Solo en las diapositivas.}
\onlynotes{Solo en los apuntes y en el libro.}
\onlyteacher{Solo en las copias del profesor.}
\end{frame}
```

`\begin{frame}` **no significa «diapositiva»**: es la unidad de contenido. Con
un perfil de diapositivas sale como una diapositiva; con uno de apuntes, como
un bloque de texto seguido.

`\didactatitle` es el título de la unidad, y sale donde cada medio lo espere:
como título de la diapositiva, o como encabezado de la sección.

## Los tres canales

| Orden | Diapositivas | Apuntes | Profesor |
|---|:---:|:---:|:---:|
| *(nada)* | ✓ | ✓ | ✓ |
| `\onlyslides` | ✓ | | ✓ si el perfil es de diapositivas |
| `\onlynotes` | | ✓ | ✓ si el perfil es de documento |
| `\onlyteacher` | | | ✓ |

## Los teoremas

```latex
\begin{definition}[Espacio normado]
Un par $(E, \|\cdot\|)$ tal que\ldots
\end{definition}

\begin{theorem}[Hahn--Banach]
Toda forma lineal acotada en un subespacio se extiende\ldots
\end{theorem}

\begin{proof}
Por el lema de Zorn\ldots
\end{proof}
```

Hay `definition`, `theorem`, `proposition`, `lemma`, `corollary`, `example`,
`remark`, `question` y `proof`. Cada uno tiene **dos aspectos**: en
diapositivas son un recuadro de color, y en documento un bloque con su
numeración.

Los nombres --«Definición», «Definició», «Definition»-- los pone el idioma del
documento, no el fichero.

## Las pausas

```latex
La serie converge.
\pause
Y su suma es $\pi^2/6$.
```

`\pause` se respeta en `slides` y se ignora en `slides-flat` y en todos los
perfiles de documento.

## Las notas de clase

```latex
\begin{teaching}[Ritmo]
Quince minutos. Detente en la homogeneidad: es donde se atascan.
\end{teaching}
```

**Nunca sale en un documento del alumno**, en ningún perfil y por ningún
descuido, porque los perfiles del alumno no tienen ese canal.

## Los problemas

```latex
\begin{problem}[Convergencia]
Estudia la convergencia de $\sum 1/n^2$.

\hint{Compárala con una integral.}
\answer{Converge; su suma es $\pi^2/6$.}
\solution{Por el criterio integral\ldots}
\marking{1 punto por plantear, 1 por calcular, 0{,}5 por concluir.}
\end{problem}
```

[:octicons-arrow-right-24: Los cuatro niveles](../conceptos/problemas.md)

## Las figuras

Viven en `figures/`, dentro del directorio de la unidad, y se llaman por su
nombre:

```latex
\didactafigure{bola-unidad}{La bola unidad de tres normas de $\mathbb{R}^2$.}
```

La ruta la resuelve Didacta, así que mover la unidad no rompe la figura.

## La referencia completa

Todo lo demás --fórmulas destacadas, recuadros sin etiqueta, bibliografía,
alias heredados del sistema anterior, los detalles de cada entorno-- está en
la referencia:

[La referencia de escritura](referencia.md){ .md-button .md-button--primary }
