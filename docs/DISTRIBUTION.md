# Distribución y actualización

Cómo llega Didacta a la máquina de alguien, y cómo se mantiene al día.

---

## 1. Cómo se reparte

Didacta es una aplicación de escritorio para tres sistemas, y **el código es
abierto**. Eso resuelve de golpe la pregunta que antes era la difícil --quién
puede instalarla-- y deja solo las dos de verdad: que llegue a la máquina de
quien la quiera, y que se mantenga al día sin que nadie se acuerde de nada.

```
                  franjfal/didacta  (público)
                         │
   «Publish Didacta      │   compila macOS/Windows/Linux
    Release»  ───────────┤   publica el release aquí mismo
                         │   y dispara el despliegue de la web
                         │
      ┌──────────────────┼───────────────────┐
      ▼                  ▼                   ▼
   la web            Releases            Didacta, sola
   (descarga)        (descarga)          (actualización)
```

Un solo repositorio, y eso es un cambio respecto a cómo empezó esto. Antes
había dos: el código en uno privado y las versiones en otro, también privado,
para poder dar acceso a las segundas sin dar el primero. Con el código abierto
esa separación no separa nada, así que se fue, y con ella la GitHub App de
publicación, sus dos secrets y la lista de colaboradores que había que
mantener.

## 2. Lo que eso simplificó

Conviene dejarlo dicho, porque son cosas que estaban y ya no están:

- **no hay comprobación de autorización.** Antes, después de entrar en GitHub,
  la aplicación preguntaba si esa cuenta llegaba al repositorio de versiones y
  se cerraba si no. Ahora cualquiera puede descargarla y usarla; a lo que hay
  que tener acceso es al material de cada uno, que es otra cosa y la sigue
  diciendo GitHub;
- **el actualizador no manda ninguna credencial.** La API pública basta.
  Está explicado en `app/lib/data/release_channel.dart`;
- **la página de descarga es una página de verdad**, no el README de un
  repositorio privado. Ver la sección 7.

## 3. La versión: una sola fuente, y la sube el ciclo

`app/pubspec.yaml`:

```yaml
version: 1.4.2+142
```

De ahí sale **todo**: el tag (`v1.4.2`), el nombre de los artefactos, lo que la
aplicación dice de sí misma, y lo que declara el manifiesto. Ningún otro sitio
escribe un número de versión a mano.

**Y ese número no lo escribe nadie: lo sube la publicación.** Cada release sube
una parte --la que diga `release.yaml`-- y el build de uno en uno. Esa línea
deja de ser algo que se edita antes de publicar y pasa a ser el registro de lo
último que se publicó.

**Cuánto sube lo dice `release.yaml`**, en la raíz del repositorio:

```yaml
bump: minor
```

| `bump` | También vale | 1.4.2 → | Para |
|---|---|---|---|
| `major` | `grande` | 2.0.0 | algo que obliga a aprender otra vez |
| `minor` | `mediana` | 1.5.0 | lo de siempre: lo hecho desde la anterior |
| `patch` | `pequeña` | 1.4.3 | sólo arreglos |

Tres reglas que lo hacen difícil de estropear:

- **Vale para una publicación.** El commit final del workflow, el que escribe
  la versión en `pubspec.yaml`, deja también `release.yaml` otra vez en
  `minor`. Una grande que se quedara puesta haría grande la siguiente, y la de
  después, sin que nadie lo hubiera pedido.
- **Una errata para, no publica otra cosa.** Una clave que no existe
  (`bumb:`), un valor que no es ninguno de los seis, una línea repetida o
  sangrada: el workflow se para en su primer paso, antes de compilar, y dice
  qué línea es. Los tests de `packaging/` lo leen también en cada pull request.
- **Es un fichero del repositorio y no un campo del botón**, para que los
  cuatro trabajos, que descargan el mismo commit, lean exactamente lo mismo, y
  para que la decisión quede en el historial junto a sus notas.

Crecer es añadir una línea a `PLAN_KEYS`, en `release.py`: cómo se lee la
clave y qué vale si no está.

```
$ python3 packaging/release.py plan
bump: minor (mediana) · 1.4.2 → 1.5.0
$ python3 packaging/release.py next
1.5.0
```

