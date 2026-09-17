---
title: La distribución de TeX
description: Qué instalar para poder compilar, y qué hacer si Didacta no la encuentra.
---

# La distribución de TeX

Didacta genera PDF llamando a LaTeX, así que hace falta una distribución de TeX
en la máquina. **Didacta no lleva una dentro**, y conviene decir por qué:

- la completa son varios gigas, y meterla en cada instalador sería repartir
  varios gigas a cada persona para que use tres paquetes;
- **qué versión de cada paquete se usa lo tiene que poder elegir quien
  compila**, no la aplicación;
- las actualizaciones de CTAN no pueden depender de que alguien publique una
  versión de Didacta.

Lo que sí hace es **encontrar la que haya**, y decir dónde ha mirado cuando no
encuentra ninguna.

## Cuál instalar

Sirve cualquiera de estas. Hace falta **TeX Live 2023 o posterior**, con
`latexmk`.

| Sistema | Opción cómoda | Opción ligera |
|---|---|---|
| macOS | [MacTeX](https://tug.org/mactex/) (~5 GB) | `brew install --cask basictex` (~100 MB) |
| Windows | [TeX Live](https://tug.org/texlive/) o [MiKTeX](https://miktex.org/) | MiKTeX instala paquetes según los necesita |
| Linux | el `texlive-full` de tu distribución | `texlive` + `texlive-latex-extra` + `latexmk` |
| las tres | [TinyTeX](https://yihui.org/tinytex/), ~100 MB y ampliable con `tlmgr` | |

!!! tip "Todos los paquetes que Didacta usa están en CTAN"

    Una TeX Live estándar basta: no hay que instalar ningún `.sty` suelto ni
    ninguna fuente empaquetada aparte. Eso es un requisito del sistema, no una
    casualidad, y es lo que permite compilar en una máquina limpia o en un
    runner de integración continua.

    Con una instalación mínima como BasicTeX o TinyTeX puede faltar algún
    paquete la primera vez. El log lo dice con nombre y apellido, y se añade
    con `tlmgr install <paquete>`.

## Si Didacta no la encuentra

Aparece en **Ajustes → Compilación**, con la lista de los sitios donde ha
mirado. Hay un botón para buscar otra vez y un campo para decirle dónde está.

Esto pasa más de lo que parece, y la razón no es evidente:

!!! warning "Una aplicación no hereda el PATH del terminal"

    Cuando lanzas Didacta desde el Finder o desde el menú de aplicaciones, el
    sistema le da un PATH mínimo: en macOS, `/usr/bin:/bin:/usr/sbin:/sbin` y
    nada más. Y `latexmk` vive en `/Library/TeX/texbin`, que entra en el PATH
    porque lo añade `/etc/paths.d/TeX`, **que solo lee un shell de login**.

    El resultado era una Didacta diciendo «hace falta una distribución de TeX»
    con TeX Live instalada y compilando perfectamente en el terminal.

    Por eso Didacta busca en los sitios de siempre en lugar de preguntarle al
    PATH: las rutas por defecto de TeX Live, MacTeX, MiKTeX y TinyTeX. Lo que
    se escriba en Ajustes manda sobre todo eso.

## Comprobarlo desde el terminal

Si quieres saber qué ve tu sistema antes de abrir Didacta:

```bash
latexmk --version
kpsewhich article.cls
```

La segunda orden dice si LaTeX encuentra sus propias clases. Si la primera
falla pero el binario existe, el problema es el PATH y no la instalación.
