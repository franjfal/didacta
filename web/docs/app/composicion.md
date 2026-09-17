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

## Guardar

Como en todas partes: un commit, con mensaje y con el diff delante. Y con el
mismo cuidado que en `unit.yaml` --las líneas comentadas y los `TODO` de los
títulos que faltan sobreviven a la edición, porque se cambia la línea que toca
y no se reescribe el fichero.

Si la forma del fichero no se reconoce, Didacta lo dice y ofrece el editor de
texto en lugar de adivinar.
