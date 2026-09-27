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
/// Las dos se manejan igual: lo que está son etiquetas, lo que falta está en
/// un desplegable con su botón de añadir, y quitar pregunta antes. Eran diez
/// chips marcados y sin marcar en una fila, y así no se leía de un vistazo
/// qué mantiene un repositorio: los siete que no traduce pesaban lo mismo que
/// los tres que sí, y los que no se podían quitar salían grises, como si no
/// estuvieran.
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
import '../l10n/tr.dart';

class LanguageSettings extends StatefulWidget {
  const LanguageSettings({super.key, required this.session});

  final Session session;

  @override
  State<LanguageSettings> createState() => _LanguageSettingsState();
}

class _LanguageSettingsState extends State<LanguageSettings> {
  /// El repositorio que se está escribiendo, para apagar sus controles
  /// mientras.
  String? _busy;

  /// Lo último que salió mal, tal cual. El caso corriente es haber intentado
  /// quitar un idioma en uso, y el mensaje trae la lista de asignaturas.
  String? _problem;

  Future<void> _writeRepo(String repo, Set<String> next) async {
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

  Future<void> _addToRepo(String repo, String code) async {
    final catalogue = widget.session.catalogueOrNull;
    if (catalogue == null) return;
    await _writeRepo(repo, {...catalogue.languagesOf(repo), code});
  }

  Future<void> _removeFromRepo(
    String repo,
    String label,
    LanguageOption option,
  ) async {
    final sure = await _confirmRemoval(
      context,
      title: tr('¿Quitar {0} de {1}?', [option.name, label]),
      body: tr(
        'Sale de la lista de su didacta.yaml, así que cambia para todo el '
        'que use este repositorio y se verá en el historial. Sus unidades dejan '
        'de pedir la traducción a {0}; no se borra ningún .tex, '
        'y lo que ya esté traducido vuelve a contar si lo añades otra vez.',
        [option.name],
      ),
      shared: true,
    );
    if (!sure || !mounted) return;
    final catalogue = widget.session.catalogueOrNull;
    if (catalogue == null) return;
    await _writeRepo(
      repo,
      {...catalogue.languagesOf(repo)}..remove(option.code),
    );
  }

  Future<void> _removeFromMine(LanguageOption option) async {
    final sure = await _confirmRemoval(
      context,
      title: tr('¿Dejar de trabajar con {0}?', [option.name]),
      body: tr(
        'Deja de ofrecerse en la barra de arriba, en los menús de compilar '
        'y en la ficha de una asignatura. Es solo para ti: no cambia ningún '
        'fichero, y lo recuperas desde aquí cuando quieras.',
      ),
      shared: false,
    );
    if (!sure || !mounted) return;
    await widget.session.setLanguageEnabled(option.code, false);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final catalogue = session.catalogue;
    final repos = session.workspace.repos;

    final inMaterial = session.namedLanguages(catalogue.languages);
    final mine = [
      for (final option in inMaterial)
        if (session.isLanguageEnabled(option.code)) option,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Heading(tr('Con los que trabajas')),
              Text(
                tr(
                  'De los que hay en el material, cuáles quieres que te ofrezca '
                  'la aplicación: la barra de arriba, los menús de compilar y '
                  'la ficha de una asignatura. Es solo para ti, viaja con tus '
                  'preferencias y no cambia ningún fichero. Un idioma quitado '
                  'sigue saliendo donde algo ya lo declara, para que guardar no '
                  'pueda borrarlo sin querer.',
                ),
                style: TextStyle(fontSize: 11.5, height: 1.45),
              ),
              const SizedBox(height: 8),
              if (catalogue.languages.isEmpty)
                Note(tr('Todavía no hay material del que sacar idiomas.'))
              else
                _LanguageTags(
                  keyPrefix: 'use-language',
                  chosen: mine,
                  available: [
                    for (final option in inMaterial)
                      if (!mine.contains(option)) option,
                  ],
                  // Apagar el último es volver a «todos», que en una fila de
                  // etiquetas se vería como que los quitados vuelven solos.
                  lockedBecause: (option) => mine.length == 1
                      ? tr(
                          'Es el único que queda: sin ninguno no habría '
                          'material que enseñar.',
                        )
                      : null,
                  complete: tr(
                    'Están todos: no hay filtro, se ofrece lo que haya.',
                  ),
                  onAdd: (code) => session.setLanguageEnabled(code, true),
                  onRemove: _removeFromMine,
                ),

              const SizedBox(height: 18),
              _Heading(tr('A los que traduce cada repositorio')),
              Text(
                tr(
                  'Esto sí es del material: está en su didacta.yaml, se ve en '
                  'el historial y lo lee todo el mundo. Añade lo que ese repositorio '
                  'mantiene de verdad — un idioma de más convierte la lista de '
                  'traducciones pendientes en ruido. Quitar uno no borra ningún '
                  '.tex: dejan de pedirse.',
                ),
                style: TextStyle(fontSize: 11.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              if (repos.isEmpty)
                Note(
                  tr(
                    'Sin repositorios abiertos no hay didacta.yaml que editar.',
                  ),
                )
              else
                for (final repo in repos)
                  _RepoLanguages(
                    key: Key('repo-languages-${repo.id}'),
                    id: repo.id,
                    label: repo.name,
                    colour: repo.colour,
                    known: catalogue.languageOptions,
                    mine: session.namedLanguages(
                      catalogue.languagesOf(repo.id),
                    ),
                    reference: catalogue.defaultLanguageOf(repo.id),
                    writable: session.canWriteIn(repo.id),
                    busy: _busy == repo.id,
                    usedBy: (code) => session.coursesUsing(repo.id, code),
                    language: session.language,
                    onAdd: (code) => _addToRepo(repo.id, code),
                    onRemove: (option) =>
                        _removeFromRepo(repo.id, repo.name, option),
                  ),

              if (_problem != null) ...[
                const SizedBox(height: 10),
                Note(_problem!, tone: context.palette.teacher),
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
    required this.onAdd,
    required this.onRemove,
  });

  final String id;
  final String label;
  final int colour;

  /// Los diez a los que Didacta sabe imprimir.
  final List<LanguageOption> known;

  /// Los que este repositorio mantiene, con su nombre.
  final List<LanguageOption> mine;

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

  final ValueChanged<String> onAdd;
  final ValueChanged<LanguageOption> onRemove;

  /// Por qué no se puede quitar, o `null` si se puede.
  ///
  /// El último no se quita, ni el de referencia, ni uno en el que se dé algo:
  /// los tres dejarían un repositorio que el motor no puede leer entero, y
  /// enterarse de eso al volver a indexar es enterarse tarde.
  String? _locked(LanguageOption option) {
    if (!writable) return tr('No se puede escribir en este repositorio.');
    if (option.code == reference) {
      return tr(
        'Es el idioma de referencia: el que se supone cuando nada dice '
        'otra cosa.',
      );
    }
    final used = usedBy(option.code);
    if (used.isNotEmpty) {
      return tr(
        'Se dan en {0}: '
        '{1}. '
        'Quítalo de sus fichas y luego de aquí.',
        [option.name, used.map((course) => course.title(language)).join(', ')],
      );
    }
    if (mine.length == 1) return tr('Es el único que le queda.');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final codes = {for (final option in mine) option.code};
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
                  color: context.palette.repo(colour),
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
                Text(
                  tr('solo lectura'),
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
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
          _LanguageTags(
            keyPrefix: 'repo-$id-language',
            chosen: mine,
            available: [
              for (final option in known)
                if (!codes.contains(option.code)) option,
            ],
            reference: reference,
            lockedBecause: _locked,
            enabled: !busy,
            canAdd: writable,
            complete: tr('Ya traduce a todos los que Didacta sabe imprimir.'),
            onAdd: onAdd,
            onRemove: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Una lista de idiomas como etiquetas, y un desplegable para añadir.
///
/// Solo se ve lo que está. Lo que falta se elige en el desplegable y entra
/// con su botón, y cada etiqueta que se puede quitar lleva una cruz pequeña.
/// La que no se puede, un candado, y al pasar por encima dice por qué: una
/// etiqueta sin cruz y sin explicación parece un fallo.
class _LanguageTags extends StatefulWidget {
  const _LanguageTags({
    required this.keyPrefix,
    required this.chosen,
    required this.available,
    required this.onAdd,
    required this.onRemove,
    this.lockedBecause,
    this.reference,
    this.enabled = true,
    this.canAdd = true,
    this.complete,
  });

  /// De donde salen las claves: `<prefijo>-<código>` para cada etiqueta,
  /// `<prefijo>-choice` para el desplegable y `<prefijo>-add` para el botón.
  final String keyPrefix;

  /// Los que están, en el orden en que se enseñan.
  final List<LanguageOption> chosen;

  /// Los que se pueden añadir.
  final List<LanguageOption> available;

  /// Por qué uno de [chosen] no se puede quitar, o `null` si se puede.
  final String? Function(LanguageOption option)? lockedBecause;

  /// El idioma que se señala como de referencia, si hay uno.
  final String? reference;

  /// Falso mientras se escribe: ni se quita ni se añade.
  final bool enabled;

  /// Falso donde no se puede escribir: sin desplegable.
  final bool canAdd;

  /// Lo que se dice cuando no queda nada que añadir.
  final String? complete;

  final ValueChanged<String> onAdd;
  final ValueChanged<LanguageOption> onRemove;

  @override
  State<_LanguageTags> createState() => _LanguageTagsState();
}

class _LanguageTagsState extends State<_LanguageTags> {
  /// El que está elegido en el desplegable y todavía no se ha añadido.
  String? _pick;

  void _add(String code) {
    setState(() => _pick = null);
    widget.onAdd(code);
  }

  @override
  Widget build(BuildContext context) {
    // Lo elegido puede haberse ido del desplegable --otra pantalla lo añadió,
    // o se volvió a indexar-- y un DropdownButton con un valor que no está
    // entre sus opciones no se pinta: se cae.
    final pick = widget.available.any((option) => option.code == _pick)
        ? _pick
        : null;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final option in widget.chosen) _tag(context, option),
        if (widget.canAdd && widget.available.isNotEmpty) ...[
          const SizedBox(width: 6),
          _choice(context, pick),
          OutlinedButton.icon(
            key: Key('${widget.keyPrefix}-add'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.add, size: 16),
            label: Text(tr('Añadir')),
            onPressed: pick == null || !widget.enabled
                ? null
                : () => _add(pick),
          ),
        ] else if (widget.canAdd && widget.complete != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              widget.complete!,
              style: TextStyle(fontSize: 11, color: context.palette.muted),
            ),
          ),
      ],
    );
  }

  /// Una etiqueta con la cara de un chip marcado, hecha a mano.
  ///
  /// No es un [InputChip] porque uno sin nada que hacer --el de referencia,
  /// el que está en uso-- se pinta desactivado, gris, y eso era justo lo que
  /// se veía mal: parecía que el idioma no estaba, cuando es el que más está.
  Widget _tag(BuildContext context, LanguageOption option) {
    final locked = widget.lockedBecause?.call(option);
    final isReference = option.code == widget.reference;
    final label = Theme.of(context).chipTheme.labelStyle;

    final tag = Container(
      key: Key('${widget.keyPrefix}-${option.code}'),
      height: 30,
      padding: EdgeInsets.only(left: 8, right: locked == null ? 3 : 9),
      decoration: BoxDecoration(
        color: context.palette.accentDark.withValues(alpha: 0.16),
        border: Border.all(color: context.palette.accentDark, width: 1.4),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 16, color: context.palette.accentDark),
          const SizedBox(width: 6),
          Text(option.name, style: label),
          if (isReference)
            Text(
              tr(' · referencia'),
              style: label?.copyWith(
                fontSize: 11,
                color: context.palette.muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          if (locked != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline, size: 13, color: context.palette.muted),
          ] else ...[
            const SizedBox(width: 2),
            IconButton(
              tooltip: tr('Quitar {0}', [option.name]),
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 22, height: 22),
              onPressed: widget.enabled ? () => widget.onRemove(option) : null,
            ),
          ],
        ],
      ),
    );

    return locked == null ? tag : Tooltip(message: locked, child: tag);
  }

  Widget _choice(BuildContext context, String? pick) {
    // Del tema y no un TextStyle suelto, para que herede su familia: el
    // `hint` se pinta con este estilo, y sin familia sale con la de caja.
    final text = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 12.5,
      color: context.palette.ink,
    );
    // Con ancho fijo: sin él mide lo que la opción más larga, y con «Deutsch»
    // o «Galego» el «Otro idioma…» de antes de elegir no cabe.
    return Container(
      width: 170,
      height: 32,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border.all(color: context.palette.rule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: Key('${widget.keyPrefix}-choice'),
          value: pick,
          isDense: true,
          isExpanded: true,
          hint: Text(
            tr('Otro idioma…'),
            style: text?.copyWith(color: context.palette.muted),
          ),
          style: text,
          borderRadius: BorderRadius.circular(Radii.control),
          items: [
            for (final option in widget.available)
              DropdownMenuItem(
                key: Key('${widget.keyPrefix}-choice-${option.code}'),
                value: option.code,
                child: Text(option.name),
              ),
          ],
          onChanged: widget.enabled
              ? (code) => setState(() => _pick = code)
              : null,
        ),
      ),
    );
  }
}

/// Pregunta antes de quitar un idioma. Contesta si se sigue adelante.
///
/// [shared] dice si lo que se quita es del material: entonces el botón va en
/// el color de lo que no se deshace con un clic, porque ya lo ve todo el que
/// use el repositorio.
Future<bool> _confirmRemoval(
  BuildContext context, {
  required String title,
  required String body,
  required bool shared,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: Text(body, style: const TextStyle(fontSize: 13, height: 1.45)),
      ),
      actions: [
        TextButton(
          key: const Key('remove-language-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('remove-language-confirm'),
          style: shared
              ? FilledButton.styleFrom(backgroundColor: context.palette.teacher)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Quitar')),
        ),
      ],
    ),
  );
  return answer ?? false;
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
