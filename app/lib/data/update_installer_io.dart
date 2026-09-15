/// La instalación de verdad, en un sistema con ficheros y procesos.
///
/// Tres sistemas y tres mecanismos, porque las tres formas de instalar una
/// aplicación son distintas y fingir que son la misma es cómo se rompe una
/// instalación:
///
/// **macOS.** Se descarga un ZIP con el `.app` --no el DMG-- y lo sustituye un
/// script que espera a que Didacta cierre. El DMG es para instalar a mano la
/// primera vez; montarlo, copiar y desmontarlo desde el propio programa que se
/// está reemplazando añade tres formas de fallar sin ganar nada. Es lo que
/// hace Sparkle, por lo mismo.
///
/// **Windows.** Se descarga el instalador y se ejecuta en silencio. Un
/// instalador de verdad ya sabe sustituir ficheros en uso, escribir el menú
/// de inicio y dejar la desinstalación registrada; reimplementar eso con un
/// `.cmd` sería hacer peor lo que Inno Setup hace bien. Se instala **en la
/// carpeta del usuario**, así que no pide administrador.
///
/// **Linux.** Se sustituye el propio AppImage, que es un solo fichero, con un
/// `mv` --que en el mismo sistema de ficheros es atómico-- y se relanza. Si
/// Didacta no viene de un AppImage, no se toca nada: allí manda el gestor de
/// paquetes, y escribirle los ficheros por debajo le rompe la base de datos.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../model/update_manifest.dart';
import 'release_channel.dart';
import 'update_installer.dart';

UpdateInstaller createInstaller() {
  if (Platform.isMacOS) return _MacInstaller();
  if (Platform.isWindows) return _WindowsInstaller();
  if (Platform.isLinux) return _LinuxInstaller();
  return _Unsupported(
    'Didacta solo se actualiza sola en macOS, Windows y Linux.',
  );
}

/// Recoge el digest que `sha256.startChunkedConversion` va soltando.
///
/// Escrito aquí en vez de traer `package:convert` por un `AccumulatorSink`:
/// son seis líneas y una dependencia menos que mantener.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Lo común: descargar comprobando, y preparar un script que espera.
abstract class _DesktopInstaller implements UpdateInstaller {
  /// El script que hará la sustitución, una vez escrito.
  String? _prepared;

  @override
  bool get supported => unsupportedReason == null;