El parche vuelve a cero --1.5.0 y no 1.5.2--: lo que una mediana dice es «otra
tanda de cambios», y arrastrar el parche de la anterior no significa nada.

Por qué la mediana si nadie dice nada: lo que cada versión trae es lo que se
haya hecho desde la anterior. Un parche afirmaría que sólo se han arreglado
cosas, y eso lo tiene que decir alguien a propósito.

**Cómo llega ese número a los cuatro trabajos** sin pasarse un commit entre
ellos: cada uno ejecuta `release.py bump` sobre su propia copia nada más
descargarla. La función es determinista, así que los cuatro llegan al mismo
sitio, y el binario lleva dentro el número con el que se publica. El commit se
hace al final, en `publicar`, cuando el release ya existe -- así un fallo a
mitad de camino, o un ensayo, no gastan un número.

La aplicación no lee una constante del código sino el paquete construido
(`Info.plist` en macOS, `version.json` en Windows y Linux), vía
`package_info_plus`. Una constante puede quedarse atrás de la compilación; el
paquete que se está ejecutando, no. Está en `app/lib/data/app_info.dart`.

La comparación es **semántica**, en `app/lib/model/app_version.dart`. Existe
porque comparar como texto dice que `1.10.0 < 1.9.0`, y el síntoma de ese fallo
no es un error sino algo peor: una actualización que nunca se ofrece.

## 4. Publicar una versión

Dos pasos:

1. escribir arriba de `CHANGELOG.md` lo que trae la versión. Si todavía no
   sabes el número, `## Próxima` vale: se lo pone el paso siguiente;
2. `python3 packaging/publish.py`.

```
¿Cómo es esta versión?
  1) pequeña   0.1.0 → 0.1.1    sólo arreglos
  2) mediana   0.1.0 → 0.2.0    lo de siempre: lo hecho desde la anterior   ← la de release.yaml
  3) grande    0.1.0 → 1.0.0    algo que obliga a aprender otra vez
```

Después pregunta si se publica o se ensaya, enseña lo que va a hacer y pide un
«sí». Antes de escribir nada comprueba lo que suele salir mal:

- que estás en `main` y al día con GitHub --después de cada publicación el
  workflow deja allí un commit con la versión, y lo ofrece traer--;
- que el número no está publicado ya, ni en un borrador a medias;
- que hay notas para él, y si la sección de arriba tiene otro título, le pone
  el que toca;
- **lo que no va a entrar**: se compila lo que hay en GitHub, así que un
  cambio sin commit no va en la versión, y lo dice con la lista delante;
- que no hay otra publicación en marcha.

Si se le dice que sí, deja la parte en `release.yaml`, hace un commit
«Preparar Didacta X» con eso y el CHANGELOG --sólo con eso--, lo sube y lanza el
workflow con `gh`. Si `gh` no está instalado (`brew install gh && gh auth
login`), hace todo lo demás y abre la página del botón. Al final ofrece
quedarse siguiendo el workflow.

`--part`, `--dry-run` y `--yes` lo dejan contestado de antemano; `--yes` dice
que sí a las preguntas, pero no se salta ninguna comprobación.

Sin el script también se puede: escribir la sección con el número que diga
`python3 packaging/release.py next`, poner la parte en `release.yaml`, y
GitHub → Actions → **Publish Didacta Release** → Run workflow.

`app/pubspec.yaml` no se toca. Subirlo a mano se salta un número, porque el
ciclo lo subirá igual la próxima vez.

El workflow (`.github/workflows/release.yml`) hace, en este orden:

| # | Trabajo | Qué hace |
|---|---|---|
| 1 | `comprobar` | Sube el número, exige la sección del CHANGELOG, comprueba que el tag no exista ya |
| 2 | `pruebas` | Tests de Python, tests de Dart, `flutter analyze --fatal-infos`, formato |
| 3 | `construir` | macOS, Windows y Linux **en paralelo, sin `fail-fast`**, cada uno con el número ya subido |
| 4 | `publicar` | Solo si los tres salieron. Publica el release --GitHub crea el tag sobre el commit compilado-- y al final escribe la versión nueva en `main` y deja `release.yaml` en `minor` |

El orden importa. Descubrir que falta la sección del CHANGELOG después de tres
compilaciones de quince minutos es tirar media hora por algo que se ve en un
segundo.

