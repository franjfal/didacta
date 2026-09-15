# Cambios

Lo que cambia en cada versión de Didacta, escrito a mano.

**A mano y no generado desde los commits**, a propósito. Un changelog sacado
de `git log` dice «arregla el test de la barra lateral» y «wip», que es
información para quien escribió el código y ruido para quien lo usa. Lo que
alguien necesita saber antes de actualizar es qué va a poder hacer que antes
no podía, y qué ha dejado de fallar.

La sección de cada versión es **lo que se publica como notas del release** y
lo que se enseña dentro de la aplicación cuando ofrece actualizar. Así que se
escribe pensando en que se va a leer en un diálogo, no en un repositorio:
frases cortas, sin nombres de fichero y sin números de issue.

El formato lo lee `packaging/release.py`, y es el mínimo que hace falta:

```markdown
## 1.4.2 — 2026-09-15

- Lo nuevo…
- Lo mejorado…
- Lo corregido…
```

El encabezado tiene que empezar por `## ` seguido de la versión. La fecha
detrás es opcional y no se usa para nada más que para leerla aquí.

---

## 1.0.0 — 2026-09-15

Primera versión que se distribuye e instala como una aplicación, en lugar de
compilarse en la máquina de cada uno.

- **Didacta se actualiza sola.** Comprueba si hay una versión nueva una vez
  por semana, lo pregunta antes de hacer nada y se encarga del resto. También
  se puede buscar a mano desde Ajustes.
- **Se instala en Windows, macOS y Linux.** Hasta ahora solo había una
  compilación para macOS hecha a mano.
- **Se entra con la cuenta de GitHub**, sin escribir la contraseña dentro de
  la aplicación: se autoriza en github.com y se vuelve. Quien tenga acceso al
  repositorio de versiones puede instalar y actualizar; quien no, no.
- Se trabaja con varios repositorios de contenido a la vez, cada uno con su
  carpeta y su color.
- Edición multilingüe de unidades, de `unit.yaml` y de composiciones, sobre
  clones locales.
