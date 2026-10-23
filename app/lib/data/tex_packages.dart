/// Instalar el paquete de LaTeX que le falta a una compilación.
///
/// Con el gestor de la distribución con la que se compila --`tlmgr` en TeX
/// Live, MacTeX y TinyTeX; el de MiKTeX en Windows--, nunca con uno propio:
/// ver `model/tex_packages.dart`, que explica por qué y guarda la parte que
/// no lanza procesos.
///
/// **Solo en escritorio**, como compilar: en el navegador no hay ni TeX ni
/// procesos, y la interfaz no ofrece el botón.
library;

import '../model/tex_packages.dart';
import 'tex_packages_stub.dart'
    if (dart.library.io) 'tex_packages_io.dart'
    as platform;

abstract class TexPackages {
  /// La de esta plataforma. [texPath] es la carpeta de TeX de Ajustes, si
  /// se ha elegido una: el paquete se instala en la distribución con la que
  /// se compila, no en la primera que aparezca.
  factory TexPackages({String? texPath}) =>
      platform.makeTexPackages(texPath: texPath);

  static bool get supported => platform.supported;

  /// Qué gestor hay, y si instalar con él pide ser administrador. Nunca
  /// lanza: no encontrar ninguno es una respuesta ([TexPackageManager.none]).
  Future<TexPackageManager> manager();

  /// Dónde está [file] según `kpsewhich`, si la distribución ya lo tiene.
  ///
  /// Se pregunta antes de instalar: si ya está, instalarlo otra vez no
  /// arregla nada, y lo que pasa es otra cosa --se compila con otro TeX, o la
  /// base de ficheros no está al día--.
  Future<String?> locate(String file);

  /// El paquete que trae [file]. Null si el gestor no conoce ninguno. Lanza
  /// [TexPackageException] si no se ha podido preguntar (sin red, por
  /// ejemplo).
  Future<String?> packageFor(
    String file,
    TexPackageManager manager, {
    void Function(String line)? onOutput,
  });

  /// Instala [package] con [manager], contando por [onOutput] lo que va
  /// diciendo. Si hace falta ser administrador, la contraseña la pide el
  /// sistema en su ventana. Lanza [TexPackageException] con el detalle y los
  /// pasos para hacerlo a mano.
  Future<void> install(
    String package,
    TexPackageManager manager, {
    void Function(String line)? onOutput,
  });
}