**Sin `fail-fast`** a propósito: si Windows falla, hay que poder ver si Linux y
macOS estaban bien. Cancelar los otros dos esconde justo eso.

**Nunca se publica media versión.** `publicar` solo se ejecuta si la matriz
entera salió, y además comprueba que los cuatro artefactos estén antes de tocar
nada.

### El release se crea en borrador

Y se publica al final, en un solo acto:

```
crear release (draft) → subir 200 MB de binarios → generar el manifiesto
con los identificadores que GitHub acaba de asignar → subirlo → --draft=false
```

Mientras se suben los binarios, `releases/latest` no devuelve nada, y la
aplicación además ignora explícitamente los borradores. Si algo se rompe a la
mitad, lo que queda es un borrador invisible.

### Ensayo

`dry_run` compila los tres sistemas y comprueba todo, pero no publica. Sirve
para saber si una versión compila en Windows sin gastar un número: el commit
con la versión nueva sólo lo hace `publicar`, así que después de un ensayo la
próxima publicación asigna ese mismo número.

### Si la publicación sale pero el commit de la versión no

El último paso de `publicar` escribe `app/pubspec.yaml` en `main`. El tag no:
lo crea GitHub al publicar el release, sobre el commit que se compiló
(`$GITHUB_SHA`). Crearlo también desde el workflow chocaba con ése, y la 0.1.0
salió publicada con el trabajo marcado en rojo por eso. Si alguien empujó a la rama mientras se compilaba, reintenta poniéndose
detrás; si aun así no puede --una rama protegida, por ejemplo--, el trabajo
falla diciéndolo, y la versión ya está publicada. Entonces hay que subir esa
línea a mano, o la siguiente publicación repetirá el número y se parará en la
comprobación de que el tag no exista.

## 5. Qué se genera

| Sistema | Artefacto | Para qué |
|---|---|---|
| macOS | `Didacta-X.Y.Z-macos-universal.dmg` | Instalar a mano |
| macOS | `Didacta-X.Y.Z-macos-universal.zip` | **El actualizador** |
| Windows | `Didacta-X.Y.Z-windows-x64.exe` | Las dos cosas |
| Linux | `Didacta-X.Y.Z-linux-x64.AppImage` | Las dos cosas |

Y junto a ellos, `SHA256SUMS.txt` y `latest.json`.

**Un solo artefacto de macOS y no dos por arquitectura.** `flutter build macos`
produce ya un binario universal arm64 + x64 en un solo paso. Publicar un
`-arm64` y un `-x64` con el mismo contenido sería inventar una elección que
nadie tiene que hacer.

**Dos empaquetados de macOS, eso sí.** El DMG es lo que espera una persona; el
ZIP es lo que necesita el actualizador, porque descomprimir y mover una carpeta
son dos órdenes, mientras que montar un DMG, copiar y desmontarlo desde el
propio programa que se está sustituyendo son tres formas más de fallar. Es lo
que hace Sparkle, por lo mismo.

**Windows: Inno Setup, instalación por usuario.** `PrivilegesRequired=lowest`
manda a `%LOCALAPPDATA%\Programs\Didacta`, donde se puede instalar y actualizar
sin UAC. No se usa MSIX porque exige firma obligatoria para poder instalarse, y
eso dejaría Windows sin versión hasta que haya certificado.

**Linux: AppImage.** Es un solo fichero, así que actualizarlo es sustituir ese
fichero con un `mv` --atómico en el mismo sistema de ficheros-- y relanzarlo.
Un `.deb` lo gobierna el gestor de paquetes, y escribirle los ficheros por
debajo le rompe la base de datos.

## 6. El manifiesto

`latest.json`, publicado **como asset del release**:

```json
{
  "version": "1.4.2",
  "build": 142,
  "tag": "v1.4.2",
  "publishedAt": "2026-09-15T10:00:00Z",
  "releaseNotes": "- Lo nuevo…",
  "assets": [
    {
      "platform": "macos",
      "architecture": "universal",
      "kind": "update",
      "name": "Didacta-1.4.2-macos-universal.zip",
      "size": 94371840,
      "sha256": "e3b0c442…",
      "assetId": 219384756
    }
  ]
}
```

Tres decisiones, y las tres importan:

