/// Cómo se lanza un programa en cada sistema: el motor y el visor de PDF.
///
/// Sin `dart:io`, a propósito. Lo que cambia de un sistema a otro es **la
/// decisión** --qué ejecutable, con qué argumentos delante-- y esa decisión se
/// puede probar para los tres desde una sola máquina. Lanzar el proceso es lo
/// fácil; equivocarse de proceso en un sistema que no se tiene delante es lo
/// que pasó.
///
/// Pasó así: la aplicación lanzaba `cli/didacta` directamente. En macOS y en
/// Linux eso funciona --el script lleva un *shebang* y el sistema busca Python
/// solo--, y en Windows no ha funcionado nunca: `CreateProcess` no sabe qué
/// hacer con un fichero sin extensión y contesta «no es una aplicación Win32
/// válida». Compilar desde la aplicación estaba roto allí desde el primer día,
/// y nada lo decía porque nadie la había abierto en Windows.
library;

import 'toolchain.dart' show Host;

/// Un programa y los argumentos que van delante de los de siempre.
class LaunchCommand {
  const LaunchCommand(this.executable, [this.arguments = const []]);

  final String executable;

  /// Los que van **antes** de los que pida quien llama: el script, en
  /// Windows, o el `-3` del lanzador `py`.
  final List<String> arguments;

  /// La lista entera, con [more] detrás.
  List<String> then(List<String> more) => [...arguments, ...more];

  @override
  String toString() => [executable, ...arguments].join(' ');
}

/// Cómo se lanza el motor en [host].
///
/// En macOS y Linux, el script tal cual: su primera línea dice que es Python,
/// y es el sistema quien lo resuelve.
///
/// En Windows hay que decir el intérprete, y el orden en que se busca no es
/// indiferente:
///
/// 1. **`py`**, el lanzador que instala python.org. Es el único nombre que en
///    Windows significa «Python 3» sin ambigüedad, y con `-3` elige la última
///    versión 3 instalada aunque haya varias;
/// 2. **`python`**, que es como se llama si se instaló de otra manera --con
///    winget, con conda, a mano--;
/// 3. **`python3`**, que en Windows casi nunca existe, pero no cuesta mirar.
///
/// Y una trampa que conviene conocer: en un Windows recién instalado,
/// `python.exe` **existe** aunque no haya ningún Python. Es un alias que abre
/// la Microsoft Store (`%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe`), y
/// ejecutarlo no compila nada: abre una tienda. [find] devuelve rutas, y las
/// que caen ahí no cuentan como un Python.
///
/// `null` si no hay ningún intérprete: quien llama lo dice, con el enlace para
/// instalarlo, antes de que nadie pulse compilar.
LaunchCommand? engineLaunch({
  required String script,
  required Host host,
  required String? Function(String name) find,
}) {
  if (host != Host.windows) return LaunchCommand(script);

  final launcher = find('py');
  if (launcher != null && !isStoreAlias(launcher)) {
    return LaunchCommand(launcher, ['-3', script]);
  }
  for (final name in const ['python', 'python3']) {
    final found = find(name);
    if (found != null && !isStoreAlias(found)) {
      return LaunchCommand(found, [script]);
    }
  }
  return null;
}

