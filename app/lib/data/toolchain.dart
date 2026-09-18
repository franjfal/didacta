/// Comprobar qué hay instalado, e instalar lo que falte.
///
/// La pregunta que responde es la primera que se hace en una máquina nueva:
/// «¿esto va a funcionar?». Y la respuesta que da no es sí o no, sino **qué
/// hay, dónde está y qué versión**, que es lo único con lo que se puede hacer
/// algo cuando la respuesta es que no.
///
/// Dos cosas que este fichero hace y parecen una sola:
///
/// **Buscar no es preguntar al PATH.** Una aplicación de escritorio no hereda
/// el PATH del terminal --launchd le da cuatro directorios-- así que `which`
/// contesta que no hay nada con la máquina llena de cosas. Se busca a mano en
/// los sitios de siempre, igual que ya hace [Compiler.findTool] para TeX, y
/// **se enseña dónde se ha mirado**: cuando algo está instalado y no aparece,
/// esa lista es la única pista que sirve.
///
/// **Instalar puede terminar fuera de aquí.** El instalador de Apple, el de
/// MacTeX y el de MiKTeX se abren en su ventana y Didacta no se entera de
/// cuándo acaban. En lugar de fingir una barra de progreso que no sabe nada,
/// el plan lo dice --`handsOver`-- y la interfaz pide volver a comprobar.
library;

import '../model/toolchain.dart';
import 'toolchain_stub.dart'
    if (dart.library.io) 'toolchain_io.dart'
    as platform;

/// Lo que se sabe de una herramienta después de buscarla.
class ToolState {
  const ToolState({
    required this.tool,
    this.path,
    this.version,
    this.problem,
    this.searched = const [],
  });

  final Tool tool;

  /// Dónde ha aparecido. Null si no está.
  final String? path;

  /// Lo que contestó al preguntarle la versión, ya recortado a una línea.
  ///
  /// Null si está el fichero pero no arranca, que es un estado real y peor
  /// que faltar: `latexindent` en MacTeX es justo eso, y por eso se
  /// distingue de [path] en lugar de resumirlo todo en un booleano.
  final String? version;

  /// Por qué lo que se ha encontrado no vale.
  final String? problem;

  /// Los directorios donde se ha mirado, para poder decirlo.
  final List<String> searched;

  bool get ready => path != null && problem == null;
}

/// Un intento de instalación que no salió.
///
/// Lleva el plan dentro porque el modal que lo enseña necesita las dos cosas
/// --qué se intentó y qué hacer ahora-- y sacarlas de sitios distintos es
/// cómo se acaba enseñando un error sin salida.
class ToolInstallException implements Exception {
  const ToolInstallException(this.message, {this.detail, this.plan});

  final String message;

  /// Lo que escribió el proceso. Va en el modal, en monoespaciada.
  final String? detail;

  final InstallPlan? plan;

  @override
  String toString() => message;
}

/// Lo que se puede hacer con las herramientas en este sistema.
abstract class Toolchain {
  /// La de esta plataforma.
  ///
  /// [texPath] es el directorio de TeX configurado a mano, cuando lo hay, y
  /// [enginePath] dónde está el motor: son las dos cosas que la sesión sabe y
  /// esto no puede adivinar.
  factory Toolchain({String? texPath, String? enginePath}) =>
      platform.makeToolchain(texPath: texPath, enginePath: enginePath);

  /// Si aquí hay algo que comprobar. Falso en el navegador, donde no hay ni
  /// procesos que lanzar ni nada que instalar.
  static bool get supported => platform.supported;

  /// Sobre qué sistema se está decidiendo.
  Host get host;

  /// Busca una herramienta y cuenta qué ha encontrado.
  ///
  /// Nunca lanza: no encontrar algo **es** la respuesta, y una excepción
  /// dejaría la lista a medias por la primera que faltara.
  Future<ToolState> inspect(ToolId id);

  /// Las cuatro, a la vez.
  Future<List<ToolState>> inspectAll();

  /// El plan que se puede intentar aquí: el primero cuyo requisito esté.
  ///
  /// Nunca devuelve null --el último candidato de cada lista no depende de
  /// nada-- para que la interfaz no tenga que dibujar el caso de «no hay ni
  /// plan», que sería una fila sin botón y sin explicación.
  Future<InstallPlan> choose(List<InstallPlan> candidates);

  /// Ejecuta el plan, contando por [onOutput] lo que va pasando.
  ///
  /// Lanza [ToolInstallException] cuando no sale. Con el detalle dentro: un
  /// «no se pudo instalar» sin la salida del proceso no se puede ni buscar
  /// en internet.
  Future<void> install(
    InstallPlan plan, {
    void Function(String line)? onOutput,
  });
}
