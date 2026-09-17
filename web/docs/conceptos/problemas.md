---
title: Los cuatro niveles de un problema
description: Enunciado, resultado, solución y corrección, en un solo fichero.
---

# Los cuatro niveles de un problema

Un problema en Didacta es **un fichero con cuatro campos**, y las versiones
que se reparten los revelan por niveles.

```latex
\begin{problem}[Convergencia de una serie]
Estudia la convergencia de $\sum_{n\ge 1} \frac{1}{n^2}$.

\hint{Compárala con una integral.}

\answer{Converge, y su suma es $\pi^2/6$.}

\solution{
  La función $f(x)=1/x^2$ es positiva y decreciente en $[1,\infty)$,
  así que\ldots
}

\marking{
  1 punto por plantear el criterio integral, 1 por calcular la integral,
  0{,}5 por concluir. Un error de cálculo con el método bien planteado
  no baja de 1{,}5.
}
\end{problem}
```

|  | `hint` | `answer` | `solution` | `marking` |
|---|:---:|:---:|:---:|:---:|
| `problems` · alumnos, solo enunciados | ✓ | | | |
| `problems-answers` · alumnos, con resultados | ✓ | ✓ | | |
| `problems-teacher` · profesor, todo | ✓ | ✓ | ✓ | ✓ |
| `exam` | | | | |
| `exam-marking` · la corrección | | ✓ | ✓ | ✓ |

En los dos perfiles de examen **las pistas no salen**, tampoco en el del
profesor: en un examen no hay pista que dar, y quien corrige no la necesita.

Qué es cada uno:

`hint`
:   La pista. Una frase que desatasca sin resolver.

`answer`
:   **El resultado, en una línea.** Para que el alumno pueda corregirse solo
    sin leerse la solución entera. Es el campo que más se echa de menos cuando
    no está y el que menos cuesta escribir.

`solution`
:   El desarrollo completo.

`marking`
:   Qué buscar al corregir y cuánto vale cada parte. Nunca sale en un
    documento del alumno.

## Lo mismo vale para un guion de prácticas

Un documento con ejercicios dentro se reparte, se corrige y se entrega igual
venga de donde venga, así que los perfiles `handout-*` hacen exactamente lo
mismo que los `problems-*`:

| | qué revela |
|---|---|
| `handout` | el guion, con los enunciados |
| `handout-answers` | y los resultados |
| `handout-teacher` | y las soluciones y la corrección |

## Por qué en un solo fichero

La alternativa --un fichero de enunciados y otro de soluciones-- se rompe
sola. Se renumera un ejercicio y las soluciones dejan de corresponder; se
mejora un enunciado y la solución sigue resolviendo el anterior; y nadie se
entera hasta que un alumno lo dice en clase.

Con los cuatro campos juntos no hay forma de que se desincronicen, porque no
hay dos sitios.

## Un examen

`exam` no revela nada, ni siquiera la pista. `exam-marking` lleva el resultado,
la solución y los criterios de corrección, y es lo que se lleva quien corrige.
Los dos usan además una maquetación propia, con espacio numerado para
contestar.

Un examen es una composición como cualquier otra: una lista de referencias a
problemas que ya existen.

```yaml
documents:
  - id: parcial-1
    kind: exam
    title: {es: "Primer parcial"}
    profiles: [exam, exam-marking]
    structure:
      - problem: analysis/series/convergence
      - problem: analysis/normed/exercises
```
