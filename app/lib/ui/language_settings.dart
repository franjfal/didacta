/// Los idiomas: los que mantiene cada repositorio y los que quiero ver.
///
/// Dos cosas distintas en una pantalla, y juntas a propósito, porque la
/// confusión entre ellas es justo lo que había que arreglar. Didacta sabe
/// imprimir en diez idiomas; un repositorio traduce a los que diga su
/// `didacta.yaml`; una asignatura se da en los que diga su `course.yaml`, que
/// tienen que estar entre los de su repositorio; y una persona trabaja con
/// los que le interesen, que pueden ser menos.
///
/// **Los tres primeros son del material y el cuarto es de quien mira.** Lo que
/// se escribe aquí arriba --el filtro-- va con las preferencias y no toca
/// ningún fichero del repositorio; lo de abajo escribe `didacta.yaml`, se ve
/// en el diff y lo lee todo el mundo. Que se distingan de un vistazo es el
/// motivo de que estén en la misma tarjeta y separadas.
///
/// Quitar un idioma del repositorio **no se deja** si alguna asignatura se da
/// en él. No es una cortesía: el motor rechaza un `course.yaml` que declare un
/// idioma que su repositorio no mantiene, y una asignatura rechazada
/// desaparece de la biblioteca con un error en una lista que nadie mira. Se
/// dice qué asignaturas lo usan y se quita de ellas primero.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../state/session.dart';
import 'theme.dart';

class LanguageSettings extends StatefulWidget {
  const LanguageSettings({super.key, required this.session});

  final Session session;

  @override
  State<LanguageSettings> createState() => _LanguageSettingsState();
}

class _LanguageSettingsState extends State<LanguageSettings> {
  /// El repositorio que se está escribiendo, para apagar sus chips mientras.
  String? _busy;

  /// Lo último que salió mal, tal cual. El caso corriente es haber intentado
  /// quitar un idioma en uso, y el mensaje trae la lista de asignaturas.
  String? _problem;

  Future<void> _toggleRepo(String repo, String code, bool on) async {
    final catalogue = widget.session.catalogueOrNull;
    if (catalogue == null) return;
    final next = <String>{...catalogue.languagesOf(repo)};
    if (on) {
      next.add(code);
    } else {
      next.remove(code);
    }
    setState(() {
      _busy = repo;
      _problem = null;
    });
    try {
      await widget.session.setRepoLanguages(
        repo: repo,
        languages: next.toList(),
      );
    } catch (error) {
      if (mounted) setState(() => _problem = '$error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final catalogue = session.catalogue;
    final repos = session.workspace.repos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Heading('Con los que trabajas'),
              const Text(
                'De los que hay en el material, cuáles quieres que te ofrezca '
                'la aplicación: la barra de arriba, los menús de compilar y '
                'la ficha de una asignatura. Es solo para ti, viaja con tus '
                'preferencias y no cambia ningún fichero. Un idioma apagado '
                'sigue saliendo donde algo ya lo declara, para que guardar no '
                'pueda quitarlo sin querer.',
                style: TextStyle(fontSize: 11.5, height: 1.45),
              ),
              const SizedBox(height: 8),
              if (catalogue.languages.isEmpty)
                const Note('Todavía no hay material del que sacar idiomas.')
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final option in session.namedLanguages(
                      catalogue.languages,
                    ))
                      FilterChip(
                        key: Key('use-language-${option.code}'),
                        label: Text(option.name),
                        selected: session.isLanguageEnabled(option.code),
                        onSelected: (on) =>
                            session.setLanguageEnabled(option.code, on),
                      ),
                  ],
                ),
              if (session.languageChoices.length ==
                  catalogue.languages.length) ...[
                const SizedBox(height: 6),
                const Text(
                  'Con todos marcados no hay filtro: se ofrece lo que haya.',
                  style: TextStyle(fontSize: 11, color: didactaMuted),
                ),
              ],