  @override
  Future<DownloadedUpdate> download({
    required ReleaseChannel channel,
    required UpdateAsset asset,
    required UpdateManifest manifest,
    void Function(DownloadProgress)? onProgress,
    Future<void>? cancelled,
  }) async {
    final staging = await _stagingDirectory(manifest);
    final file = File('${staging.path}${Platform.pathSeparator}${asset.name}');

    var stopped = false;
    unawaited(cancelled?.then((_) => stopped = true));

    final response = await channel.open(asset);
    // Lo que diga el servidor, y si no lo dice, lo que diga el manifiesto.
    final total = response.contentLength ?? asset.size;

    final digests = _DigestSink();
    final hasher = sha256.startChunkedConversion(digests);
    final out = file.openWrite();
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        if (stopped) {
          throw const UpdateException(
            UpdateProblem.cancelled,
            'Descarga cancelada.',
          );
        }
        out.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received: received, total: total));
      }
      await out.flush();
      await out.close();
    } catch (thrown) {
      // Cerrar antes de borrar: en Windows no se borra un fichero abierto.
      try {
        await out.close();
      } catch (_) {}
      await _quietlyDelete(staging);
      if (thrown is UpdateException) rethrow;
      throw _mapWriteFailure(thrown);
    }

    hasher.close();
    final digest = digests.value?.toString() ?? '';

    // Y aquí está la única puerta que hay. Un fichero que no cuadra no se
    // guarda: dejarlo en el disco sería dejar un binario sin verificar al
    // alcance de cualquier cosa que lo ejecute.
    if (digest != asset.sha256) {
      await _quietlyDelete(staging);
      throw UpdateException(
        UpdateProblem.checksumMismatch,
        'La descarga no coincide con lo que anunciaba el release, así que no '
        'se va a instalar. Vuelve a intentarlo; si sigue pasando, avisa a '
        'quien publica Didacta.',
        detail: 'esperado ${asset.sha256}, obtenido $digest',
      );
    }

    // Y el tamaño, que además es lo que detecta una descarga cortada que por
    // casualidad hubiera dado el mismo principio.
    if (asset.size > 0 && received != asset.size) {
      await _quietlyDelete(staging);
      throw UpdateException(
        UpdateProblem.downloadInterrupted,
        'La descarga se quedó a medias.',
        detail: 'esperados ${asset.size} bytes, recibidos $received',
      );
    }

    return DownloadedUpdate(path: file.path, asset: asset, manifest: manifest);
  }

  @override
  Never applyAndExit() {
    final script = _prepared;
    if (script == null) {
      throw const UpdateException(
        UpdateProblem.installFailed,
        'No hay ninguna actualización preparada.',
      );
    }
    // Desligado del proceso: en cuanto Didacta termine, el script tiene que
    // seguir vivo. Es toda la razón por la que la sustitución la hace otro.
    Process.start(
      _runner.first,
      [..._runner.skip(1), script],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    // `exit` y no `SystemNavigator.pop()`: hay que cerrar de verdad y ya, que
    // es lo que el script está esperando.
    exit(0);
  }

  /// Con qué se ejecuta el script: `/bin/sh` o `cmd.exe`.
  List<String> get _runner;

  @override
  Future<void> discard(DownloadedUpdate update) async {
    _prepared = null;
    await _quietlyDelete(File(update.path).parent);
  }

  Future<Directory> _stagingDirectory(UpdateManifest manifest) async {
    final Directory base;
    try {
      base = await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp.createTempSync('didacta-update-');
    }
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}didacta-update-${manifest.version}',
    );
    // Recreada: si quedó algo de un intento anterior, mezclarlo con esto es
    // exactamente cómo se instala media versión vieja.
    if (dir.existsSync()) await _quietlyDelete(dir);
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _quietlyDelete(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } catch (_) {
      // Un temporal que no se deja borrar no es motivo para fallar nada.
    }
  }

  UpdateException _mapWriteFailure(Object thrown) {
    if (thrown is FileSystemException) {
      final code = thrown.osError?.errorCode;
      final message = thrown.osError?.message.toLowerCase() ?? '';
      // 28 es ENOSPC en POSIX; 112 es ERROR_DISK_FULL en Windows.
      if (code == 28 ||
          code == 112 ||
          message.contains('no space') ||
          message.contains('espacio')) {
        return const UpdateException(
          UpdateProblem.noSpace,
          'No hay espacio suficiente en el disco para descargar la '
          'actualización.',
        );
      }
      if (code == 13 || code == 5 || message.contains('permission')) {
        return const UpdateException(
          UpdateProblem.noPermission,
          'No hay permiso para escribir la descarga.',
        );
      }
    }
    return UpdateException(
      UpdateProblem.downloadInterrupted,
      'Se cortó la descarga.',
      detail: '$thrown',
    );
  }

  /// Escribe el script y lo deja listo para [applyAndExit].
  Future<String> _writeScript(
    String directory,
    String name,
    String body,
  ) async {
    final file = File('$directory${Platform.pathSeparator}$name');
    await file.writeAsString(body, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', file.path]);
    }
    _prepared = file.path;
    return file.path;
  }

  /// Un valor dentro de comillas simples de shell, a prueba de rutas raras.
  static String sh(String value) => "'${value.replaceAll("'", r"'\''")}'";
}

class _Unsupported extends _DesktopInstaller {
  _Unsupported(this.reason);

  final String reason;

  @override
  String? get unsupportedReason => reason;

  @override
  List<String> get _runner => const ['/bin/sh'];

  @override
  Future<void> stage(DownloadedUpdate update) async =>
      throw UpdateException(UpdateProblem.installFailed, reason);
}

// ---------------------------------------------------------------- macOS ----

class _MacInstaller extends _DesktopInstaller {
  /// La carpeta `.app` que se está ejecutando.
  ///
  /// `Platform.resolvedExecutable` es
  /// `…/Didacta.app/Contents/MacOS/Didacta`, así que el bundle son tres
  /// niveles hacia arriba.
  static String? bundlePath() {
    var dir = File(Platform.resolvedExecutable).parent; // MacOS
    for (var i = 0; i < 2; i++) {
      dir = dir.parent; // Contents, luego el .app
    }
    return dir.path.endsWith('.app') ? dir.path : null;
  }

  @override
  String? get unsupportedReason => bundlePath() == null
      ? 'Didacta no se está ejecutando desde un paquete .app, así que no '
            'puede sustituirse a sí misma. Descarga el DMG e instálala.'
      : null;

