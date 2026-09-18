---
title: La composición
description: Qué unidades lleva un documento, en qué orden y con qué apartados.
---

# La composición

![El editor de composición](../img/app/composicion.png)

Un documento es una **lista ordenada de referencias**, con sus apartados. No
lleva materia dentro: cada línea apunta a una unidad de `content/` o de
`problems/`.

## Qué se ve

Cada línea es una referencia que se puede seguir hasta la unidad, y lleva al
lado **el estado del idioma que se está compilando**: si el tema va a salir en
valenciano, lo que decide si sale entero son las unidades, no el documento.

```
▸ Normas                                    ← apartado
  ├ analysis/normed/definition      es va   ← traducida
  ├ analysis/normed/banach          es ·    ← falta el valenciano
  └ analysis/normed/no-existe       ⚠       ← referencia rota
```

!!! danger "Una referencia rota se enseña en su sitio"

    No se omite. Una composición que se salta lo que falta **parece completa y
    compila corta**, y eso se descubre en clase.

## Editar

- **reordenar** arrastrando;
- **añadir** unidades buscándolas en la biblioteca, sin salir de la pantalla;
- **quitar** una entrada, que la comenta en lugar de borrarla;
- **crear apartados**, con su título en cada idioma.

Las entradas comentadas se ven, en gris, y se vuelven a activar con un clic.
Son material que existe y que este año no se da: un estado que una entrada
puede tener, no basura. En la biblioteca migrada eran 905 entradas, y volver a
activar algunas es la edición más común después de una migración.

## Los apartados van en la composición

Y no en las unidades, por lo mismo que el orden: una unidad que declarara «yo
voy en la sección Normas» no se podría reutilizar en un curso que la organice
de otra manera.

```yaml
structure:
  - section:
      es: Normas
      va: Normes
  - unit: analysis/normed/definition
  - unit: analysis/normed/banach
  - section:
      es: Completitud
  - unit: analysis/normed/banach-spaces
```

## El icono de información

Arriba a la derecha, la **ⓘ**, la misma que en una lección. Contesta dónde
está este tema y qué hay guardado de él:

- **Se da en**: los sitios donde se da **este mismo tema**. Un tema vinculado
  en dos grupos son dos, no uno: no son copias, es uno, y lo que se edita
  desde cualquiera se ve en el otro.
- **Pertenece a**: los temas que declara. El que los declara puede ser otro
  repositorio --la teoría en uno y los problemas en otro-- y entonces el
  vínculo no se ve desde el fichero.
- **Versiones congeladas** de su curso académico: verlas y crear una. Estaban
  sólo en la pantalla de Asignaturas, que es donde no estás cuando te lo
  preguntas.
- **Gestionar vinculación…**, cuando está vinculado en varios sitios: parte la
  vinculación en dos, y cada grupo sigue sincronizado por dentro.

## Guardar

Como en todas partes: un commit, con mensaje y con el diff delante. Y con el
mismo cuidado que en `unit.yaml` --las líneas comentadas y los `TODO` de los
títulos que faltan sobreviven a la edición, porque se cambia la línea que toca
y no se reescribe el fichero.

Si la forma del fichero no se reconoce, Didacta lo dice y ofrece el editor de
texto en lugar de adivinar.

## Y el `.tex` del documento

La composición vive en `year.yaml`, que es **la autoridad**: lleva el orden y
los apartados en los tres idiomas. Al lado hay un `<documento>.tex`, que es lo
que compila `pdflatex`, y que repite esa misma lista porque tiene que seguir
funcionando por su cuenta: abrirlo en un editor y compilarlo a mano da el
documento que dice la composición, sin que el motor intervenga.

**Compilar pone los dos de acuerdo.** Antes de llamar a LaTeX, `didacta build`
reescribe el cuerpo del `.tex` con lo que dice `year.yaml` --sólo el cuerpo: el
preámbulo y la portada se quedan como están, y lo que está desactivado sigue
desactivado, comentado--. Así que no hay que tocar ese fichero a mano, y un
subapartado añadido aquí sale en el PDF siguiente.

`didacta check` lo dice antes de compilar, cuando el `.tex` se ha quedado
atrás. Y si el cuerpo lleva LaTeX que la composición no sabe decir --algo
escrito a mano entre las unidades-- el fichero no se toca y se avisa: un `.tex`
que alguien editó no se sacrifica para que el motor tenga razón.
