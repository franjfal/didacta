/// Lo que hay que saber para instalar un paquete de LaTeX que falta.
///
/// La pregunta llega de una compilación que ha fallado con «File
/// `tcolorbox.sty' not found»: el motor lo reconoce y dice qué **fichero**
/// falta (`CompileDiagnostic.needs`). De ahí a instalarlo hay dos pasos, y
/// los dos los da el gestor de la distribución que haya en la máquina, no
/// Didacta:
///
/// 1. **Qué paquete trae ese fichero.** En TeX Live lo sabe `tlmgr search
///    --global --file`, que pregunta al repositorio de CTAN; en MiKTeX el
///    paquete se llama casi siempre como el fichero.
/// 2. **Instalarlo**, con `tlmgr install` o con el `mpm` de MiKTeX.
///
/// No hay un gestor propio. Los oficiales ya saben de qué espejo bajar, qué
/// dependencias tiene cada paquete y dónde dejarlo para que la distribución lo
/// encuentre; uno propio sería una segunda copia del árbol de TeX que nadie
/// actualiza, y justo lo que se quería evitar: instalaciones duplicadas.
///
/// Este fichero es la parte que no lanza nada --leer la salida de `tlmgr`,
/// decidir qué se le dice a quien no puede instalar desde aquí-- para poder
/// probarla sin red y sin TeX.
library;

import '../l10n/tr.dart';
import 'toolchain.dart' show Host;

/// Con qué se instalan paquetes en esta máquina.
enum TexManagerKind {
  /// `tlmgr`, de TeX Live, MacTeX, BasicTeX o TinyTeX.
  tlmgr,

  /// El `mpm` de MiKTeX (o su sucesor, `miktex packages`).
  miktex,

  /// El TeX de la distribución de Linux: `tlmgr` está, pero los paquetes los
  /// pone `apt` o `dnf`, y tocar el árbol por debajo lo rompe.
  system,

  /// No se ha encontrado ningún gestor.
  none,
}

/// El gestor de paquetes de la distribución de TeX con la que se compila.
class TexPackageManager {
  const TexPackageManager({
    required this.kind,
    this.program,
    this.root,
    this.needsAdmin = false,
    this.distribution,
  });

  static const TexPackageManager none = TexPackageManager(
    kind: TexManagerKind.none,
  );

  final TexManagerKind kind;

  /// La ruta entera de `tlmgr`, `mpm` o `miktex`.
  final String? program;

  /// La raíz de la distribución (`TEXMFROOT`): `/usr/local/texlive/2026`.
  final String? root;

  /// Si escribir en [root] pide ser administrador: MacTeX instala como
  /// `root`, y un TeX Live de Linux en `/usr/local` también. Entonces la
  /// instalación pide la contraseña al sistema --nunca a Didacta--.
  final bool needsAdmin;

  /// Cómo se llama, para leerlo: «TeX Live 2026», «MiKTeX».
  final String? distribution;

  bool get canInstall =>
      kind == TexManagerKind.tlmgr || kind == TexManagerKind.miktex;

  /// El nombre del gestor, para los mensajes.
  String get label => switch (kind) {
    TexManagerKind.tlmgr => 'tlmgr',
    TexManagerKind.miktex => tr('el gestor de paquetes de MiKTeX'),
    TexManagerKind.system => tr('el gestor de paquetes del sistema'),
    TexManagerKind.none => tr('ningún gestor de paquetes'),
  };
}

/// Por qué no se ha podido instalar, con lo que se puede hacer a mano.
class TexPackageException implements Exception {
  const TexPackageException(
    this.message, {
    this.detail = '',
    this.manual = const [],
  });

  final String message;

  /// Lo que dijo el gestor, tal cual.
  final String detail;

  /// Pasos para hacerlo a mano: órdenes que se pueden copiar.
  final List<String> manual;

  @override
  String toString() => message;
}

/// Un nombre de paquete o de fichero que se puede pasar a una orden sin
/// comillas: letras, números y `._+-`. Lo que llega del log de LaTeX no se
/// pasa a un proceso, y menos a uno con permisos de administrador, sin
/// mirarlo antes.
bool isSafePackageName(String name) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(name);

/// El paquete de TeX Live que trae [file], leído de lo que contesta `tlmgr
/// search --global --file /fichero`.
///
/// La salida es un paquete por línea, terminado en `:`, y debajo sus
/// ficheros con un tabulador delante:
///
/// ```
/// tlmgr: package repository https://… (verified)
/// tcolorbox:
/// 	texmf-dist/tex/latex/tcolorbox/tcolorbox.sty
/// ```
///
/// La búsqueda es por subcadena, así que se queda con el primero que tiene un
/// fichero que se llama **exactamente** así. Null si ninguno.
String? packageFromTlmgrSearch(String output, String file) {
  final wanted = '/${file.toLowerCase()}';
  String? current;
  for (final raw in output.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    if (!raw.startsWith('\t') && !raw.startsWith(' ')) {
      final match = RegExp(r'^([A-Za-z0-9._+-]+):$').firstMatch(line);
      current = match?.group(1);
      continue;
    }
    if (current == null) continue;
    if (line.trim().toLowerCase().endsWith(wanted)) return current;
  }
  return null;
}

