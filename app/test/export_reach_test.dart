/// Exportar con el motor de verdad: qué se reparte y qué no.
///
/// La casilla del diálogo no vale nada si la bandera no llega al motor, o si
/// llega y lo que el motor devuelve no se lee. Esto lo prueba de punta a
/// punta con un repositorio de verdad y PDF de mentira --exportar solo copia,
/// así que no hace falta TeX--: la hoja de problemas tiene la versión del
/// estudiante, la de resultados y la del profesor, y la del profesor no sale
/// salvo que se pida.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/compiler_io.dart';

/// Dónde está Didacta, subiendo desde el test.
String get enginePath => Directory.current.path.endsWith('/app')
    ? Directory.current.parent.path
    : Directory.current.path;

void main() {
  late Directory work;
  late String repository;
  late Compiler compiler;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('didacta-export-');
    repository = '${work.path}/repo';
    final copy = await Process.run('cp', [
      '-R',
      '$enginePath/examples/demo-course',
      repository,
    ]);
    expect(copy.exitCode, 0, reason: '${copy.stderr}');
    // Lo que hubiera compilado en la copia local del ejemplo, fuera: el test
    // pone los suyos y no depende de lo que alguien compilara antes.
    final built = Directory('$repository/.didacta-build');
    if (built.existsSync()) built.deleteSync(recursive: true);

    for (final profile in [
      'problems',
      'problems-answers',
      'problems-teacher',
    ]) {
      final pdf = File(
        '$repository/.didacta-build/am-iii@2025-2026_hoja-1/$profile-es/'
        'Hoja 1 espacios normados - $profile - es.pdf',
      );
      pdf.createSync(recursive: true);
      pdf.writeAsStringSync('%PDF-1.4\n');
    }
    compiler = makeCompiler(enginePath: enginePath, repositoryPath: repository);
  });

  tearDown(() async => work.delete(recursive: true));

  Future<ExportResult> export(ExportReach reach, String folder) =>
      compiler.exportCourse(
        where: 'am-iii@2025-2026',
        to: '${work.path}/$folder',
        languages: const ['es'],
        documents: const ['hoja-1'],
        reach: reach,
      );

  /// La versión de cada fichero, como la dice su nombre: en el idioma del
  /// reparto, «Hoja de problemas (con resultados)», y no el id de la
  /// plantilla.
  List<String> profilesIn(List<String> copied) => [
    for (final name in copied)
      name.split(' - ').last.replaceAll(RegExp(r'\.pdf$'), ''),
  ]..sort();

  test('por defecto, lo del profesor se queda fuera y se dice', () async {
    final result = await export(ExportReach.students, 'alumnos');
    expect(profilesIn(result.copied), [
      'Hoja de problemas',
      'Hoja de problemas (con resultados)',
    ]);
    expect(result.withheld, ['hoja-1 · problems-teacher · es']);
    expect(result.missing, isEmpty);
  });

  test('pidiéndolo, sale todo', () async {
    final result = await export(ExportReach.teacher, 'profesor');
    expect(profilesIn(result.copied), [
      'Hoja de problemas',
      'Hoja de problemas (con resultados)',
      'Hoja de problemas (profesor)',
    ]);
    expect(result.withheld, isEmpty);
  });
}
