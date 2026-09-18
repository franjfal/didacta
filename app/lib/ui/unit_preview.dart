/// «¿Cómo queda esto?»
///
/// Una unidad compilada, en las versiones que le pegan: diapositivas, libro,
/// apuntes. Es la pregunta que se hace editando y hasta ahora no se podía
/// responder sin salir a un terminal y construir el tema entero alrededor.
///
/// Tres decisiones que conviene dejar dichas:
///
/// **Compila el motor, no la aplicación.** `didacta preview` ya sabe montar
/// el preámbulo, elegir la clase según el perfil y leer el log de LaTeX, y
/// está probado compilando de verdad. Una segunda implementación en Dart
/// sería una segunda cosa que se desincroniza del `.sty`.
///
/// **El preámbulo no se ve.** La envoltura que hace que una unidad compile se
/// genera en el directorio de compilación, que no se versiona. El `.tex` de
/// la unidad sigue siendo contenido.
///
/// **El PDF se abre en el visor del sistema.** En lugar de incrustar uno: el
/// del sistema tiene zoom, navegación y pantalla completa, que para repasar
/// unas diapositivas es exactamente lo que hace falta, y no mete una
/// dependencia de renderizado de PDF en una aplicación que edita LaTeX.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/compiler.dart';
import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'build_console.dart';
import 'pdf_tab.dart';
import 'missing_translations.dart';
import 'theme.dart';

/// El estado de compilar una unidad.
///
/// No es un widget, y por la misma razón que `_LanguageEditor` tampoco lo es:
/// una pestaña de la que te vas tiene que conservar lo que había. Sin esto,
/// abrir el PDF en su pestaña y volver a «compilar» borraba los resultados y
/// obligaba a compilar otra vez -- que es justo lo que la pestaña venía a
/// evitar.
/// Lo que se puede compilar: una unidad suelta o un tema entero.
///
/// Existe para que las dos pantallas sean **la misma pantalla**. Elegir
/// versiones, elegir idiomas, ver lo que salió, abrirlo lado a lado, en el
/// visor del sistema o en el Finder: eso no cambia porque lo que se compile
/// sea una lección o el tema que la contiene, y tener dos implementaciones
/// de lo mismo es tener dos sitios donde arreglar cada cosa.
///
/// Lo único que cambia es qué le pide al motor, que es justo lo que hay
/// debajo.
abstract class PreviewTarget {
  /// El idioma marcado de entrada.
  String get defaultLanguage;

  /// Qué se está compilando, para decirlo en el título: «esta unidad», «este
  /// tema». La misma pantalla sirve para las dos cosas y hasta ahora decía
  /// «unidad» compilando un tema entero.
  String get what;

  /// De qué repositorio es lo que se compila: se compila contra su raíz.
  String get repo;

  /// De qué asignatura, cuando se sabe.
  ///
  /// Null en una unidad suelta, que no es de ninguna: la biblioteca es
  /// compartida y la misma lección la usan asignaturas distintas. Sirve para
  /// saber en qué idiomas tiene sentido ofrecer compilar --los de esa
  /// asignatura, no los de todo el material--.
  String? get course => null;

  /// Qué falta por traducir para poder compilar en [language].
  ///
  /// Vacío es «se puede compilar». No vacío es que **no se compila**: lo que
  /// saldría es un documento con partes en otro idioma, y eso no se lleva a
  /// un aula. La lista es el trabajo que queda.
  List<MissingPiece> missingIn(Catalogue catalogue, String language);

  /// Las versiones que admite, con las suyas marcadas.
  Future<List<BuildableProfile>> profilesFrom(Compiler compiler);

  /// Lo que ya está compilado, si se puede saber.
  Future<List<ExistingOutput>> existingFrom(Compiler compiler);

  Future<List<CompileOutput>> buildWith(
    Compiler compiler, {
    required List<String> profiles,
    required List<String> languages,
    bool fast,
    void Function(String line)? onOutput,
  });
}

/// Una unidad suelta: `didacta preview`.
class UnitTarget implements PreviewTarget {
  const UnitTarget(this.unit);

  final Unit unit;

