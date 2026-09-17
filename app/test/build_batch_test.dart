/// Compilar en lote: un documento, un tema o un curso entero.
///
/// La operación de la víspera. Un curso son cuarenta salidas y media hora, así
/// que lo que importa no es solo que compile: es que se sepa por dónde va, que
/// un documento que falla no se lleve por delante a los demás, y que al acabar
/// la pantalla sepa qué PDF hay para ofrecerlos.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';

import 'fixture.dart';

typedef Job = ({
  String repo,
  String course,
  String year,
  String id,
  String title,
});

Job job(String id) =>
    (repo: '', course: 'am-i', year: '2026-2027', id: id, title: 'El $id');

/// Un compilador que apunta lo que le piden y contesta lo que se le diga.
class RecordingCompiler extends FakeCompiler {
  final List<String> compiled = [];
  final Set<String> failing = {};

  @override
  Future<List<BuildableProfile>> documentProfiles(String document) async =>
      const [
        BuildableProfile(
          id: 'notes',
          label: 'Apuntes',
          family: 'notes',
          reveals: 'statements',
          byDefault: true,
        ),
        BuildableProfile(
          id: 'slides',
          label: 'Diapositivas',
          family: 'slides',
          reveals: 'statements',
          byDefault: true,
        ),
      ];

  @override
  Future<List<CompileOutput>> compileDocument({
    required String document,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) async {
    compiled.add(document);
    onOutput?.call('=== $document');
    final ok = !failing.contains(document);
    return [
      for (final profile in profiles)
        CompileOutput(profile: profile, language: 'es', ok: ok),
    ];
  }
}

Future<FakeSession> session(RecordingCompiler compiler) async {
  final catalogue = catalogueWith(defaultUnits());
  final made = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: compiler,
  );
  await made.primeForTest(catalogue);
  await made.useCloneForTest('/tmp/didacta-test');
  return made;
}

void main() {
  test('compila cada documento, con todas sus versiones', () async {
    final compiler = RecordingCompiler();
    final it = await session(compiler);

    final ok = await it.buildDocuments([
      job('tema-1'),
      job('hoja-1'),
    ], title: 'Curso entero');

    expect(compiler.compiled, [
      'am-i@2026-2027/tema-1',
      'am-i@2026-2027/hoja-1',
    ]);
    expect(ok, 2);
  });

  test('va contando por dónde va', () async {
    // Media hora sin saber cuánto queda es media hora preguntándose si se ha
    // colgado.
    final compiler = RecordingCompiler();
    final it = await session(compiler);
    final console = it.buildConsole;

    final work = it.buildDocuments([
      job('a'),
      job('b'),
      job('c'),
    ], title: 'Tema 1');
    expect(console.total, 3);
    await work;
    expect(console.done, 3);
    expect(console.title, 'Tema 1');
  });

  test('uno que falla no para los demás', () async {
    // Parar el lote por un documento dejaría los otros treinta sin hacer, y
    // el que falla ya sale en el registro con su error.
    final compiler = RecordingCompiler()..failing.add('am-i@2026-2027/b');
    final it = await session(compiler);

    final ok = await it.buildDocuments([
      job('a'),
      job('b'),
      job('c'),
    ], title: 'Curso');

    expect(compiler.compiled.length, 3, reason: 'se intentaron los tres');
    expect(ok, 2);
    expect(it.buildConsole.ok, isFalse);
  });

  test('lo que escribe el motor va al registro', () async {
    final compiler = RecordingCompiler();
    final it = await session(compiler);
    await it.buildDocuments([job('tema-1')], title: 'Uno');
    expect(it.buildConsole.lines, contains('=== am-i@2026-2027/tema-1'));
  });

  test('al acabar vuelve a preguntar qué hay compilado', () async {
    // Si no, los atajos de ver el PDF no aparecen hasta volver a entrar en la
    // pantalla, justo después de haberlos generado.
    final compiler = RecordingCompiler();
    final it = await session(compiler);
    final before = compiler.builtCalls;
    await it.buildDocuments([job('tema-1')], title: 'Uno');
    expect(compiler.builtCalls, greaterThan(before));
  });

  test('sin nada que compilar no se llama al motor', () async {
    final compiler = RecordingCompiler();
    final it = await session(compiler);
    final ok = await it.buildDocuments(const [], title: 'Vacío');
    expect(compiler.compiled, isEmpty);
    expect(ok, 0);
  });
}
