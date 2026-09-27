---
title: Cuando algo falla
description: Los errores que más se ven al compilar, con la carpeta del repositorio y al sincronizar, y qué hacer con cada uno.
---

# Cuando algo falla

Didacta dice qué ha pasado en un aviso que no se va solo, y lo que escribió el
programa --LaTeX, git, GitHub-- queda debajo, en **Detalles**. Esta página
junta los casos que más se ven, cada uno con lo que se hace. Si el tuyo no
está, al final dice cómo contarlo.

## Al compilar

Un error de LaTeX sale con **la lección, el idioma y la línea** donde está, y
**Abrir** lleva allí con el cursor puesto:

```
«Espacios normados» (es) · línea 42 · Undefined control sequence. · \foo   Abrir
```

[:octicons-arrow-right-24: Cuando falla una compilación](../app/compilar.md#cuando-falla)

### «Undefined control sequence»

LaTeX ha encontrado una orden --la que sale al final, `\foo`-- que nadie ha
definido. Casi siempre es una de estas, de más a menos probable:

- **Una errata**: `\fracc`, `\lamda`, `\Rigtharrow`. Es lo primero que hay que
  mirar, y la línea que da Didacta es la buena: la de la lección, no la del
  documento que la incluye.
- **Una orden del material antiguo.** El material migrado usaba macros
  propias de cada departamento. Didacta trae las más comunes en
  `didacta-legacy.sty`; la que no esté, o se cambia por la de LaTeX, o se
  define una vez para todo el repositorio en un
  [snippet](../app/ajustes.md#snippets) con *LaTeX propio*.
- **Una orden de un paquete que Didacta no carga.** Lo mismo: el snippet, o la
  [cabecera de una plantilla](../app/ajustes.md#plantillas) si solo la
  necesita esa salida.

Los nombres de funciones en castellano --`\sen`, `\tg`, `\arcsen`, `\cotg`,
`\senh`-- existen en todos los idiomas, y cada uno escribe el nombre que toca:
una fórmula copiada del castellano al valenciano compila igual. Y una cita sin
bibliografía no rompe nada: sale como `[?]`, y **Revisar** avisa antes.

### «File `X.sty' not found»

A tu distribución de TeX le falta un paquete. Lo que se hace depende de cuál
tengas; [Ajustes → Herramientas](../app/ajustes.md#herramientas) dice cuál es.

=== "TinyTeX"

    Sin contraseña de administrador:

    ```bash
    tlmgr install X
    ```

    Casi siempre el paquete se llama como el fichero, sin `.sty`. Si
    `tlmgr` dice que no existe, pregúntale en cuál está:

    ```bash
    tlmgr search --global --file "/X.sty"
    ```

    y se instala el que diga.

=== "BasicTeX (macOS)"

    Lo mismo que con TinyTeX, pero con la contraseña del Mac:

    ```bash
    sudo tlmgr install X
    ```

    y `tlmgr search --global --file "/X.sty"` si no se llama igual.

=== "MacTeX o TeX Live completa"

    Ya lo traen todo. Si aun así falta, el paquete no está en CTAN y no hay
    orden que lo instale: define lo que uses de él en un snippet o en la
    cabecera de la plantilla.

=== "MiKTeX (Windows)"

    MiKTeX instala cada paquete **la primera vez que un documento lo pide**.
    Si falla, es que esa opción está apagada: en *MiKTeX Console* →
    *Settings*, elige instalar los paquetes que falten sobre la marcha. O a
    mano, en una consola:

    ```bash
    miktex packages install X
    ```

=== "Linux"

    El `tlmgr` del TeX Live de la distribución no suele funcionar: los
    paquetes vienen del gestor de paquetes. En Debian y Ubuntu, casi todo
    está en

    ```bash
    sudo apt install texlive-latex-extra texlive-science
    ```

    y `apt-file search X.sty` dice en cuál está uno concreto. En Fedora,
    `sudo dnf install 'tex(X.sty)'` instala justo el que falta.

Después, **Compilar** otra vez: no hace falta cerrar Didacta.

### MiKTeX sin Perl

`latexmk`, el programa que decide cuántas pasadas de LaTeX hacen falta, está
escrito en Perl. TeX Live y MacTeX traen su Perl; **MiKTeX no**. Se nota
porque nada compila, y el mensaje habla de `perl` o de un *script engine* que
no se encuentra.

Se arregla instalando Perl, en una consola:

```bash
winget install --id StrawberryPerl.StrawberryPerl -e
```

o con el instalador de [strawberryperl.com](https://strawberryperl.com/).
Después **cierra Didacta y vuelve a abrirla**: una aplicación lee dónde están
los programas al arrancar, y la que ya estaba abierta no ve el Perl nuevo.

### «I can't write on file» (Windows)

Windows no deja escribir en un fichero que otro programa tiene abierto. Un
PDF abierto en Acrobat o en el navegador impide compilarlo de nuevo, y LaTeX
lo dice así. Ciérralo y vuelve a compilar.

## La carpeta del repositorio

### «La carpeta del repositorio está ocupada»

Otro programa está usando git en esa carpeta a la vez que Didacta: un
terminal, GitHub Desktop, el editor de código. Espera a que acabe, o ciérralo,
y vuelve a intentarlo.

Si no hay nada más abierto y el aviso sigue, es que un git se cerró a medias y
dejó su candado: el fichero `.git/index.lock`, dentro de la carpeta del
repositorio. **Solo entonces**, bórralo y vuelve a intentarlo.

### OneDrive, Dropbox o iCloud Drive

**No pongas los repositorios dentro de una carpeta que se sincroniza.** El
programa de sincronización y git escriben en los mismos ficheros a la vez:
uno bloquea al otro --y sale el aviso de arriba, o LaTeX no puede escribir--,
y a veces aparecen copias duplicadas con el nombre del ordenador detrás. La
carpeta de salida, `~/Didacta`, está fuera de todas ellas; si los tuyos están
dentro, envía lo que tengas pendiente, quítalos (**Quitar de la lista**) y
vuelve a añadirlos desde GitHub en otra carpeta.

La [carpeta de reparto](../app/ajustes.md#la-carpeta-de-reparto) es otra cosa:
esa sí va en OneDrive o en Drive, porque ahí Didacta solo copia PDF.

### El antivirus

Un antivirus que examina cada fichero que escribe LaTeX puede hacer que
compilar vaya lento o falle de vez en cuando con *Permission denied*, sin que
se repita al volver a intentarlo. Si pasa a menudo, lo que se puede excluir
sin riesgo es la carpeta de compilación, `.didacta-build`, dentro de cada
repositorio: solo tiene lo que Didacta vuelve a generar.

## Al guardar y sincronizar

### «Hay cambios nuevos en GitHub»

Alguien --o tú, desde otro ordenador-- ha enviado algo desde la última vez.
El aviso trae **Traer**: trae sus cambios, y entonces se vuelve a intentar.
Lo tuyo no se pierde.

### «Dos cambios chocan»

El mismo fichero ha cambiado **en otro sitio** desde que lo abriste: otra
ventana, el asistente del [servidor MCP](../app/mcp.md), otro programa que lo
editó en el disco. Lo que has escrito sigue en el editor. Cópialo, vuelve a
cargar el fichero y aplica otra vez tu cambio.

Si pasa **al traer**, es que tú y otra persona habéis guardado cambios
distintos a la vez, y los dos historiales se han separado. Didacta no los
mezcla por su cuenta --una mezcla que nadie ha mirado es la forma de estropear
un tema sin enterarse--: lo dice y no toca nada. Juntarlos es trabajo de git,
en un terminal, en la carpeta del repositorio:

```bash
git pull --rebase
```

Si git dice que hay un conflicto en un fichero, ábrelo: las dos versiones
están entre las marcas `<<<<<<<` y `>>>>>>>`. Deja la buena, borra las marcas y
termina con `git add <fichero>` y `git rebase --continue`. Después, en Didacta,
**Actualizar** (++cmd+r++ o ++ctrl+r++).

### «GitHub no acepta tu sesión»

La sesión ha caducado, o esa cuenta no tiene permiso para escribir en ese
repositorio. **Volver a entrar**, en el aviso, lleva a
[Cuenta y repositorios](../app/ajustes.md#repositorios).

### «GitHub ha rechazado el envío»

Una regla del repositorio no lo permite: una rama protegida, una comprobación
que tiene que pasar antes. Lo tuyo sigue guardado en tu ordenador. Quien
administra el repositorio en GitHub es quien puede cambiar la regla.

### «No se llega a GitHub»

No hay red, o GitHub no contesta. No hay nada que hacer: lo guardado está a
salvo en tu ordenador y se enviará cuando vuelva.

## Si no está aquí

En [Ajustes → Ayuda](../app/ajustes.md#ayuda), **Copiar informe de
diagnóstico** junta lo que ha pasado por dentro --la versión, el sistema, cada
orden del motor y de git con lo que contestó-- sin tus claves ni tus
contraseñas. **Abrir una incidencia** lo lleva ya escrito. Lleva rutas y
nombres de ficheros: échale un vistazo antes de enviarlo.
