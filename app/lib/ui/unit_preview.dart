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
import 'theme.dart';

/// El estado de compilar una unidad.
///
/// No es un widget, y por la misma razón que `_LanguageEditor` tampoco lo es:
/// una pestaña de la que te vas tiene que conservar lo que había. Sin esto,
/// abrir el PDF en su pestaña y volver a «compilar» borraba los resultados y
/// obligaba a compilar otra vez -- que es justo lo que la pestaña venía a
/// evitar.
class PreviewState {
  PreviewState({
    required this.unit,
    required this.session,
    required this.onChanged,
    required this.onCompiled,
  }) {
    // El idioma de referencia, marcado de entrada. Los demás se añaden: se
    // compila `es` y `va` juntos para ver si la traducción cabe.
    languages.add(unit.reference);
    scheduleMicrotask(load);
  }

  final Unit unit;
  final Session session;
  final VoidCallback onChanged;

  /// Lo que acaba de compilar, para que la página lo abra.
  ///
  /// Automático y no a botones: acabas de pedir estas versiones, y quererlas
  /// ver es la única razón por la que las pediste.
  final ValueChanged<List<CompileOutput>> onCompiled;

  CompilerStatus? status;
  List<BuildableProfile> profiles = const [];
  final Set<String> chosen = {};

  /// Los idiomas elegidos. Varios: la comparación que importa es la del
  /// mismo perfil en dos idiomas.
  final Set<String> languages = {};

  bool loading = true;
  bool building = false;
  Object? problem;
  List<CompileOutput> results = const [];

  Future<void> load() async {
    final compiler = session.compiler();
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
          ? await compiler.profilesFor(unit.path)
          : const <BuildableProfile>[];
      status = found;
      profiles = available;
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

  /// Cuántas salidas produciría compilar ahora: perfiles por idiomas.
  int get outputCount => chosen.length * languages.length;

  Future<void> compile() async {
    final compiler = session.compiler();
    if (compiler == null || chosen.isEmpty || languages.isEmpty) return;
    building = true;
    problem = null;
    results = const [];
    onChanged();
    try {
      results = await compiler.compile(
        unitPath: unit.path,
        profiles: profiles
            .where((p) => chosen.contains(p.id))
            .map((p) => p.id)
            .toList(),
        // En el orden del catálogo y no del conjunto, para que `es` quede
        // siempre a la izquierda de `va`: comparar dos cosas que cambian de
        // lado entre compilaciones es peor que no compararlas.
        languages: [
          for (final code in session.catalogue.languages)
            if (languages.contains(code)) code,
        ],
      );
      onCompiled(results);
    } catch (error) {
      problem = error;
    } finally {
      building = false;
      onChanged();
    }
  }
}

class UnitPreview extends StatelessWidget {
  const UnitPreview({super.key, required this.state, required this.onExternal});

  final PreviewState state;

  /// El visor del sistema y el Finder.
  final void Function(String path, {required bool reveal}) onExternal;

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
          unit: state.unit,
          profiles: state.profiles,
          chosen: state.chosen,
          chosenLanguages: state.languages,
          languages: state.session.catalogue.languages,
          outputs: state.outputCount,
          building: state.building,
          onToggle: state.toggle,
          onLanguage: state.toggleLanguage,
          onCompile: state.chosen.isEmpty || state.building
              ? null
              : state.compile,
        ),
        Expanded(
          child: state.problem != null
              ? _Failure(problem: state.problem!)
              : _Results(
                  results: state.results,
                  building: state.building,
                  unit: state.unit,
                  onOpen: (path) => onExternal(path, reveal: false),
                  onReveal: (path) => onExternal(path, reveal: true),
                ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.unit,
    required this.profiles,
    required this.chosen,
    required this.chosenLanguages,
    required this.languages,
    required this.outputs,
    required this.building,
    required this.onToggle,
    required this.onLanguage,
    required this.onCompile,
  });

  final Unit unit;
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
              const Expanded(
                child: Text(
                  'Compilar esta unidad',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
                  label: Text(profile.label),
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
    required this.building,
    required this.unit,
    required this.onOpen,
    required this.onReveal,
  });

  final List<CompileOutput> results;
  final bool building;
  final Unit unit;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onReveal;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
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
                      : 'Elige las versiones y pulsa compilar.',
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
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