  @override
  String get defaultLanguage => unit.reference;

  /// Ninguna: la biblioteca es compartida y la misma lección la usan
  /// asignaturas distintas, así que compilarla suelta se ofrece en los
  /// idiomas del material y no en los de una.
  @override
  String? get course => null;

  @override
  String get what => 'esta unidad';

  @override
  String get repo => unit.repo;

  /// Una unidad suelta se previsualiza igual.
  ///
  /// La regla de no compilar sin traducción es del documento: lo que sale de
  /// ahí es lo que se proyecta en clase, y un tema con cinco páginas en otro
  /// idioma no se lleva a un aula. Una unidad suelta es lo contrario: se
  /// mira para ver cómo queda, el motor marca en el PDF que ese idioma
  /// falta, y quitar el botón dejaría sin forma de ver el original mientras
  /// se traduce.
  @override
  List<MissingPiece> missingIn(Catalogue catalogue, String language) =>
      const [];

  @override
  Future<List<BuildableProfile>> profilesFrom(Compiler compiler) =>
      compiler.profilesFor(unit.path);

  @override
  Future<List<ExistingOutput>> existingFrom(Compiler compiler) =>
      compiler.outputsFor(unit.path);

  @override
  Future<List<CompileOutput>> buildWith(
    Compiler compiler, {
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) => compiler.compile(
    unitPath: unit.path,
    profiles: profiles,
    languages: languages,
    fast: fast,
    onOutput: onOutput,
  );
}

/// Un documento entero: `didacta build`.
///
/// El tema tal como se da, con sus unidades en su orden, su portada y sus
/// referencias cruzadas. Compilar una lección suelta dice si esa lección
/// está bien; compilar el tema dice si **la clase** está bien, que es otra
/// pregunta y la que se hace la víspera.
class DocumentTarget implements PreviewTarget {
  const DocumentTarget({
    required this.courseId,
    required this.year,
    required this.documentId,
    required this.language,
    required this.document,
  });

  final String courseId;
  final String year;
  final String documentId;
  final String language;

  @override
  String? get course => courseId;

  /// El documento, para saber qué unidades lleva dentro.
  final Document document;

  @override
  String get repo => document.repo;

  @override
  List<MissingPiece> missingIn(Catalogue catalogue, String language) =>
      missingFor(document, catalogue, language);

  /// Cómo nombra el motor a un documento: `curso@año/documento`. Los ids se
  /// repiten entre asignaturas --hay nueve «capitulo-1»-- así que el nombre
  /// a secas no vale.
  String get reference => '$courseId@$year/$documentId';

  @override
  String get defaultLanguage => language;

  @override
  String get what => 'este tema';

  @override
  Future<List<BuildableProfile>> profilesFrom(Compiler compiler) =>
      compiler.documentProfiles(reference);

  /// Todavía no: el motor sabe decir qué hay compilado de una unidad, y para
  /// un documento aún no. Vacío en lugar de inventárselo, que enseñaría un
  /// atajo que abre un PDF que no existe.
  @override
  Future<List<ExistingOutput>> existingFrom(Compiler compiler) async =>
      const [];

  @override
  Future<List<CompileOutput>> buildWith(
    Compiler compiler, {
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  }) => compiler.compileDocument(
    document: reference,
    profiles: profiles,
    languages: languages,
    fast: fast,
    onOutput: onOutput,
  );
}

class PreviewState {
  PreviewState({
    required this.target,
    required this.session,
    required this.onChanged,
    required this.onCompiled,
  }) {
    // El idioma de referencia, marcado de entrada. Los demás se añaden: se
    // compila `es` y `va` juntos para ver si la traducción cabe.
    languages.add(target.defaultLanguage);
    scheduleMicrotask(load);
  }

  final PreviewTarget target;
  final Session session;
  final VoidCallback onChanged;

  /// Lo que acaba de compilar, para que la página lo abra.
  ///
  /// Automático y no a botones: acabas de pedir estas versiones, y quererlas
  /// ver es la única razón por la que las pediste.
  final ValueChanged<List<CompileOutput>> onCompiled;

  CompilerStatus? status;
  List<BuildableProfile> profiles = const [];