**Como asset y no como fichero del repositorio ni como página.** Hereda la
privacidad del release: se descarga solo con un token que tenga acceso. El
manifiesto dice dónde están los binarios, así que un manifiesto público sería
un inventario público de lo privado.

**`assetId` y no una URL.** Es lo que la API pide para descargar con un
`Authorization:`, que es el único camino que respeta que el repositorio sea
privado. No se guarda ningún `browser_download_url` ni ningún enlace firmado
que pudiera sobrevivir a que a alguien se le retire el acceso.

**`kind`.** Un release lleva dos artefactos de macOS y los dos son «el de
macOS». Sin este campo el actualizador acabaría intentando montar un DMG.

## 7. La página de descarga

Es **la web**, en `web/`, publicada en GitHub Pages desde este mismo
repositorio: <https://franjfal.github.io/didacta/descargas/>.

El bloque de descargas no se escribe a mano ni se guarda en el repositorio: lo
genera `packaging/web.py` **leyendo el release publicado**, en el momento de
construir la web.

```bash
python3 packaging/web.py downloads --repo franjfal/didacta
```

Que lea el release y no un fichero importa el día que haya que volver atrás:
marcar otra versión como la última es un `gh release edit --latest`, y con
esto la web se corrige volviendo a desplegarla, sin publicar nada y sin tocar
ningún fichero.

Y si no hay ningún release --el primer día, o un fork-- escribe un bloque que
lo dice y explica cómo compilar. Una web que no se puede estrenar hasta que
haya binarios es una web que se estrena tarde.

Durante una publicación el manifiesto ya está en el disco del runner, así que
también se le puede dar directamente:

```bash
python3 packaging/web.py downloads --manifest latest.json
```

El despliegue lo hace `.github/workflows/site.yml`, que se lanza al empujar a
`main`, al terminar una publicación y a mano. Genera además las capturas de
pantalla ejecutando la propia aplicación (`flutter test
tool/generate_screenshots.dart`), así que la documentación enseña siempre la
versión de ahora.

## 8. Autenticación: OAuth Device Flow

Ya existía en `app/lib/data/github.dart` y no se ha sustituido.

```
Didacta → «Entrar en GitHub» → enseña ABCD-1234
       → la persona lo escribe en github.com/login/device
       → autoriza allí → Didacta recibe el token
```

Por qué el device flow y no un redirect con callback:

- **no hay secreto que guardar.** Un `client_id` es público; una aplicación de
  escritorio no puede esconder un `client_secret`, así que un flujo que lo
  exija es un flujo que se está usando mal;
- **no hace falta un servidor** que atienda la redirección;
- **la contraseña no pasa por Didacta.** Se teclea en github.com y en ningún
  otro sitio, que es la única forma honesta de pedirla.

El token va al **llavero del sistema** (`flutter_secure_storage`): Keychain en
macOS, Credential Manager en Windows, Secret Service en Linux. Nunca a
`SharedPreferences`, ni a un JSON, ni a un log. Está en
`app/lib/data/repository_access.dart`.

El alcance pedido es `repo` y nada más. Sin `delete_repo`, sin `admin`, sin
`user`.

### El Client ID va escrito en el código

`Ov23liZqSOY4xMvnXU4Z`, en `app/lib/main.dart`. **No es un descuido y no es un
secreto filtrado**, y conviene dejarlo dicho porque la pregunta se hace sola al
ver un identificador dentro de un repositorio público:

- un Client ID **viaja en la URL de cada autorización**, así que ya lo ve en la
  barra de direcciones cualquiera que entre;
- el secreto de una aplicación de OAuth es el **client secret**, y el device
  flow no lo usa. Existe justamente porque una aplicación de escritorio no
  puede esconder un secreto dentro de un binario que reparte;
- con el Client ID y nada más, lo único que se puede hacer es pedir un código
  que **una persona tiene que autorizar en github.com**. No da acceso a nada.

Lo hacen igual `gh`, VS Code y GitHub Desktop, y por el mismo motivo. Lo que se
gana es lo que decide si alguien llega a usar Didacta: al abrirla por primera
vez hay **un botón**, y no un campo pidiendo que te crees una aplicación de
OAuth en GitHub antes de poder empezar. El campo sigue estando, detrás de
«Entrar con otra aplicación de OAuth», para quien monte su propio despliegue;
y `--dart-define=DIDACTA_GITHUB_CLIENT=…` lo cambia al compilar.