  @override
  List<String> get _runner => const ['/bin/sh'];

  @override
  Future<void> stage(DownloadedUpdate update) async {
    final target = bundlePath();
    if (target == null) {
      throw UpdateException(UpdateProblem.installFailed, unsupportedReason!);
    }

    final staging = File(update.path).parent.path;
    final extracted = '$staging/extracted';
    await Directory(extracted).create(recursive: true);

    // `ditto` y no `unzip`: conserva los atributos extendidos y la firma del
    // paquete. `unzip` la rompe, y una aplicación firmada que se extrae con
    // `unzip` deja de validar.
    final unzip = await Process.run('/usr/bin/ditto', [
      '-x',
      '-k',
      update.path,
      extracted,
    ]);
    if (unzip.exitCode != 0) {
      throw UpdateException(
        UpdateProblem.brokenRelease,
        'El paquete descargado no se pudo abrir.',
        detail: '${unzip.stderr}',
      );
    }

    final newBundle = Directory(extracted)
        .listSync()
        .whereType<Directory>()
        .where((entry) => entry.path.endsWith('.app'))
        .firstOrNull;
    if (newBundle == null) {
      throw const UpdateException(
        UpdateProblem.brokenRelease,
        'El paquete descargado no contiene ninguna aplicación.',
      );
    }

    // Que dentro haya de verdad un ejecutable. Un ZIP bien formado con un
    // bundle vacío pasaría el checksum y dejaría una Didacta que no abre.
    final executable = File('${newBundle.path}/Contents/MacOS/Didacta');
    if (!executable.existsSync()) {
      throw const UpdateException(
        UpdateProblem.brokenRelease,
        'La aplicación descargada está incompleta.',
      );
    }

    await _checkSignature(newBundle.path, target);

    final script =
        '''
#!/bin/sh
# Sustituye Didacta cuando el proceso $pid termine. Lo escribe la propia
# aplicación y lo ejecuta fuera de ella: un .app no puede reemplazarse a sí
# mismo mientras corre.
set -u

TARGET=${_DesktopInstaller.sh(target)}
NEW=${_DesktopInstaller.sh(newBundle.path)}
BACKUP="\$TARGET.didacta-anterior"
STAGING=${_DesktopInstaller.sh(staging)}

# Esperar a que cierre, con tope: si no termina en 60 s, no se toca nada.
i=0
while kill -0 $pid 2>/dev/null; do
  i=\$((i + 1))
  [ \$i -gt 600 ] && exit 1
  sleep 0.1
done

rm -rf "\$BACKUP"
mv "\$TARGET" "\$BACKUP" || exit 1

if ditto "\$NEW" "\$TARGET" && [ -x "\$TARGET/Contents/MacOS/Didacta" ]; then
  rm -rf "\$BACKUP"
else
  # No se pudo: vuelve la de antes, que es la que funcionaba.
  rm -rf "\$TARGET"
  mv "\$BACKUP" "\$TARGET"
fi

open "\$TARGET"
rm -rf "\$STAGING"
''';
    await _writeScript(staging, 'instalar.sh', script);
  }

  /// Si la copia instalada está firmada, la nueva también tiene que estarlo.
  ///
  /// Sin exigir firma cuando todavía no hay certificado --hoy no lo hay-- y
  /// sin permitir el camino contrario: pasar de una Didacta firmada a una sin
  /// firmar sería usar el actualizador para rebajar la seguridad, que es
  /// justo lo que un actualizador no puede dejar hacer.
  Future<void> _checkSignature(String candidate, String installed) async {
    final current = await Process.run('/usr/bin/codesign', [
      '--verify',
      '--strict',
      installed,
    ]);
    if (current.exitCode != 0) return; // La instalada no está firmada.

    final next = await Process.run('/usr/bin/codesign', [
      '--verify',
      '--deep',
      '--strict',
      candidate,
    ]);
    if (next.exitCode != 0) {
      throw UpdateException(
        UpdateProblem.installFailed,
        'La actualización no está firmada correctamente y la versión que '
        'tienes instalada sí lo está, así que no se va a instalar.',
        detail: '${next.stderr}',
      );
    }
  }
}

// -------------------------------------------------------------- Windows ----

class _WindowsInstaller extends _DesktopInstaller {
  @override
  String? get unsupportedReason => null;

  @override
  List<String> get _runner => [
    Platform.environment['COMSPEC'] ?? r'C:\Windows\System32\cmd.exe',
    '/c',
  ];

