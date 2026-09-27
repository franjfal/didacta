/// Traducir: la memoria de traducción, el glosario y las tandas de lecciones
/// que se traducen con la máquina.
///
/// Era una parte de la sesión. Aparte porque es un trabajo con su propio
/// ciclo --estimar, traducir, guardar un commit por repositorio, aprender de
/// lo guardado-- que de la sesión solo necesita lo que cualquier pantalla ya
/// le pide: el catálogo, las pasarelas y los repositorios abiertos. La sesión
/// la sigue ofreciendo con los mismos nombres.
library;

import 'dart:async';
import 'dart:collection';
import '../data/diagnostics.dart';
import '../data/content_gateway.dart';
import '../model/catalogue.dart';
import '../model/glossary.dart';
import '../model/latex_protect.dart' show protectLatex;
import '../model/source_hash.dart';
import '../data/translator.dart';
import '../model/translation_memory.dart';
import '../model/translation_run.dart';
import '../model/yaml_patch.dart';

import 'session.dart';
import '../l10n/tr.dart';

/// Una lección que traducir: de qué idioma a cuál.
typedef TranslationTask = ({Unit unit, String from, String to});

/// Lo que pasó con una tanda de traducción.
class TranslationBatch {
  const TranslationBatch({
    required this.results,
    required this.written,
    required this.failed,
    required this.stopped,
    required this.commits,
  });

  /// Lo traducido de cada lección escrita, en el orden de [written].
  final List<TranslationResult> results;
  final List<TranslationTask> written;
  final List<({TranslationTask task, Object error})> failed;

  /// Si se paró antes de acabar. Lo hecho hasta ahí está guardado.
  final bool stopped;

  /// Cuántos cambios guardó el material: uno por repositorio.
  final int commits;

  TranslationStats get stats => results.fold(
    const TranslationStats(),
    (sum, result) => sum.plus(result.stats),
  );

  List<String> get warnings => [
    for (final result in results) ...result.warnings,
  ];
}

class TranslationService {
  TranslationService(this.session);

  final Session session;

  /// La memoria de un par de idiomas, junta de todos los repositorios.
  ///
  /// De todos y no solo del que se va a escribir: lo que alguien decidió en
  /// el repositorio de problemas vale igual para el de teoría, y es lo que
  /// hace que la misma definición no salga dicha de dos maneras.
  Future<TranslationMemory> memoryFor({
    required String from,
    required String to,
  }) async {
    final path = memoryPath(from, to);
    final parts = <TranslationMemory>[];
    for (final repo in session.openedWorkspace.repos) {
      try {
        final file = await session.gatewayFor(repo.id).read(path);
        parts.add(TranslationMemory.parse(file.text));
      } catch (caught, trace) {
        Diagnostics.instance.note('session.translationMemory', caught, trace);
        // No tenerla es lo normal hasta que alguien traduce algo.
      }
    }
    return TranslationMemory.merge(parts);
  }

  /// El glosario de un repositorio, o uno vacío si no tiene.
  Future<Glossary> glossaryIn(String repo) async {
    try {
      return Glossary.parse(
        (await session.gatewayFor(repo).read(glossaryPath)).text,
      );
    } catch (caught, trace) {
      Diagnostics.instance.note('session.glossaryIn', caught, trace);
      return Glossary();
    }
  }

  /// El de todos los repositorios abiertos, junto: lo que decidió el
  /// departamento vale en la teoría y en los problemas.
  Future<Glossary> glossary() async => Glossary.merge([
    for (final repo in session.openedWorkspace.repos) await glossaryIn(repo.id),
  ]);