Lo único que un Client ID ajeno permite es montar una aplicación que enseñe
«Didacta» en la pantalla de autorización de GitHub. Es así para cualquier
aplicación de escritorio y no se arregla escondiéndolo.

### La OAuth App de la gente y el token del CI son dos cosas

Y no se mezclan nunca:

| | Quién la usa | Para qué | Dónde vive |
|---|---|---|---|
| **OAuth App** | Las personas | Entrar, clonar | Client ID en el código, token en el llavero de cada uno |
| **`GITHUB_TOKEN`** | El workflow | Crear el release, construir la web | Lo da Actions en cada ejecución |

Reutilizar la OAuth App como credencial de publicación daría a cada persona que
entra el permiso de publicar versiones.

## 9. Quién puede usar Didacta

Cualquiera. Es software libre, y descargarla no pide nada.

Entrar en GitHub sí hace falta, pero por otro motivo: **el material vive en
repositorios**, y quién puede leer o escribir en cada uno lo dice GitHub. La
aplicación no mantiene ninguna otra lista, ni tiene cuentas propias, ni
comprueba ninguna autorización suya.

## 10. Cómo actualiza

`app/lib/state/update_service.dart`, con `checkForUpdates()`,
`downloadUpdate()` e `installUpdate()`.

**Cuándo.** Cada siete días, en segundo plano, después de que la aplicación
esté en pie. Ni al arrancar --retrasaría la primera pantalla por una petición
que a nadie le urge-- ni cada vez, que es cómo un aviso útil se convierte en
ruido que se cierra sin leer. Y a mano desde **Ajustes → Actualizaciones**.

**Si no hay nada nuevo, no se dice nada.** Un «ya estás al día» que nadie ha
pedido es una interrupción.

**El flujo completo:**

```
1. descargar, con progreso y cancelable
2. comprobar el SHA-256   ← si no cuadra, se borra y no se instala. Nunca.
3. comprobar el tamaño
4. extraer y comprobar que dentro hay una aplicación de verdad
5. comprobar la firma, si la versión instalada está firmada
6. escribir el script de sustitución
   ── hasta aquí, la instalación que funciona no se ha tocado ──
7. cerrar Didacta
8. el script sustituye, con copia de seguridad
9. relanza
```

**El programa que se actualiza no puede ser el que actualiza.** Un ejecutable no
puede reemplazarse mientras corre: en Windows el fichero está bloqueado, y en
macOS borrar el `.app` bajo los pies de la aplicación la deja sin sus recursos.
Por eso la sustitución la hace un script externo, lanzado con
`ProcessStartMode.detached`, que espera a que el proceso termine (con tope de
60 segundos) y entonces actúa.

| Sistema | Cómo sustituye |
|---|---|
| macOS | `ditto` del ZIP; el `.app` anterior se aparta, no se borra; si falla, vuelve |
| Windows | Ejecuta el instalador con `/SILENT`; su Restart Manager hace el resto |
| Linux | `cp` al lado + `mv -f` sobre el AppImage (atómico); copia de seguridad antes |

**Rollback.** La versión anterior se aparta y solo desaparece cuando la nueva ya
está en su sitio y se ha comprobado que su ejecutable existe. Si algo falla
entre medias, el script la devuelve.

**Y se comprueba que salió.** Antes de cerrar, la aplicación apunta a qué
versión se estaba actualizando; al arrancar, compara esa nota con la versión
que de verdad está corriendo. Si coincide, lo dice y se puede cerrar el aviso;
si no, dice que no se completó y cuál se está ejecutando. Sin esto, una
sustitución que falló y se restauró correctamente sería indistinguible de una
que salió, y alguien podría quedarse creyendo que tiene una versión que no
tiene.

**Si no se puede escribir donde está instalada** --una Didacta en
`/Applications` con una cuenta que no es administradora-- se dice antes de
descargar nada. Se comprueba escribiendo de verdad en la carpeta y no mirando
los permisos: en macOS el bit de escritura puede decir que sí y una ACL decir
que no.

**Errores.** Sin red, GitHub caído, token caducado, token revocado, sin acceso,
release corrupta, checksum incorrecto, descarga interrumpida, sin espacio, sin
permisos, cancelado por la persona: todos están en `UpdateProblem` y todos
tienen un mensaje en castellano. **Ninguno impide usar Didacta.**

