/// Lo que Didacta guardó en el disco cuando se llamaba de otra forma.
///
/// Hasta la 0.2.0 la aplicación se identificaba como `es.uv.didacta`, y en
/// Windows su editor era la Universitat de València. Los tres sistemas eligen
/// con eso la carpeta de datos de la aplicación, así que al cambiarlo por
/// `io.github.franjfal.didacta` --y el editor por quien publica Didacta-- la
/// carpeta pasó a ser otra, vacía:
///
/// | | antes | ahora |
/// |---|---|---|
/// | macOS | `Application Support/es.uv.didacta` | `…/io.github.franjfal.didacta` |
/// | Windows | `%APPDATA%\Universitat de València\Didacta` | `%APPDATA%\Javier Falcó\Didacta` |
/// | Linux | `~/.local/share/es.uv.didacta` | `~/.local/share/io.github.franjfal.didacta` |
///
/// Dentro están las plantillas guardadas en el programa, y en Windows y en
/// Linux también los ajustes; en Windows, además, el token de GitHub cifrado.
/// Sin traerlo, quien se actualizara sola se encontraría una instalación
/// nueva. En macOS los ajustes van aparte, en el dominio de preferencias, y
/// los trae `MainFlutterWindow.swift` antes de que arranque esto.
///
/// Lo único que no se puede traer es el token en Linux: allí lo guarda el
/// llavero del escritorio con el identificador en el nombre, y hay que volver
/// a entrar en GitHub una vez.
library;

import 'legacy_identity_stub.dart'
    if (dart.library.io) 'legacy_identity_io.dart'
    as platform;

/// El identificador de antes.
const String legacyBundleId = 'es.uv.didacta';

/// El editor de antes, en Windows.
const String legacyCompany = 'Universitat de València';

/// Copia a la carpeta de datos de ahora lo que hubiera en la de antes.
///
/// Una sola vez, sin pisar nada que ya esté, y sin lanzar nunca: que no se
/// pueda traer lo de antes no puede impedir que Didacta arranque.
Future<void> bringLegacyData() => platform.bringLegacyData();

/// Borra lo que quede con el nombre de antes. Es parte de «Restablecer».
Future<void> forgetLegacyData() => platform.forgetLegacyData();