  /// Lo que ya está compilado de esta unidad, y si sigue valiendo.
  ///
  /// Se pregunta al abrir la pestaña y después de compilar: es lo que permite
  /// abrir una versión sin volver a hacerla, que era lo único que obligaba a
  /// pedir dos veces la misma compilación.
  List<ExistingOutput> existing = const [];
  final Set<String> chosen = {};

  /// Los idiomas elegidos. Varios: la comparación que importa es la del
  /// mismo perfil en dos idiomas.
  final Set<String> languages = {};

  bool loading = true;
  bool building = false;
  Object? problem;
  List<CompileOutput> results = const [];

  Future<void> load() async {
    final compiler = session.compiler(repo: target.repo);
    if (compiler == null) {
      status = CompilerStatus(
        ready: false,
        enginePath: session.enginePath,
        problem: session.canCompile
            ? 'Compilar necesita el motor y un clon del repositorio en '
                  'disco. Los dos se eligen en Ajustes.'
            : 'Compilar necesita LaTeX, y un navegador no lo tiene. Usa la '
                  'aplicación de escritorio.',
      );
      loading = false;
      onChanged();
      return;
    }

    try {
      final found = await compiler.status();
      final available = found.ready
          ? await target.profilesFrom(compiler)
          : const <BuildableProfile>[];
      status = found;
      profiles = available;
      if (found.ready) await _loadExisting(compiler);
      // Las dos que se pidieron más la prosa por defecto, marcadas de
      // entrada: son la respuesta casi siempre que alguien abre esto.
      chosen
        ..clear()
        ..addAll(available.where((p) => p.isPrimary).map((p) => p.id));
      if (chosen.isEmpty && available.isNotEmpty) {
        chosen.add(available.first.id);
      }
    } catch (error) {
      problem = error;
    } finally {
      loading = false;
      onChanged();
    }
  }

  Future<void> _loadExisting(Compiler compiler) async {
    try {
      final found = await target.existingFrom(compiler);
      // Solo lo que existe: la lista de lo que *no* está compilado son los
      // chips de arriba, y repetirla aquí sería la misma cosa dos veces.
      existing = [
        for (final output in found)
          if (output.exists) output,
      ];
    } catch (error) {
      // No saber qué hay compilado no impide compilar: se pierde el atajo,
      // no la pantalla.
      existing = const [];
    }
  }

  /// Vuelve a preguntar qué hay compilado.
  ///
  /// Después de guardar un `.tex`, lo que había pasa a estar viejo, y eso
  /// tiene que verse sin recargar nada.
  Future<void> refreshExisting() async {
    final compiler = session.compiler(repo: target.repo);
    if (compiler == null) return;
    await _loadExisting(compiler);
    onChanged();
  }

  void toggle(String id) {
    if (!chosen.remove(id)) chosen.add(id);
    onChanged();
  }

  void toggleLanguage(String code) {
    if (!languages.remove(code)) languages.add(code);
    // Nunca ninguno: compilar cero idiomas no es un estado que quiera nadie,
    // y un botón deshabilitado por eso sería un acertijo.
    if (languages.isEmpty) languages.add(code);
    onChanged();
  }

  /// Lo que falta por traducir de los idiomas elegidos.
  ///
  /// Vacío es «se puede compilar». Se mira aquí y no al pulsar porque el
  /// botón tiene que estar apagado antes: enterarte de que no se puede
  /// después de esperar la compilación es la peor forma de enterarse.
  Map<String, List<MissingPiece>> get blocked {
    final catalogue = session.catalogueOrNull;
    if (catalogue == null) return const {};
    final found = <String, List<MissingPiece>>{};
    for (final code in session.languagesIn(target.course)) {
      if (!languages.contains(code)) continue;
      final missing = target.missingIn(catalogue, code);
      if (missing.isNotEmpty) found[code] = missing;
    }
    return found;
  }

  /// Cuántas salidas produciría compilar ahora: perfiles por idiomas.
  int get outputCount => chosen.length * languages.length;