## 10.bis Cómo se prueba

Tres capas, porque ninguna sola vale:

| Qué | Dónde | Qué coge |
|---|---|---|
| Unitario | `app/test/app_version_test.dart`, `update_manifest_test.dart` | Comparar versiones, leer un manifiesto roto, elegir artefacto |
| Con red falsa | `app/test/update_service_test.dart`, `update_ui_test.dart` | Los códigos de estado de GitHub, los estados del servicio, lo que se ve |
| Con red de verdad | `packaging/e2e-macos.sh` | **El contrato con GitHub** |

La tercera es la que importa y es la que no se puede saltar. Los dos fallos
que tenía el workflow al escribirlo solo se veían ejecutándolo:

- **un release en borrador no tiene tag** --el tag de git se crea al
  publicarlo--, así que pedir los assets por `releases/tags/` devuelve 404
  justo en el momento en que el workflow los necesita;
- `gh release view --json assets` devuelve el identificador de **GraphQL**
  (`RA_kwDO…`) y la API de descarga pide el **numérico**. El manifiesto habría
  salido con identificadores que no descargan nada.

Ninguno de los dos se ve leyendo el código.

```bash
DIDACTA_E2E_TOKEN=$(gh auth token) \
  packaging/e2e-macos.sh ~/Applications/Didacta.app
```

Prepara una **copia** de esa Didacta en una carpeta temporal y actualiza la
copia, así que se puede ejecutar con Didacta abierta sin tocarla. Comprueba,
por este orden: el acceso al repositorio privado, que un token inválido se
rechaza, el manifiesto, que la copia es más vieja que lo publicado, la
descarga por `assetId`, el SHA-256, que preparar no ha sustituido nada
todavía, la sustitución, que la copia de seguridad se limpió, que arranca, y
que lo que está corriendo dice ser la versión nueva.

**Lo único manual que queda** es pulsar «Actualizar ahora» en la ventana. Ese
camino --el diálogo, el progreso, «más tarde», los mensajes de error-- está
cubierto por `update_ui_test.dart` contra el mismo `UpdateService`; lo que no
se automatiza es el clic.

## 11. Firma

### macOS

Hoy **no hay certificado de Developer ID**, y el sistema está hecho para que eso
no impida publicar: `packaging/macos/sign.sh` avisa y sigue. Un DMG sin firmar
se abre con el aviso de Gatekeeper que le corresponde, que es lo honesto.

Lo que **no** se hace en ningún caso: quitarle el `com.apple.quarantine` a
nadie, recomendar `spctl --master-disable`, ni permitir que el actualizador
instale una versión sin firmar encima de una firmada.

Cuando haya certificado, añadir estos secrets y ya está:

| Secret | Qué es |
|---|---|
| `MACOS_CERTIFICATE` | El `.p12` del Developer ID Application, en base64 |
| `MACOS_CERTIFICATE_PASSWORD` | Su contraseña |
| `MACOS_SIGNING_IDENTITY` | `Developer ID Application: Nombre (TEAMID)` |
| `MACOS_NOTARY_APPLE_ID` | El Apple ID de la cuenta de desarrollador |
| `MACOS_NOTARY_TEAM_ID` | El Team ID |
| `MACOS_NOTARY_PASSWORD` | Una contraseña específica de aplicación |

```bash
base64 -i DeveloperID.p12 | pbcopy
```

El orden de la firma es de dentro afuera, con `--options runtime` (el hardened
runtime, que la notarización exige), y luego notarizar y **grapar** el ticket
para que se pueda abrir sin conexión. `codesign --deep` no se usa: Apple lo
desaconseja justo para esto, porque no firma bien los frameworks anidados de
Flutter.

El sandbox está desactivado a propósito y seguirá estándolo: la aplicación
ejecuta `git` y lee carpetas elegidas en sesiones anteriores, y un sandbox no
permite ninguna de las dos. Eso descarta la Mac App Store, que aquí no importa.

### Windows

Igual: sin `WINDOWS_CERTIFICATE` se publica sin firmar, y SmartScreen avisará
la primera vez («Más información» → «Ejecutar de todas formas»).

