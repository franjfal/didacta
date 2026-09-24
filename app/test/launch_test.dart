/// Cómo se lanzan el motor y el visor en cada sistema.
///
/// Estas pruebas existen porque lanzar el motor estuvo roto en Windows desde
/// el primer día sin que nada lo dijera: la aplicación ejecutaba `cli/didacta`
/// directamente, que en macOS y en Linux funciona por su *shebang* y en
/// Windows contesta «no es una aplicación Win32 válida». Nadie la había abierto
/// allí.
///
/// Lo que cambia de un sistema a otro es la **decisión** --qué ejecutable, con
/// qué argumentos-- y la decisión se prueba aquí para los tres, desde
/// cualquier máquina. El disco no entra: se le pasa a `engineLaunch` qué
/// encontraría en cada caso.
library;

import 'package:didacta_app/model/launch.dart';
import 'package:didacta_app/model/toolchain.dart';
import 'package:flutter_test/flutter_test.dart';

const String script = r'C:\Users\ana\Didacta\didacta\cli\didacta';

/// Un disco de mentira: qué ruta devuelve cada nombre.
String? Function(String) disk(Map<String, String> found) =>
    (name) => found[name];

void main() {
  group('el motor', () {
    test('en macOS y en Linux, el script tal cual', () {
      for (final host in [Host.macos, Host.linux]) {
        final command = engineLaunch(
          script: '/home/ana/didacta/cli/didacta',
          host: host,
          find: disk({}),
        );
        expect(command!.executable, '/home/ana/didacta/cli/didacta');
        expect(command.arguments, isEmpty);
      }
    });

    test('en Windows, con el lanzador `py` delante si está', () {
      final command = engineLaunch(
        script: script,
        host: Host.windows,
        find: disk({
          'py': r'C:\Windows\py.exe',
          'python': r'C:\Python312\python.exe',
        }),
      );
      expect(command!.executable, r'C:\Windows\py.exe');
      // `-3` antes del script: con varias versiones instaladas, la última 3.
      expect(command.then(['build', 'tema-1']), [
        '-3',
        script,
        'build',
        'tema-1',
      ]);
    });

    test('sin `py`, con `python`', () {
      final command = engineLaunch(
        script: script,
        host: Host.windows,
        find: disk({
          'python':
              r'C:\Users\ana\AppData\Local\Programs\Python\'
              r'Python312\python.exe',
        }),
      );
      expect(command!.executable, endsWith(r'Python312\python.exe'));
      expect(command.arguments, [script]);
    });

    test('el alias de la Microsoft Store no es un Python', () {
      // Está en el PATH de cualquier Windows recién instalado y existe como
      // fichero; ejecutarlo abre una tienda. Si es lo único que hay, no hay
      // ningún Python, y hay que decirlo en lugar de lanzarlo.
      final command = engineLaunch(
        script: script,
        host: Host.windows,
        find: disk({
          'python':
              r'C:\Users\ana\AppData\Local\Microsoft\WindowsApps'
              r'\python.exe',
        }),
      );
      expect(command, isNull);
    });

    test('y si hay alias y un Python de verdad, se queda con el de verdad', () {
      final command = engineLaunch(
        script: script,
        host: Host.windows,
        find: disk({
          'python':
              r'C:\Users\ana\AppData\Local\Microsoft\WindowsApps'
              r'\python.exe',
          'python3': r'C:\tools\python3.exe',
        }),
      );
      expect(command!.executable, r'C:\tools\python3.exe');
    });

    test('sin ningún Python en Windows, null: se dice, no se lanza', () {
      expect(
        engineLaunch(script: script, host: Host.windows, find: disk({})),
        isNull,
      );
    });

    test('el alias se reconoce con cualquier barra y cualquier mayúscula', () {
      expect(
        isStoreAlias('C:/Users/x/AppData/Local/Microsoft/WindowsApps/py.exe'),
        isTrue,
      );
      expect(
        isStoreAlias(r'c:\users\x\appdata\local\MICROSOFT\WINDOWSAPPS\x.exe'),
        isTrue,
      );
      expect(isStoreAlias(r'C:\Windows\py.exe'), isFalse);
    });
  });

  group('abrir un PDF', () {
    const pdf = '/Users/ana/Didacta/build/tema-1-slides-es.pdf';

    test('en macOS, `open` y `open -R`', () {
      final open = fileLaunch(file: pdf, reveal: false, host: Host.macos);
      final show = fileLaunch(file: pdf, reveal: true, host: Host.macos);
      expect([open.executable, ...open.arguments], ['open', pdf]);
      expect([show.executable, ...show.arguments], ['open', '-R', pdf]);
    });

    test('en Windows, con `explorer` y las barras al revés', () {
      // `explorer /select` con barras normales abre «Documentos» en lugar de
      // la carpeta del fichero; y `cmd /c start` rompería un nombre con `&`.
      const windowsPdf = 'C:/Users/ana/Didacta/build/Tema 1 & 2.pdf';
      final open = fileLaunch(
        file: windowsPdf,
        reveal: false,
        host: Host.windows,
      );
      final show = fileLaunch(
        file: windowsPdf,
        reveal: true,
        host: Host.windows,
      );
      expect(open.executable, 'explorer');
      expect(open.arguments, [r'C:\Users\ana\Didacta\build\Tema 1 & 2.pdf']);
      expect(show.arguments, [
        r'/select,C:\Users\ana\Didacta\build\Tema 1 & 2.pdf',
      ]);
    });

    test('en Linux, `xdg-open`; y enseñar abre la carpeta', () {
      final open = fileLaunch(file: pdf, reveal: false, host: Host.linux);
      final show = fileLaunch(file: pdf, reveal: true, host: Host.linux);
      expect([open.executable, ...open.arguments], ['xdg-open', pdf]);
      expect(show.arguments, ['/Users/ana/Didacta/build']);
    });

    test('en Windows, el código de salida de explorer no cuenta', () {
      // Devuelve 1 también cuando ha abierto el fichero perfectamente.
      expect(exitCodeMeansFailure(Host.windows), isFalse);
      expect(exitCodeMeansFailure(Host.macos), isTrue);
      expect(exitCodeMeansFailure(Host.linux), isTrue);
    });
  });
}