              const SizedBox(height: 18),
              const _Heading('A los que traduce cada repositorio'),
              const Text(
                'Esto sí es del material: está en su didacta.yaml, se ve en '
                'el diff y lo lee todo el mundo. Marca lo que ese repositorio '
                'mantiene de verdad — un idioma marcado de más convierte la '
                'lista de traducciones pendientes en ruido. Quitar uno no '
                'borra ningún .tex: dejan de pedirse.',
                style: TextStyle(fontSize: 11.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              if (repos.isEmpty)
                const Note(
                  'Sin repositorios abiertos no hay didacta.yaml que editar.',
                )
              else
                for (final repo in repos)
                  _RepoLanguages(
                    key: Key('repo-languages-${repo.id}'),
                    id: repo.id,
                    label: repo.name,
                    colour: repo.colour,
                    known: catalogue.languageOptions,
                    mine: catalogue.languagesOf(repo.id),
                    reference: catalogue.defaultLanguageOf(repo.id),
                    writable: session.canWriteIn(repo.id),
                    busy: _busy == repo.id,
                    usedBy: (code) => session.coursesUsing(repo.id, code),
                    language: session.language,
                    onChanged: (code, on) => _toggleRepo(repo.id, code, on),
                  ),

              if (_problem != null) ...[
                const SizedBox(height: 10),
                Note(_problem!, tone: didactaTeacher),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Los idiomas de un repositorio, con el de referencia señalado.
class _RepoLanguages extends StatelessWidget {
  const _RepoLanguages({
    super.key,
    required this.id,
    required this.label,
    required this.colour,
    required this.known,
    required this.mine,
    required this.reference,
    required this.writable,
    required this.busy,
    required this.usedBy,
    required this.language,
    required this.onChanged,
  });

  final String id;
  final String label;
  final int colour;

  /// Los diez a los que Didacta sabe imprimir.
  final List<LanguageOption> known;

  /// Los que este repositorio mantiene.
  final List<String> mine;

  /// El de referencia: el que se supone cuando nada dice otra cosa. No se
  /// puede quitar sin más --el motor no lee un fichero cuyo
  /// `default_language` no esté en la lista-- así que se señala y, si algún
  /// día sale, lo sustituye el primero que quede.
  final String reference;

  final bool writable;
  final bool busy;

  /// Qué asignaturas se dan en un idioma, para no dejar quitarlo.
  final List<Course> Function(String code) usedBy;

  /// En el que se está trabajando, para los títulos de las asignaturas.
  final String language;

  final void Function(String code, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(colour),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              if (!writable)
                const Text(
                  'solo lectura',
                  style: TextStyle(fontSize: 11, color: didactaMuted),
                ),
              if (busy)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final option in known)
                _chip(option, mine.contains(option.code)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(LanguageOption option, bool on) {
    final isReference = option.code == reference;
    final used = on ? usedBy(option.code) : const <Course>[];
    // El último no se quita, ni el de referencia, ni uno en el que se dé algo:
    // los tres dejarían un repositorio que el motor no puede leer entero, y
    // enterarse de eso al volver a indexar es enterarse tarde.
    final locked = on && (mine.length == 1 || isReference || used.isNotEmpty);

    final chip = FilterChip(
      key: Key('repo-$id-language-${option.code}'),
      label: Text(isReference ? '${option.name} ·' : option.name),
      selected: on,
      onSelected: !writable || busy || locked
          ? null
          : (value) => onChanged(option.code, value),
    );

    final why = !writable
        ? 'No se puede escribir en este repositorio.'
        : isReference && on
        ? 'Es el idioma de referencia: el que se supone cuando nada dice '
              'otra cosa.'
        : used.isNotEmpty
        ? 'Se dan en ${option.name}: '
              '${used.map((course) => course.title(language)).join(', ')}. '
              'Quítalo de sus fichas y luego de aquí.'
        : mine.length == 1 && on
        ? 'Es el único que le queda.'
        : option.name;

    return Tooltip(message: why, child: chip);
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
  );
}
