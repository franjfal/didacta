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

**Qué versión.** La que asigne la próxima publicación, que sube la mediana por
su cuenta. La dice:

```
python3 packaging/release.py next
```

Sin esa sección no se publica: el workflow se para antes de compilar nada.

---

## 1.1.0 — 2026-09-15

- **Compilar ya no es una espera a oscuras.** Se abre un terminal que enseña
  lo que LaTeX va escribiendo, línea a línea y mientras compila: qué fichero
  está leyendo, qué paquete carga y en qué pasada va. Vale tanto para una
  unidad suelta como para un tema entero.
- La ventana se quita sola cuando la compilación sale bien y se queda cuando
  algo falla, que es cuando hay algo que leer. El registro se puede volver a
  abrir, y copiar entero.
- **Didacta pide entrar en GitHub para abrirse.** El material está en
  repositorios privados y cada cambio se guarda con el nombre de quien lo hace,
  así que la sesión es el permiso. Se entra una vez; a partir de ahí la
  aplicación abre también sin conexión, y solo vuelve a pedirlo si GitHub deja
  de reconocer la sesión.
- **Solo se abren repositorios de GitHub a los que llegas.** Una carpeta
  cualquiera del disco ya no vale: lo que se escriba en ella no tendría a dónde
  ir. Al añadir un clon se comprueba de qué repositorio es y si tu cuenta
  alcanza ese repositorio, y se pone al día con GitHub en ese momento.
- **Lo que se edita está al día.** Antes de guardar un cambio se comprueba que
  el repositorio no se haya quedado atrás, y si se ha quedado se trae. La
  comprobación vale unos minutos, así que guardar sigue siendo instantáneo. Si
  las dos versiones han seguido por su lado, no se toca nada y se avisa en la
  barra de arriba.

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