| Secret | Qué es |
|---|---|
| `WINDOWS_CERTIFICATE` | El `.pfx` de code signing, en base64 |
| `WINDOWS_CERTIFICATE_PASSWORD` | Su contraseña |

Se firma **el ejecutable antes de meterlo en el instalador, y el instalador
después**. Firmar solo el instalador dejaría a SmartScreen avisando al ejecutar
el programa.

## 12. Los secrets

En `franjfal/didacta` → Settings → Secrets and variables → Actions.

**Ninguno es imprescindible.** El workflow publica con el `GITHUB_TOKEN` que
Actions le da a cada ejecución: dura lo que dura el trabajo, solo sirve para
este repositorio, y no hay nada que crear, que renovar ni que pueda caducar sin
avisar.

Antes sí hacía falta uno --una GitHub App con `Contents: write` sobre el
repositorio privado de versiones-- y se fue con él. Es la clase de pieza que
funciona durante un año y falla el día que hay prisa.

**Opcionales**, los de firma, en las dos tablas de arriba. Sin ellos se publica
sin firmar, que es lo que pasa hoy.

Nada más. No hay ningún token en el código, ni en ningún fichero del
repositorio, ni se escribe ninguno en un log.

## 13. Operaciones

### Dar acceso a alguien

No hay nada que dar: la aplicación es pública y se descarga de
[la web](https://franjfal.github.io/didacta/descargas/) o de Releases.

Lo que sí se da o se quita es el acceso **al material**, y eso son los permisos
de cada repositorio de contenido en GitHub. Si hace falta invalidar el token de
alguien ahora mismo, en la OAuth App → *Revoke all user tokens*.

### Rollback

Un release publicado no se borra: se marca otro como el último.

```bash
gh release edit v1.4.1 -R franjfal/didacta --latest
```

A partir de ese momento `releases/latest` devuelve la 1.4.1, y quien tenga la
1.4.2 instalada **no** recibirá una oferta de bajar: la comparación es
`publicada > instalada`, así que nadie se degrada solo. Quien tenga la 1.4.0 sí
recibirá la 1.4.1.

Para que la 1.4.2 no se pueda instalar a nadie más:

```bash
gh release edit v1.4.2 -R franjfal/didacta --draft
```

Y después publicar una 1.4.3 con lo corregido, que es lo que arregla el
problema de verdad.

La web se corrige volviéndola a desplegar --Actions → **Publish the
documentation site** → Run workflow--: lee el release que esté marcado como el
último, así que no hay que tocar ningún fichero.

### Si una versión rompe la instalación de quien la tenía

No debería poder pasar --el paquete se valida entero antes de tocar nada y hay
copia de seguridad-- pero si pasara: el DMG, el `.exe` y el AppImage de la
versión anterior siguen en Releases, y se instalan encima.

### Subir el mínimo soportado

Si una versión cambia el formato de lo que hay en disco de forma que no se
pueda saltar desde cualquier versión anterior, se publica con
`minimumSupportedVersion`. Quien esté por debajo recibe un mensaje que le dice
que descargue el instalador en lugar de una actualización que le dejaría a
medias.

## 14. Dónde está cada cosa

```
.github/workflows/release.yml      El workflow de publicación
.github/workflows/site.yml         El de la web y las capturas
web/                               La web de documentación
CHANGELOG.md                       Las notas, escritas a mano
release.yaml                       Cuánto sube la próxima: grande, mediana o pequeña
packaging/
├── publish.py                     Publicar desde el terminal, preguntando
├── release.py                     Versión, plan, notas, checksums, manifiesto
├── web.py                         El bloque de descargas de la web
├── test_release.py, test_publish.py  Sus tests
├── macos/{package,sign,notarize}.sh
├── windows/didacta.iss
└── linux/{package.sh,didacta.desktop,didacta-*.png}
app/lib/
├── model/app_version.dart         Comparación semántica
├── model/update_manifest.dart     El manifiesto y la elección de artefacto
├── data/app_info.dart             Qué versión, qué sistema, qué arquitectura
├── data/release_channel.dart      La API de GitHub (sin dart:io)
├── data/update_installer*.dart    La instalación por sistema
├── state/update_service.dart      La máquina de estados
└── ui/update_section.dart         Ajustes, el diálogo y la franja
```