/// El paquete de MiKTeX para [file]: el nombre del fichero sin extensión.
///
/// Es la regla con la que MiKTeX nombra casi todos (`tcolorbox.sty` está en
/// `tcolorbox`), y no hay una orden que lo pregunte por fichero. Si no
/// acierta, la instalación lo dice y se manda a la Consola de MiKTeX, que sí
/// busca por fichero. Las fuentes (`.tfm`) no siguen la regla: null.
String? miktexPackageFor(String file) {
  final dot = file.lastIndexOf('.');
  if (dot <= 0) return null;
  if (file.substring(dot).toLowerCase() == '.tfm') return null;
  return file.substring(0, dot);
}

/// Lo que se dice cuando `tlmgr` falla por algo que tiene arreglo conocido.
///
/// Los dos de siempre: un TeX Live de un año que ya cerró --el repositorio
/// es del año siguiente y `tlmgr` se niega-- y un `tlmgr` que pide
/// actualizarse antes de instalar nada.
String? explainTlmgrFailure(String output) {
  final lower = output.toLowerCase();
  if (lower.contains('is older than remote repository') ||
      lower.contains('cross release updates are only supported')) {
    return tr(
      'Tu TeX Live es de un año que ya ha cerrado y tlmgr no instala '
      'paquetes del repositorio nuevo. Hay que actualizar TeX Live a la '
      'versión de este año (o instalar el paquete desde el archivo histórico '
      'de tu año).',
    );
  }
  if (lower.contains('tlmgr itself needs to be updated')) {
    return tr(
      'tlmgr pide actualizarse antes de instalar nada. Ejecuta '
      '«tlmgr update --self» y vuelve a probar.',
    );
  }
  if (lower.contains('permission denied') ||
      lower.contains('not writable') ||
      lower.contains('cannot be written')) {
    return tr(
      'No hay permiso para escribir en la carpeta de TeX. Hay que instalarlo '
      'como administrador.',
    );
  }
  if (lower.contains('cannot contact') ||
      lower.contains('unable to download') ||
      lower.contains('could not resolve') ||
      lower.contains('connection')) {
    return tr(
      'No se ha podido llegar al repositorio de CTAN. Comprueba la conexión '
      'a internet.',
    );
  }
  return null;
}

/// Cómo instalar [file] a mano, con las órdenes de esta máquina.
///
/// Lo que se enseña cuando no se puede desde aquí: sin gestor, con el TeX de
/// la distribución de Linux, o cuando el gestor ha fallado. [package] es el
/// paquete si ya se sabe.
List<String> manualInstallSteps({
  required TexPackageManager manager,
  required Host host,
  required String file,
  String? package,
}) {
  final name = package ?? miktexPackageFor(file) ?? file;
  switch (manager.kind) {
    case TexManagerKind.tlmgr:
      final tlmgr = manager.program ?? 'tlmgr';
      final search = package == null
          ? ['$tlmgr search --global --file /$file']
          : const <String>[];
      return switch (host) {
        Host.windows => [
          ...search,
          tr('En una consola como administrador: {0}', [
            '$tlmgr install $name',
          ]),
        ],
        _ => [
          ...search,
          manager.needsAdmin
              ? tr('En el Terminal: {0}', ['sudo $tlmgr install $name'])
              : tr('En el Terminal: {0}', ['$tlmgr install $name']),
        ],
      };
    case TexManagerKind.miktex:
      return [
        tr(
          'Abre la Consola de MiKTeX → Paquetes, busca «{0}» e instala el '
          'paquete que lo contiene.',
          [file],
        ),
        tr(
          'O deja que MiKTeX lo haga solo: Consola de MiKTeX → Ajustes → '
          '«Instalar los paquetes que falten: Siempre».',
        ),
      ];
    case TexManagerKind.system:
      return [
        tr(
          'Debian o Ubuntu: apt-file search {0}, y luego sudo apt install '
          'con el paquete que diga (texlive-latex-extra, texlive-science…)',
          [file],
        ),
        tr('Fedora: sudo dnf install \'tex({0})\'', [file]),
        tr('Arch: sudo pacman -S texlive-latexextra'),
      ];
    case TexManagerKind.none:
      return [
        tr(
          'No he encontrado tlmgr ni MiKTeX. Instala LaTeX desde Ajustes → '
          'Herramientas, o añade el paquete con el gestor de tu distribución.',
        ),
      ];
  }
}

/// La raíz de una distribución que pertenece al sistema y no a TeX Live: la
/// de Debian, Ubuntu o Fedora, bajo `/usr/share`. Ahí `tlmgr` no instala
/// (Debian lo deja solo en «modo usuario») y los paquetes van con `apt`.
bool isSystemTexRoot(String? root) {
  if (root == null) return false;
  final path = root.replaceAll('\\', '/');
  return path.startsWith('/usr/share/') || path == '/usr/share/texlive';
}