  @override
  Future<void> stage(DownloadedUpdate update) async {
    final staging = File(update.path).parent.path;
    final executable = Platform.resolvedExecutable;

    // El instalador es un ejecutable firmado (cuando haya certificado) y ya
    // sabe sustituir ficheros en uso. Lo único que hace falta de este lado es
    // esperar a que Didacta cierre y volver a abrirla después.
    final script =
        '''
@echo off
rem Actualiza Didacta cuando el proceso $pid termine.
setlocal

set "INSTALADOR=${update.path}"
set "APP=$executable"
set "REGISTRO=$staging\\instalacion.log"

rem Esperar a que cierre, con tope de 60 s.
set /a intentos=0
:esperar
tasklist /FI "PID eq $pid" 2>nul | find "$pid" >nul
if errorlevel 1 goto instalar
set /a intentos+=1
if %intentos% GEQ 60 goto abrir
timeout /t 1 /nobreak >nul
goto esperar

:instalar
rem /SILENT: sin preguntas. Instalación por usuario, sin administrador.
"%INSTALADOR%" /SILENT /NORESTART /SUPPRESSMSGBOXES /LOG="%REGISTRO%"

:abrir
start "" "%APP%"
endlocal
''';
    await _writeScript(staging, 'instalar.cmd', script);
  }
}

// ---------------------------------------------------------------- Linux ----

class _LinuxInstaller extends _DesktopInstaller {
  /// La ruta del AppImage que se está ejecutando, si es que es uno.
  ///
  /// La pone el propio runtime de AppImage en el entorno. Si no está,
  /// Didacta se instaló de otra forma --un `.deb`, o descomprimida a mano--
  /// y sustituir ficheros por debajo del gestor de paquetes le rompería la
  /// base de datos.
  static String? appImagePath() {
    final path = Platform.environment['APPIMAGE'];
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  @override
  String? get unsupportedReason => appImagePath() == null
      ? 'Didacta no se está ejecutando desde un AppImage, así que la '
            'actualización la gobierna tu gestor de paquetes. Descarga el '
            'AppImage si quieres que se actualice sola.'
      : null;

  @override
  List<String> get _runner => const ['/bin/sh'];

  @override
  Future<void> stage(DownloadedUpdate update) async {
    final target = appImagePath();
    if (target == null) {
      throw UpdateException(UpdateProblem.installFailed, unsupportedReason!);
    }

    // Que lo descargado sea de verdad un AppImage: los cuatro primeros bytes
    // son los de un ELF, y en el byte 8 lleva la firma `AI\x02`.
    final head = await File(update.path).openRead(0, 11).first;
    if (head.length < 11 ||
        head[0] != 0x7F ||
        head[1] != 0x45 ||
        head[2] != 0x4C ||
        head[3] != 0x46) {
      throw const UpdateException(
        UpdateProblem.brokenRelease,
        'Lo descargado no es un AppImage.',
      );
    }

    final staging = File(update.path).parent.path;
    final script =
        '''
#!/bin/sh
# Sustituye el AppImage cuando el proceso $pid termine.
set -u

TARGET=${_DesktopInstaller.sh(target)}
NEW=${_DesktopInstaller.sh(update.path)}
STAGING=${_DesktopInstaller.sh(staging)}

i=0
while kill -0 $pid 2>/dev/null; do
  i=\$((i + 1))
  [ \$i -gt 600 ] && exit 1
  sleep 0.1
done

# Al lado del destino, para que el `mv` final sea un `rename` en el mismo
# sistema de ficheros: eso es lo que lo hace atómico. Un `cp` encima del
# AppImage dejaría un fichero a medias si se corta la luz.
NUEVO="\$TARGET.nuevo"
ANTERIOR="\$TARGET.anterior"

cp "\$NEW" "\$NUEVO" || exit 1
chmod +x "\$NUEVO" || exit 1
cp -p "\$TARGET" "\$ANTERIOR" 2>/dev/null

if mv -f "\$NUEVO" "\$TARGET"; then
  rm -f "\$ANTERIOR"
else
  rm -f "\$NUEVO"
  [ -f "\$ANTERIOR" ] && mv -f "\$ANTERIOR" "\$TARGET"
fi

"\$TARGET" >/dev/null 2>&1 &
rm -rf "\$STAGING"
''';
    await _writeScript(staging, 'instalar.sh', script);
  }
}
