# Distribución y actualización

Cómo llega Didacta a la máquina de alguien, y cómo se mantiene al día.

---

## 1. El problema

Didacta es una aplicación de escritorio que usa un grupo pequeño y conocido de
personas. Eso descarta las dos respuestas habituales por motivos opuestos:

- **una tienda** (App Store, Microsoft Store) es pública. Cualquiera la
  descarga, y además impone el sandbox, que esta aplicación no puede aceptar:
  trabaja sobre clones de git manejados con el `git` del sistema;
- **compilar cada uno lo suyo** es lo que había hasta ahora, y solo funciona
  mientras quien la usa es quien la escribe.

Lo que hace falta es distribución **privada**, con una lista de personas que se
pueda cambiar, y actualización automática que no dependa de que nadie se
acuerde de nada.

## 2. La idea: el permiso ya existe

GitHub ya sabe quién puede entrar en un repositorio privado. Esa lista es
exactamente la lista de quién puede usar Didacta, así que no se construye otra.

```
                  franjfal/didacta                franjfal/didacta_public
                  (privado, el código)            (privado, las versiones)
                         │                                  ▲
   «Publish Didacta      │                                  │
    Release»  ───────────┤   compila macOS/Windows/Linux    │
                         └──────────────────────────────────┘
                                   token de una GitHub App
                                   instalada SOLO allí

                                            │
                      ┌─────────────────────┼──────────────────────┐
                      ▼                     ▼                      ▼
                  descarga              descarga               descarga
                  (persona)             (persona)            (Didacta, sola)
```

Dos repositorios y no uno, por una razón: **el de las versiones no tiene el
código**. A alguien a quien se le da acceso para que pueda instalar y
actualizar no se le está dando el código fuente.

Dar acceso a alguien es añadirlo como colaborador de `didacta_public`.
Quitárselo es quitarlo de ahí. No hay ninguna otra lista que mantener, ni un
servidor de licencias, ni nada que pueda quedar desincronizado con la realidad.

## 3. La versión: una sola fuente

`app/pubspec.yaml`:

```yaml
version: 1.4.2+142
```

De ahí sale **todo**: el tag (`v1.4.2`), el nombre de los artefactos, lo que la
aplicación dice de sí misma, y lo que declara el manifiesto. Ningún otro sitio
escribe un número de versión a mano.

La aplicación no lee una constante del código sino el paquete construido
(`Info.plist` en macOS, `version.json` en Windows y Linux), vía
`package_info_plus`. Una constante puede quedarse atrás de la compilación; el
paquete que se está ejecutando, no. Está en `app/lib/data/app_info.dart`.

La comparación es **semántica**, en `app/lib/model/app_version.dart`. Existe
porque comparar como texto dice que `1.10.0 < 1.9.0`, y el síntoma de ese fallo
no es un error sino algo peor: una actualización que nunca se ofrece.

## 4. Publicar una versión

Cinco pasos, y ninguno es una orden en un terminal:

1. subir el número en `app/pubspec.yaml`;
2. escribir la sección en `CHANGELOG.md`;
3. GitHub → Actions → **Publish Didacta Release**;
4. Run workflow;
5. nada más.

El workflow (`.github/workflows/release.yml`) hace, en este orden:

| # | Trabajo | Qué hace |
|---|---|---|
| 1 | `comprobar` | Lee la versión, exige la sección del CHANGELOG, comprueba que el tag no exista ya |
| 2 | `pruebas` | Tests de Python, tests de Dart, `flutter analyze --fatal-infos`, formato |
| 3 | `construir` | macOS, Windows y Linux **en paralelo, sin `fail-fast`** |
| 4 | `publicar` | Solo si los tres salieron |

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
para saber si una versión compila en Windows sin gastar un número de versión.

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

El **README de `didacta_public`**, escrito por el workflow desde el manifiesto.