  /// Borra lo que ya está compilado, y vuelve a preguntar qué queda.
  ///
  /// Sin confirmación cuando es una sola: vive en el directorio de
  /// compilación, que no se versiona, y el botón de al lado la rehace. Lo que
  /// sí se pregunta es el «borrar todas», porque ahí el clic no dice cuántos
  /// ficheros se lleva.
  Future<void> delete(List<ExistingOutput> outputs) async {
    final compiler = session.compiler(repo: target.repo);
    if (compiler == null || outputs.isEmpty) return;
    problem = null;
    onChanged();
    try {
      await compiler.deleteOutputs([for (final o in outputs) o.pdf]);
    } catch (error) {
      problem = error;
    }
    // Aunque falle: si se ha llevado la mitad, la lista tiene que decir cuál.
    await _loadExisting(compiler);
    onChanged();
  }

  /// Compila una sola salida: la de una tarjeta de «ya compiladas».
  ///
  /// Es lo que se pulsa cuando una está vieja: rehacer *esa*, y no las tres
  /// que estén marcadas arriba.
  Future<void> compileOne(ExistingOutput output) async {
    final compiler = session.compiler(repo: target.repo);
    if (compiler == null) return;
    building = true;
    problem = null;
    onChanged();
    final console = session.buildConsole;
    console.start('${output.label} · ${output.language}');
    try {
      results = await target.buildWith(
        compiler,
        profiles: [output.profile],
        languages: [output.language],
        onOutput: console.add,
      );
      console.finish(ok: results.every((result) => result.ok));
      onCompiled(results);
      await _loadExisting(compiler);
    } catch (error) {
      problem = error;
      console.finish(failure: error);
    } finally {
      building = false;
      onChanged();
    }
  }

  Future<void> compile() async {
    final compiler = session.compiler(repo: target.repo);
    if (compiler == null || chosen.isEmpty || languages.isEmpty) return;
    // Nunca a medias: si falta una traducción de las elegidas, no se compila
    // ninguna. Compilar «las que se puedan» dejaría a alguien con la mitad
    // de lo que pidió y sin saber qué mitad.
    if (blocked.isNotEmpty) return;
    building = true;
    problem = null;
    results = const [];
    onChanged();
    final console = session.buildConsole;
    console.start(
      outputCount <= 1
          ? 'Compilando ${target.what}'
          : 'Compilando ${target.what}: $outputCount versiones',
    );
    try {
      results = await target.buildWith(
        compiler,
        profiles: profiles
            .where((p) => chosen.contains(p.id))
            .map((p) => p.id)
            .toList(),
        // En el orden del catálogo y no del conjunto, para que `es` quede
        // siempre a la izquierda de `va`: comparar dos cosas que cambian de
        // lado entre compilaciones es peor que no compararlas.
        languages: [
          for (final code in session.languagesIn(target.course))
            if (languages.contains(code)) code,
        ],
        onOutput: console.add,
      );
      console.finish(ok: results.every((result) => result.ok));
      onCompiled(results);
      await _loadExisting(compiler);
    } catch (error) {
      problem = error;
      console.finish(failure: error);
    } finally {
      building = false;
      onChanged();
    }
  }
}

class UnitPreview extends StatelessWidget {
  const UnitPreview({
    super.key,
    required this.state,
    required this.onOpen,
    required this.onExternal,
  });

  final PreviewState state;

  /// Abre un PDF en una pestaña de la unidad. Lo hace la página, porque las
  /// pestañas son suyas y sobreviven a salir de aquí y volver.
  final ValueChanged<OpenPdf> onOpen;

  /// El visor del sistema y el Finder.
  final void Function(String path, {required bool reveal}) onExternal;

