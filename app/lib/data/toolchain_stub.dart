/// En el navegador no hay herramientas que comprobar.
///
/// Y no es una limitación que haya que sortear: la copia web no compila
/// --no hay LaTeX ni forma de lanzar un proceso-- así que una pantalla que
/// preguntara por git y por Python estaría preguntando por cosas que no
/// harían falta aunque estuvieran. Lo que hace la interfaz es no enseñar la
/// sección, igual que no enseña la de compilar.
library;

import '../model/toolchain.dart';
import 'toolchain.dart';

bool get supported => false;

Toolchain makeToolchain({String? texPath, String? enginePath}) =>
    const _NoToolchain();

class _NoToolchain implements Toolchain {
  const _NoToolchain();

  @override
  Host get host => Host.linux;

  @override
  Future<ToolState> inspect(ToolId id) async => ToolState(
    tool: toolById(id),
    problem: 'En el navegador no hay nada que comprobar.',
  );

  @override
  Future<List<ToolState>> inspectAll() async => [
    for (final tool in didactaTools) await inspect(tool.id),
  ];

  @override
  Future<InstallPlan> choose(List<InstallPlan> candidates) async =>
      candidates.last;

  @override
  Future<void> install(
    InstallPlan plan, {
    void Function(String line)? onOutput,
  }) async => throw const ToolInstallException(
    'En el navegador no se puede instalar nada.',
  );
}