**No se usa GitHub Pages**, y es deliberado: una Page servida desde un
repositorio privado es pública salvo que la cuenta tenga GitHub Enterprise
Cloud. En una cuenta personal, activarla publicaría en internet la lista de
versiones y los enlaces de descarga. El README lo ve quien entra al
repositorio, y al repositorio entra quien tiene acceso: la misma puerta que ya
controla quién puede actualizar.

Menos bonito y correcto. La seguridad va por delante de tener una página con
estilo.

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

### La OAuth App de la gente y la credencial del CI son dos cosas

Y no se mezclan nunca:

| | Quién la usa | Para qué | Dónde vive |
|---|---|---|---|
| **OAuth App** | Las personas | Entrar, clonar, descargar | Client ID público, token en el llavero de cada uno |
| **GitHub App** | El workflow | Crear el release | Secrets de Actions |

Reutilizar la OAuth App como credencial de publicación daría a cada persona que
entra el permiso de publicar versiones.

## 9. Autorización de verdad

Poder entrar en GitHub no es poder usar Didacta. Después del login, la
aplicación pregunta:

```
GET /repos/franjfal/didacta_public
```

- **200** → tiene acceso: puede buscar, descargar e instalar;
- **404** → no lo tiene. GitHub responde 404 y no 403 a un repositorio privado
  al que no se llega, para no confirmar que existe. Aquí sabemos que existe, así
  que un 404 significa «esta cuenta no entra», y se dice tal cual.

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

**Imprescindibles:**

| Secret | Qué es |
|---|---|
| `DIDACTA_RELEASE_APP_ID` | El App ID de la GitHub App de publicación |
| `DIDACTA_RELEASE_APP_PRIVATE_KEY` | Su clave privada (el `.pem` entero) |

**Opcionales**, los de firma, en las dos tablas de arriba.

Nada más. No hay ningún token en el código, ni en ningún fichero del
repositorio, ni se escribe ninguno en un log.

### La GitHub App de publicación

Se crea una vez, en Settings → Developer settings → GitHub Apps → New:

- **Permisos:** `Contents: Read and write`. **Y nada más**;
- **Webhook:** desactivado;
- **Instalación:** solo en `didacta_public`.

El token que `actions/create-github-app-token` genera dura una hora y solo
sirve para ese repositorio. La App en sí no caduca nunca, y no está ligada a
ninguna cuenta personal: si quien la creó deja el proyecto, sigue funcionando.

Un PAT de grano fino haría lo mismo, pero caduca (máximo un año), va ligado a
una persona, y el día que caduque la publicación fallará sin previo aviso.

## 13. Operaciones

### Dar acceso a alguien

```
github.com/franjfal/didacta_public → Settings → Collaborators → Add people
```

Rol **Read**. Con eso puede descargar, y Didacta se le actualizará sola.

### Quitárselo

El mismo sitio → Remove.

Lo que pasa a partir de ahí: la siguiente comprobación devuelve 404 y Didacta
le dice que su cuenta ya no tiene acceso. **La copia que tiene instalada sigue
funcionando** --no es un DRM-- pero no recibe versiones nuevas.

Para cortar también el acceso al contenido, quitarlo además de los repositorios
de contenido. Y si hace falta invalidar su token ahora mismo, en la OAuth App →
*Revoke all user tokens*.

### Rollback

Un release publicado no se borra: se marca otro como el último.

```bash
gh release edit v1.4.1 -R franjfal/didacta_public --latest
```

A partir de ese momento `releases/latest` devuelve la 1.4.1, y quien tenga la
1.4.2 instalada **no** recibirá una oferta de bajar: la comparación es
`publicada > instalada`, así que nadie se degrada solo. Quien tenga la 1.4.0 sí
recibirá la 1.4.1.

Para que la 1.4.2 no se pueda instalar a nadie más:

```bash
gh release edit v1.4.2 -R franjfal/didacta_public --draft
```

Y después publicar una 1.4.3 con lo corregido, que es lo que arregla el
problema de verdad.

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
CHANGELOG.md                       Las notas, escritas a mano
packaging/
├── release.py                     Versión, notas, checksums, manifiesto
├── portal.py                      El README de didacta_public
├── test_release.py                Sus tests
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