  /// Compila, y enseña el terminal mientras lo hace.
  ///
  /// En este orden y sin esperar: la compilación marca el registro como
  /// empezado antes de su primer `await`, así que la ventana abre ya con
  /// esta compilación dentro y no con los restos de la anterior. Y no se
  /// espera a que la ventana se cierre porque cerrarla no es cancelar:
  /// quitarla de en medio y seguir compilando es lo normal.
  void _watch(BuildContext context, Future<void> Function() compile) {
    unawaited(compile());
    unawaited(
      showBuildConsole(context, state.session.buildConsole, autoClose: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final status = state.status;
    if (status != null && !status.ready) {
      return _NotReady(problem: status.problem ?? 'No se puede compilar.');
    }

    return Column(
      children: [
        _Controls(
          what: state.target.what,
          profiles: state.profiles,
          chosen: state.chosen,
          chosenLanguages: state.languages,
          languages: state.session.languagesIn(state.target.course),
          outputs: state.outputCount,
          building: state.building,
          onToggle: state.toggle,
          onLanguage: state.toggleLanguage,
          onCompile:
              state.chosen.isEmpty || state.building || state.blocked.isNotEmpty
              ? null
              : () => _watch(context, state.compile),
          // Solo cuando hay algo que enseñar. El registro sobrevive a cerrar
          // la ventana, y esto es lo que permite volver a ella: se cierra
          // para ver el PDF, y el aviso que pasó volando sigue estando.
          onConsole: state.session.buildConsole.isEmpty
              ? null
              : () => showBuildConsole(context, state.session.buildConsole),
        ),
        Expanded(
          child: state.problem != null
              ? _Failure(problem: state.problem!)
              : state.blocked.isNotEmpty
              ? MissingTranslations(byLanguage: state.blocked)
              : _Results(
                  results: state.results,
                  existing: state.existing,
                  building: state.building,
                  onView: onOpen,
                  onOpen: (path) => onExternal(path, reveal: false),
                  onReveal: (path) => onExternal(path, reveal: true),
                  onRecompile: (output) =>
                      _watch(context, () => state.compileOne(output)),
                  onDelete: (output) => state.delete([output]),
                  onDeleteAll: () => state.delete(state.existing),
                ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.what,
    required this.profiles,
    required this.chosen,
    required this.chosenLanguages,
    required this.languages,
    required this.outputs,
    required this.building,
    required this.onToggle,
    required this.onLanguage,
    required this.onCompile,
    required this.onConsole,
  });

  /// «esta unidad» o «este tema».
  final String what;

  final List<BuildableProfile> profiles;
  final Set<String> chosen;

  /// Los idiomas elegidos. Varios a la vez: es lo que permite comparar.
  final Set<String> chosenLanguages;

  final List<String> languages;

  /// Cuántas salidas produciría compilar: perfiles por idiomas. Se dice en
  /// el botón, porque tres perfiles por tres idiomas son nueve compilaciones
  /// y eso se tarda.
  final int outputs;

  final bool building;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onLanguage;
  final VoidCallback? onCompile;

  /// Volver a abrir el terminal de la última compilación. Null cuando no
  /// hay ninguna todavía.
  final VoidCallback? onConsole;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: didactaPanel,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Compilar $what',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Los idiomas de la salida, que no tienen que ser el que se
              // está editando, y pueden ser varios: dos idiomas del mismo
              // perfil se abren lado a lado, y comparar es para lo que se
              // compila.
              for (final code in languages)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: FilterChip(
                    key: Key('language-$code'),
                    label: Text(code),
                    selected: chosenLanguages.contains(code),
                    visualDensity: VisualDensity.compact,
                    onSelected: building ? null : (_) => onLanguage(code),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final profile in profiles)
                FilterChip(
                  key: Key('profile-${profile.id}'),
                  // Dos líneas: cómo se llama la versión y qué lleva dentro
                  // de los ejercicios. La segunda es la pregunta que se hace
                  // de verdad --«¿esta lleva las soluciones?»--, y con `problems`
                  // y `problems-answers` uno al lado del otro no se contesta
                  // sola. Lo que se imprime para una clase se decide aquí.
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(profile.label),
                      Text(
                        profile.shows,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.25,
                          color: profile.givesAway
                              ? didactaTeacher
                              : didactaMuted,
                        ),
                      ),
                    ],
                  ),
                  selected: chosen.contains(profile.id),
                  visualDensity: VisualDensity.compact,
                  avatar: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _familyColour(profile.family),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  onSelected: building ? null : (_) => onToggle(profile.id),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                key: const Key('compile'),
                icon: building
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 17),
                label: Text(
                  building
                      ? 'Compilando…'
                      : outputs <= 1
                      ? 'Compilar'
                      : 'Compilar $outputs versiones',
                ),
                onPressed: onCompile,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chosenLanguages.length > 1
                      ? 'Los idiomas de un mismo perfil se abren lado a lado, '
                            'para comparar.'
                      : 'El preámbulo lo pone Didacta al compilar; no está '
                            'en el fichero.',
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
              ),
              if (onConsole != null)
                TextButton.icon(
                  key: const Key('show-console'),
                  icon: const Icon(Icons.terminal, size: 16),
                  label: Text(building ? 'Ver el terminal' : 'Último registro'),
                  style: TextButton.styleFrom(
                    foregroundColor: didactaMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onConsole,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _familyColour(String family) => switch (family) {
    'slides' => didactaThm,
    'problems' => didactaEx,
    'handout' => didactaQues,
    'exam' => didactaTeacher,
    _ => didactaDefn,
  };
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.existing,
    required this.building,
    required this.onView,
    required this.onOpen,
    required this.onReveal,
    required this.onRecompile,
    required this.onDelete,
    required this.onDeleteAll,
  });

  final List<CompileOutput> results;
  final List<ExistingOutput> existing;
  final bool building;
  final ValueChanged<OpenPdf> onView;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onReveal;
  final ValueChanged<ExistingOutput> onRecompile;
  final ValueChanged<ExistingOutput> onDelete;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty && existing.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  building
                      ? Icons.hourglass_top
                      : Icons.picture_as_pdf_outlined,
                  size: 30,
                  color: didactaMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  building
                      ? 'Compilando. La primera vez tarda más: LaTeX está '
                            'construyendo los formatos.'
                      : 'Nada compilado todavía. Elige las versiones y pulsa '
                            'compilar.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: didactaMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        if (existing.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(child: _Label('Ya compiladas')),
              TextButton.icon(
                key: const Key('delete-all'),
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: Text(
                  existing.length == 1
                      ? 'Borrar la compilada'
                      : 'Borrar las ${existing.length}',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: didactaMuted,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: building
                    ? null
                    : () => _confirmDeleteAll(context, existing.length),
              ),
            ],
          ),
          // Lo importante de esta sección: se abren sin volver a compilar.
          // Y las que se hayan quedado viejas lo dicen, porque un PDF que no
          // corresponde al fichero es peor que no tener ninguno.
          for (final output in existing)
            _ExistingCard(
              output: output,
              onView: onView,
              onOpen: onOpen,
              onReveal: onReveal,
              onRecompile: () => onRecompile(output),
              onDelete: () => onDelete(output),
            ),
          const SizedBox(height: 14),
        ],
        if (results.isNotEmpty) ...[
          const _Label('Esta compilación'),
          for (final result in results)
            _ResultCard(result: result, onOpen: onOpen, onReveal: onReveal),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Note(
              'Es una unidad sola, así que la numeración de apartados y las '
              'referencias cruzadas serán las del documento donde se use, no '
              'estas. Para verlas bien, compila el documento.',
            ),
          ),
        ],
      ],
    );
  }

  /// Borrar una se hace y ya está; borrar todas se pregunta.
  ///
  /// No porque sea grave --se rehace compilando-- sino porque el botón no
  /// dice cuántos ficheros se lleva, y un número en un diálogo cuesta menos
  /// que la sorpresa.
  Future<void> _confirmDeleteAll(BuildContext context, int count) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          count == 1
              ? 'Borrar la versión compilada'
              : 'Borrar las $count versiones compiladas',
        ),
        content: const Text(
          'Se borran los PDF y lo que LaTeX dejó al lado. No se toca ningún '
          'fichero del repositorio: se rehacen compilando otra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('delete-all-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (yes == true) onDeleteAll();
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 4, 2, 7),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: didactaMuted,
      ),
    ),
  );
}