/// Si [path] es uno de los alias de la Microsoft Store.
///
/// Son ficheros de verdad --`File.exists` dice que sí-- y están en el PATH de
/// cualquier Windows 10 u 11, así que no hay forma de distinguirlos por otra
/// cosa que por dónde viven.
bool isStoreAlias(String path) => path
    .toLowerCase()
    .replaceAll('/', r'\')
    .contains(r'\microsoft\windowsapps\');

/// Cómo se abre un fichero con su programa, o cómo se enseña en su carpeta.
///
/// | | abrir | enseñar |
/// |---|---|---|
/// | macOS | `open fichero` | `open -R fichero` |
/// | Windows | `explorer fichero` | `explorer /select,fichero` |
/// | Linux | `xdg-open fichero` | `xdg-open carpeta` |
///
/// En Windows con `explorer` y no con `cmd /c start`: `cmd` reinterpreta la
/// línea, y un PDF que se llame `Tema 1 & 2.pdf` se convierte en dos órdenes.
/// Y con las barras al revés, porque `explorer /select` no entiende una ruta
/// con barras normales --abre «Documentos» en lugar de la carpeta del
/// fichero--.
///
/// En Linux, «enseñar» abre la carpeta: no hay una orden común para abrir un
/// explorador de archivos con un fichero seleccionado, y abrir la carpeta es
/// lo que queda cuando no se puede hacer lo otro.
LaunchCommand fileLaunch({
  required String file,
  required bool reveal,
  required Host host,
}) => switch (host) {
  Host.macos => LaunchCommand('open', [if (reveal) '-R', file]),
  Host.windows => LaunchCommand('explorer', [
    reveal
        ? '/select,${file.replaceAll('/', r'\')}'
        : file.replaceAll('/', r'\'),
  ]),
  Host.linux => LaunchCommand('xdg-open', [reveal ? _folderOf(file) : file]),
};

String _folderOf(String file) {
  final cut = file.lastIndexOf('/');
  return cut <= 0 ? '.' : file.substring(0, cut);
}

/// Si el código de salida de [host] al abrir un fichero dice algo.
///
/// En Windows no: `explorer` devuelve 1 también cuando ha abierto el fichero
/// perfectamente, así que tomarlo como un fallo enseñaría un error cada vez
/// que todo ha ido bien.
bool exitCodeMeansFailure(Host host) => host != Host.windows;

/// Cómo se abre una carpeta en el explorador de archivos de [host].
///
/// Las mismas órdenes que para abrir un fichero: con una carpeta, las tres
/// abren una ventana de su explorador en ella.
LaunchCommand folderLaunch({required String folder, required Host host}) =>
    fileLaunch(file: folder, reveal: false, host: host);

/// Cómo se manda una carpeta a la Papelera en [host], de la mejor a la peor.
///
/// **Nunca un borrado definitivo.** Una carpeta de un repositorio puede tener
/// dentro trabajo que no está en GitHub, y desde la Papelera se recupera.
/// Si ninguna de estas funciona, quien llama dice que no se pudo y la
/// carpeta se queda donde estaba: borrarla del todo para cumplir sería
/// cambiar lo que se pidió por algo que no tiene vuelta atrás.
///
/// * **macOS**: `/usr/bin/trash`, que viene con el sistema desde la 14; y si
///   no está, pedírselo al Finder, que en la primera vez pregunta si se le
///   deja a Didacta controlarlo.
/// * **Windows**: la papelera de reciclaje por la API de Visual Basic, que
///   es la única forma de llegar a ella desde la línea de órdenes sin
///   instalar nada.
/// * **Linux**: `gio trash`, que tiene cualquier escritorio con GLib; si no,
///   `trash-put`.
List<LaunchCommand> trashFolderLaunches({
  required String folder,
  required Host host,
}) => switch (host) {
  Host.macos => [
    LaunchCommand('/usr/bin/trash', [folder]),
    LaunchCommand('osascript', [
      '-e',
      'tell application "Finder" to delete '
          '(POSIX file ${_appleScriptString(folder)} as alias)',
    ]),
  ],
  Host.windows => [
    LaunchCommand('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Add-Type -AssemblyName Microsoft.VisualBasic; '
          '[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('
          "${_powerShellString(folder.replaceAll('/', r'\'))}, "
          "'OnlyErrorDialogs', 'SendToRecycleBin')",
    ]),
  ],
  Host.linux => [
    LaunchCommand('gio', ['trash', folder]),
    LaunchCommand('trash-put', [folder]),
  ],
};

/// Una cadena de AppleScript: entre comillas, con las comillas y las barras
/// de dentro escapadas. Un nombre de carpeta con una comilla no puede
/// convertirse en otra orden.
String _appleScriptString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// Una cadena de PowerShell entre comillas simples, que no interpretan nada
/// salvo otra comilla simple, que se dobla.
String _powerShellString(String value) => "'${value.replaceAll("'", "''")}'";