  /// Guarda el glosario de [repo].
  Future<void> saveGlossary(String repo, Glossary glossary) async {
    final gateway = session.gatewayFor(repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [repo]));
    }
    var sha = '';
    try {
      sha = (await gateway.read(glossaryPath)).sha;
    } catch (caught, trace) {
      Diagnostics.instance.note('session.saveGlossary', caught, trace);
      // Primera vez.
    }
    await gateway.save(
      path: glossaryPath,
      text: glossary.toTsv(),
      sha: sha,
      message: tr('Glosario de traducción: {0} término(s)', [
        glossary.terms.length,
      ]),
    );
  }

  /// Traduce una unidad y deja el resultado escrito.
  ///
  /// Es una tanda de una: ver [translateUnits]. Lo que se escribe queda
  /// **como borrador**, con la huella del original, y el `.tex` y su estado
  /// van en el mismo commit; la memoria, en otro. Si el proveedor falla, no
  /// se escribe nada y el error sube tal cual.
  Future<TranslationResult> translateUnit({
    required Unit unit,
    required String from,
    required String to,
    required Translator translator,
    List<TermCheck> terms = const [],
  }) async {
    final batch = await translateUnits(
      tasks: [(unit: unit, from: from, to: to)],
      translator: translator,
      terms: terms,
      failFast: true,
    );
    return batch.results.single;
  }

  /// Cuánto se mandaría al proveedor por traducir [tasks], sin mandarlo.
  ///
  /// Lee los originales y la memoria de cada par de idiomas, y cuenta como
  /// [translateUnits]: lo que ya sabe la memoria, y lo que se repite dentro
  /// de la misma tanda, no se paga dos veces.
  Future<TranslationEstimate> estimate(List<TranslationTask> tasks) async {
    final memories = <String, TranslationMemory>{};
    var total = const TranslationEstimate();
    for (final task in tasks) {
      final pair = '${task.from}-${task.to}';
      final memory = memories[pair] ??= await memoryFor(
        from: task.from,
        to: task.to,
      );
      try {
        final source = await session
            .gatewayFor(task.unit.repo)
            .read(task.unit.fileFor(task.from));
        final estimate = estimateLatex(source.text, memory);
        total = total.plus(estimate);
        // Lo de esta lección ya «está» para las siguientes: la definición
        // que sale en treinta lecciones se pide una vez.
        memory.remember([
          for (final segment in protectLatex(source.text))
            if (!segment.verbatim && segment.letters > 0)
              MemoryEntry(source: segment.text, target: segment.text),
        ]);
      } catch (caught, trace) {
        Diagnostics.instance.note('session.estimateTranslation', caught, trace);
        // Una que no se puede leer no se cuenta, y se dice: de esa no se
        // sabe cuánto costaría.
        total = total.plus(const TranslationEstimate(unreadable: 1));
      }
    }
    return total;
  }

  /// Traduce una tanda y la guarda como **un cambio por repositorio**.
  ///
  /// Antes eran dos commits por lección --el `.tex` con su estado, y la
  /// memoria--, y doscientas lecciones dejaban cuatrocientos commits que
  /// decían lo mismo. Ahora lo traducido va junto en uno por repositorio, y
  /// lo aprendido en otro por par de idiomas: siguen separados el material y
  /// la memoria, que es lo que se quiere poder mirar por separado, pero por
  /// tanda.
  ///
  /// Se puede parar con [stop]: se mira antes de cada lección, y lo que ya se
  /// tradujo se guarda igual --se ha pagado, y tirarlo sería pagarlo dos
  /// veces--. Una lección que falla no para la tanda; con [failFast], sí, y
  /// entonces no se escribe nada.
  ///
  /// La memoria crece mientras se traduce: lo que se pide en la primera
  /// lección sale de la memoria en las siguientes. Y el título de la lección
  /// se traduce también, si en ese idioma no tiene: una traducción con el
  /// título en el idioma original sale así en el índice del PDF.
  Future<TranslationBatch> translateUnits({
    required List<TranslationTask> tasks,
    required Translator translator,
    List<TermCheck> terms = const [],
    bool Function()? stop,
    void Function(int done, TranslationTask task)? onProgress,
    bool failFast = false,
    bool useGlossary = true,
  }) async {
    final memories = <String, TranslationMemory>{};
    final learned = <String, List<MemoryEntry>>{};
    // El glosario, una vez para toda la tanda. Sus términos se avisan como
    // los de [terms]: ver `model/glossary.dart`.
    final glossary = useGlossary ? await this.glossary() : Glossary();
    // Lo que se va a escribir, por repositorio y ruta, con el sha que tenía
    // al leerlo. Una misma `unit.yaml` recibe el estado de varios idiomas:
    // se lee de aquí la segunda vez, y no del disco, o el segundo borraría
    // lo del primero.
    final pending = <String, Map<String, ({String text, String sha})>>{};
    final results = <TranslationResult>[];
    final written = <TranslationTask>[];
    final failed = <({TranslationTask task, Object error})>[];
    var stopped = false;

    Future<({String text, String sha})?> readFor(
      String repo,
      String path,
    ) async {
      final waiting = pending[repo]?[path];
      if (waiting != null) return waiting;
      try {
        final file = await session.gatewayFor(repo).read(path);
        return (text: file.text, sha: file.sha);
      } on ContentException catch (error) {
        if (error.kind != ContentFailure.missing) rethrow;
        return null;
      }
    }

    for (final (index, task) in tasks.indexed) {
      if (stop?.call() ?? false) {
        stopped = true;
        break;
      }
      final unit = task.unit;
      try {
        final gateway = session.gatewayFor(unit.repo);
        if (!gateway.canWrite) {
          throw ArgumentError(tr('no se puede escribir en {0}', [unit.repo]));
        }
        final pair = '${task.from}-${task.to}';
        final memory = memories[pair] ??= await memoryFor(
          from: task.from,
          to: task.to,
        );
        final source = await gateway.read(unit.fileFor(task.from));

        // El título, en la misma petición que el texto cuando la hay.
        final title = unit.titles[task.from]?.trim() ?? '';
        final wantsTitle =
            title.isNotEmpty && (unit.titles[task.to]?.trim() ?? '').isEmpty;
        String? translatedTitle = wantsTitle
            ? memory.lookup(title)?.target
            : null;
        final askTitle = wantsTitle && translatedTitle == null;

        final result = await translateLatex(
          source.text,
          memory: memory,
          translate: (pieces) async {
            final answers = await translator.translate(
              [...pieces, if (askTitle) title],
              from: task.from,
              to: task.to,
            );
            if (askTitle && answers.length == pieces.length + 1) {
              translatedTitle = answers.last.trim();
              return answers.sublist(0, pieces.length);
            }
            return answers;
          },
          terms: [...terms, ...glossary.checksFor(task.from, task.to)],
          unit: unit.path,
          by: session.auth.user?.login ?? '',
          when: DateTime.now(),
        );
        // Sin nada que pedir no se llama al proveedor, y el título se queda
        // sin pedir: una llamada suelta, solo para él.
        if (askTitle && translatedTitle == null) {
          final answers = await translator.translate(
            [title],
            from: task.from,
            to: task.to,
          );
          if (answers.length == 1) translatedTitle = answers.single.trim();
        }
        final titleLearned = [
          if (askTitle && (translatedTitle ?? '').isNotEmpty)
            MemoryEntry(
              source: title,
              target: translatedTitle!,
              unit: unit.path,
              at: DateTime.now(),
              by: session.auth.user?.login ?? '',
            ),
        ];

        // Sangrado antes de escribirlo, si este idioma lo tiene puesto. Es
        // donde más falta hace: un traductor devuelve cada párrafo en una
        // sola línea --hace lo suyo-- y sin esto la primera versión de cada
        // traducción entra en el repositorio como un muro, y así se queda.
        final text = unit.indentsIn(task.to)
            ? await session.tidyLatex(result.text)
            : result.text;
        final target = await readFor(unit.repo, unit.fileFor(task.to));

        // Y marcada como borrador **en el mismo commit**. Sin esto el motor
        // cuenta el fichero como «traducida» --existe, y nadie ha dicho otra
        // cosa-- y la lección desaparece de lo que queda por revisar, que es
        // justo donde tiene que estar algo que no ha leído nadie.
        final yamlPath = '${unit.path}/unit.yaml';
        final yaml =
            await readFor(unit.repo, yamlPath) ??
            (text: tr('# Metadatos de la unidad.\nlanguages:\n'), sha: '');
        final patch = YamlPatch(yaml.text)
          ..setInFlowMap(['languages', task.to], 'status', 'draft');
        // Traducida desde este texto: si el original cambia después, el
        // borrador se queda atrás, y el motor lo dice.
        if (task.from == unit.reference) {
          patch.setInFlowMap(
            ['languages', task.to],
            'source_hash',
            contentHash(source.text),
          );
        }
        if ((translatedTitle ?? '').isNotEmpty) {
          try {
            patch.setScalar(['title', task.to], translatedTitle);
          } on YamlPatchException {
            // Un título escrito de una forma que no se sabe tocar se deja
            // como está: el texto traducido vale igual sin él.
          }
        }

        final repoFiles = pending.putIfAbsent(unit.repo, () => {});
        repoFiles[unit.fileFor(task.to)] = (text: text, sha: target?.sha ?? '');
        repoFiles[yamlPath] = (text: patch.result, sha: yaml.sha);

        memory.remember([...result.learned, ...titleLearned]);
        learned.putIfAbsent('${unit.repo}\u0000$pair', () => []).addAll([
          ...result.learned,
          ...titleLearned,
        ]);
        results.add(result);
        written.add(task);
      } catch (error) {
        if (failFast) rethrow;
        // Una que falla no para la tanda: las otras doscientas no tienen la
        // culpa, y quedarse a medias sin decir cuál falló es peor.
        failed.add((task: task, error: error));
      }
      onProgress?.call(index + 1, task);
    }

    // El material, de una vez por repositorio.
    var commits = 0;
    for (final entry in pending.entries) {
      final done = [
        for (final task in written)
          if (task.unit.repo == entry.key) task,
      ];
      final languages = {for (final task in done) task.to}.join(', ');
      await session
          .gatewayFor(entry.key)
          .saveAll(
            files: [
              for (final file in entry.value.entries)
                (path: file.key, text: file.value.text, sha: file.value.sha),
            ],
            message: done.length == 1
                ? tr(
                    'Traducir «{0}» a '
                    '{1} (borrador)',
                    [done.single.unit.title(done.single.from), done.single.to],
                  )
                : tr('Traducir {0} lecciones a {1} (borrador)', [
                    done.length,
                    languages,
                  ]),
          );
      commits += 1;
    }

    // Y lo aprendido, aparte: un commit por repositorio y par de idiomas.
    for (final entry in learned.entries) {
      final [repo, pair] = entry.key.split('\u0000');
      final [from, to] = pair.split('-');
      await remember(
        repo: repo,
        from: from,
        to: to,
        learned: entry.value,
        memory: await memoryFor(from: from, to: to),
      );
    }

    if (written.isNotEmpty) await session.reloadCatalogue();
    return TranslationBatch(
      results: results,
      written: written,
      failed: failed,
      stopped: stopped,
      commits: commits,
    );
  }

  /// Añade al fichero de memoria lo que se acaba de aprender.
  ///
  /// Añadiendo al final y sin reescribir lo que hay: el fichero lo tocan
  /// varias personas y lo fusiona git, y reescribirlo entero convierte cada
  /// traducción en un conflicto con todo lo que otra persona haya traducido
  /// mientras tanto.
  Future<void> remember({
    required String repo,
    required String from,
    required String to,
    required List<MemoryEntry> learned,
    required TranslationMemory memory,
  }) async {
    final lines = memory.linesFor(learned);
    if (lines.isEmpty) return;

    final path = memoryPath(from, to);
    final gateway = session.gatewayFor(repo);
    var text = '';
    var sha = '';
    try {
      final file = await gateway.read(path);
      text = file.text;
      sha = file.sha;
    } catch (caught, trace) {
      Diagnostics.instance.note('session._rememberTranslations', caught, trace);
      // Primera vez.
    }
    final body = StringBuffer(text);
    if (text.isNotEmpty && !text.endsWith('\n')) body.write('\n');
    for (final line in lines) {
      body.writeln(line);
    }

    try {
      await gateway.save(
        path: path,
        text: body.toString(),
        sha: sha,
        message: tr('Memoria de traducción {0}→{1}: {2} segmento(s)', [
          from,
          to,
          lines.length,
        ]),
      );
    } catch (caught, trace) {
      Diagnostics.instance.note('session._rememberTranslations', caught, trace);
      // No poder guardarla no puede deshacer la traducción, que ya está
      // escrita. Se vuelve a aprender la próxima vez.
    }
  }
}