/// Una versión que ya está en disco.
class _ExistingCard extends StatelessWidget {
  const _ExistingCard({
    required this.output,
    required this.onView,
    required this.onOpen,
    required this.onReveal,
    required this.onRecompile,
    required this.onDelete,
  });

  final ExistingOutput output;
  final ValueChanged<OpenPdf> onView;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onReveal;
  final VoidCallback onRecompile;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tone = output.stale ? didactaEx : didactaAccentDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: output.stale
                ? didactaEx.withValues(alpha: 0.55)
                : didactaRule,
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        child: Row(
          children: [
            Icon(
              output.stale
                  ? Icons.change_circle_outlined
                  : Icons.check_circle_outline,
              size: 17,
              color: tone,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${output.label} · ${output.language}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    output.stale
                        ? 'la unidad ha cambiado desde que se compiló'
                        : 'compilada ${describeWhen(output.modified)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: output.stale ? didactaEx : didactaMuted,
                      fontWeight: output.stale
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            // Abrir sin compilar, que es el punto de esta sección.
            FilledButton.icon(
              key: Key('open-${output.profile}-${output.language}'),
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: const Text('Abrir'),
              onPressed: () => onView(
                OpenPdf(
                  path: output.pdf,
                  profile: output.profile,
                  language: output.language,
                  pages: 0,
                  stale: output.stale,
                ),
              ),
            ),
            IconButton(
              key: Key('rebuild-${output.profile}-${output.language}'),
              tooltip: 'Volver a compilar esta versión',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 17),
              onPressed: onRecompile,
            ),
            IconButton(
              tooltip: 'Abrir en el visor del sistema',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new, size: 15),
              onPressed: () => onOpen(output.pdf),
            ),
            IconButton(
              tooltip: 'Ver en el Finder',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.folder_open_outlined, size: 15),
              onPressed: () => onReveal(output.pdf),
            ),
            IconButton(
              key: Key('delete-${output.profile}-${output.language}'),
              tooltip: 'Borrar este PDF. Se rehace compilando',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.onOpen,
    required this.onReveal,
  });

  final CompileOutput result;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onReveal;

  @override
  Widget build(BuildContext context) {
    final tone = result.ok ? didactaAccentDark : didactaTeacher;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: didactaRule),
          borderRadius: BorderRadius.circular(7),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 17,
                  color: tone,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${result.profile} · ${result.language}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (result.ok)
                  Text(
                    '${result.pages} '
                    '${result.pages == 1 ? 'página' : 'páginas'} · '
                    '${result.seconds.toStringAsFixed(1)} s',
                    style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                  ),
              ],
            ),
            if (result.ok && result.pdf != null) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Sin «ver aquí»: ya está abierto en su pestaña. Quedan
                  // los dos externos, que siguen haciendo falta: pantalla
                  // completa para pasar diapositivas de verdad, y el Finder
                  // para arrastrar el PDF a un correo.
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Visor del sistema'),
                    onPressed: () => onOpen(result.pdf!),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_outlined, size: 15),
                    label: const Text('Ver en el Finder'),
                    onPressed: () => onReveal(result.pdf!),
                  ),
                ],
              ),
            ],
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 9),
              for (final error in result.errors.take(6))
                _Line(text: error, tone: didactaTeacher),
              if (result.errors.length > 6)
                _Line(
                  text: '… y ${result.errors.length - 6} más',
                  tone: didactaMuted,
                ),
            ],
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 7),
              // Los avisos de Didacta son los accionables: «esta unidad no
              // tiene valenciano, he usado el castellano».
              for (final warning in result.warnings.take(4))
                _Line(text: warning, tone: didactaEx),
              if (result.warnings.length > 4)
                _Line(
                  text: '… y ${result.warnings.length - 4} avisos más',
                  tone: didactaMuted,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: SelectableText(
      text,
      style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: tone),
    ),
  );
}

class _NotReady extends StatelessWidget {
  const _NotReady({required this.problem});

  final String problem;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.build_outlined, size: 19, color: didactaMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Todavía no se puede compilar aquí',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(problem, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Ir a Ajustes'),
              onPressed: () => context.go(Routes.settings()),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.problem});

  final Object problem;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La compilación no se pudo lanzar',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            // Lo que dijo el proceso, tal cual: su mensaje suele ser lo más
            // útil que se le puede enseñar a alguien.
            SelectableText(
              '$problem',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    ),
  );
}
