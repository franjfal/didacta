/// What needs translating, in the order worth doing it.
///
/// Ordered by how many documents use each unit, which is the whole point of
/// the screen. A library of 2147 units has more gaps than anyone will ever
/// close, so a flat alphabetical list of what is missing is not a work queue
/// — it is a reproach. Sorted by reuse it becomes one: translating a unit six
/// courses depend on buys six documents.
///
/// `outdated` is listed alongside `missing`, and that matters: a translation
/// whose original has moved on is *wrong*, not merely absent, and it will
/// compile happily while saying something out of date.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../model/catalogue.dart';
import '../router.dart';
import 'shell.dart';
import '../state/session.dart';
import 'theme.dart';
import 'translate_unit.dart';

class TranslationsPage extends StatefulWidget {
  const TranslationsPage({super.key});

  @override
  State<TranslationsPage> createState() => _TranslationsPageState();
}

class _TranslationsPageState extends State<TranslationsPage> {
  /// Lo marcado para traducir en tanda, por ruta.
  ///
  /// Por ruta y no por objeto: la lista se rehace en cada recarga del
  /// catálogo, y guardar las unidades dejaría marcadas copias viejas que ya
  /// no son las que se van a traducir.
  final Set<String> _picked = {};

  /// Qué clase de trabajo se está mirando.
  ///
  /// Una pestaña y no tres cuentas encendibles, porque son **tres trabajos
  /// distintos** y no tres etiquetas del mismo: traducir lo que no está,
  /// rehacer lo que quedó viejo, y leer lo que tradujo una máquina. Quien
  /// entra a despachar traducciones no quiere ver borradores en medio, y
  /// quien entra a revisar no quiere ver lo que no existe.
  ///
  /// Y porque así traducir algo **se nota**: la unidad desaparece de «sin
  /// traducir» y aparece en «sin revisar», que es exactamente lo que ha
  /// pasado.
  TranslationStatus? _tab;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final catalogue = session.catalogue;
    final language = session.language;
    final all = session.needingTranslation(language);

    // Las tres siempre, tengan o no algo.
    //
    // Antes solo salían las que tenían: con una sola clase de trabajo el
    // selector desaparecía, y entonces no había forma de saber si lo que
    // estabas viendo era lo que falta por traducir o lo que falta por
    // revisar. Un selector que se esconde deja de decir dónde estás, que es
    // la mitad de su trabajo. Vacías se ven apagadas y con un cero, que ya
    // dice que ahí no hay nada.
    const tabs = [
      TranslationStatus.outdated,
      TranslationStatus.missing,
      TranslationStatus.draft,
    ];
    // La que estaba, o la primera que tenga algo. Al traducir lo último que
    // faltaba, quedarse en «sin traducir» enseñando una lista vacía esconde
    // justo lo que acaba de pasar: que ahora está sin revisar.
    final counts = {
      for (final status in tabs)
        status: all.where((unit) => unit.statusIn(language) == status).length,
    };
    final tab =
        _tab ??
        tabs.firstWhere(
          (status) => counts[status]! > 0,
          orElse: () => TranslationStatus.missing,
        );
    final pending = [
      for (final unit in all)
        if (unit.statusIn(language) == tab) unit,
    ];

    return Column(
      children: [
        PageHeader(
          title: 'Traducción',
          subtitle: pending.length == all.length
              ? '${all.length} de ${catalogue.units.length} unidades '
                    'necesitan trabajo en $language'
              : '${pending.length} de ${all.length} que necesitan trabajo '
                    'en $language',
          bottom: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            // Desplazable en horizontal: los dos selectores con sus tres
            // trabajos y sus cuentas no caben en la ventana de un móvil, y
            // uno de ellos --el de trabajo-- no se puede partir, porque es
            // un control de tres segmentos pegados.
            //
            // Se desplaza en vez de acortarse: abreviar «Sin traducir» a
            // «Faltan» ahorra sitio y cuesta lo único que este selector
            // tiene que decir bien, que es qué clase de trabajo es cada uno.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Picker(
                    label: 'Idioma',
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: [
                        for (final option in session.languageChoices)
                          ButtonSegment(
                            value: option.code,
                            label: Text(option.code),
                          ),
                      ],
                      selected: {language},
                      onSelectionChanged: (values) =>
                          sessionOf(context).language = values.first,
                    ),
                  ),
                  // La clase de trabajo, con la misma forma y al lado del
                  // idioma: son la misma decisión partida en dos.
                  _Picker(
                    label: 'Trabajo',
                    child: SegmentedButton<TranslationStatus>(
                      key: const Key('work-picker'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: [
                        for (final status in tabs)
                          // Todos pulsables, también los que están a cero.
                          //
                          // Apagarlos los pintaba con el borde de «no
                          // disponible» --un gris casi blanco-- y el control
                          // entero dejaba de parecerse al de idiomas que
                          // tiene al lado. Y no era un clic perdido: entrar
                          // en «Sin traducir» y que conteste «nada
                          // pendiente» es una respuesta, no un callejón.
                          ButtonSegment(
                            value: status,
                            label: Text(
                              '${_tabName(status)} ${counts[status]}',
                            ),
                          ),
                      ],
                      selected: {tab},
                      onSelectionChanged: (values) => setState(() {
                        _tab = values.first;
                        // Lo marcado era del grupo anterior: llevárselo a otro
                        // es traducir lo que no se está mirando.
                        _picked.clear();
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (tab == TranslationStatus.outdated)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Note(
              'Su original ha cambiado desde que se tradujeron, así que '
              'dicen algo que ya no es cierto — y compilan sin queja. Por eso '
              'van primero.',
              tone: statusColour(TranslationStatus.outdated),
            ),
          ),
        // Lo marcado, y qué hacer con ello. Solo cuando hay algo: una barra
        // permanente que casi siempre dice «0 seleccionadas» es una fila de
        // pantalla gastada en no decir nada.
        if (_picked.isNotEmpty)
          _PickedBar(
            count: _picked.length,
            onClear: () => setState(_picked.clear),
            onAll: () => setState(() {
              _picked
                ..clear()
                ..addAll([
                  for (final unit in pending)
                    if (session.canWriteIn(unit.repo)) unit.path,
                ]);
            }),
            onTranslate: () => _translate(context, session, [
              for (final unit in pending)
                if (_picked.contains(unit.path)) unit,
            ]),
          ),
        Expanded(
          child: pending.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 32,
                          color: statusColour(TranslationStatus.reviewed),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nada pendiente en $language.',
                          style: const TextStyle(color: didactaMuted),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: pending.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final unit = pending[index];
                    return _PendingRow(
                      unit: unit,
                      language: language,
                      showDivider: false,
                      onTranslate: session.canWriteIn(unit.repo)
                          ? (it) => _translate(context, session, [it])
                          : null,
                      // Marcar para traducir en tanda. Solo donde se puede
                      // escribir: marcar algo que no se va a poder traducir
                      // es ofrecer un trabajo que no se puede hacer.
                      picked: _picked.contains(unit.path),
                      onPick: session.canWriteIn(unit.repo)
                          ? (on) => setState(() {
                              if (on) {
                                _picked.add(unit.path);
                              } else {
                                _picked.remove(unit.path);
                              }
                            })
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Cómo se llama cada pestaña: **qué trabajo es**, no cómo se llama el
  /// estado. «En borrador» no dice qué hay que hacer; «sin revisar», sí.
  static String _tabName(TranslationStatus status) => switch (status) {
    TranslationStatus.outdated => 'Desactualizadas',
    TranslationStatus.missing => 'Sin traducir',
    TranslationStatus.draft => 'Sin revisar',
    _ => statusName(status),
  };

  /// Traduce, con el mismo diálogo para una lección que para doscientas.
  ///
  /// El diálogo mira por su cuenta qué credenciales hay y qué idiomas faltan:
  /// preguntarlo aquí obligaría a leer el llavero para dibujar una lista de
  /// doscientas filas, y la respuesta es la misma para todas.
  Future<void> _translate(
    BuildContext context,
    Session session,
    List<Unit> units,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await translateWith(context, session: session, units: units);
    if (result == null || !mounted) return;
    setState(_picked.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${result.done} traducidos'
          '${result.failed > 0 ? ', ${result.failed} sin hacer' : ''}'
          '${result.warnings.isEmpty ? '' : ' — hay algo que mirar'}',
        ),
      ),
    );
  }
}

/// Un selector de la cabecera, con su etiqueta encima.
///
/// Los dos --el idioma y la clase de trabajo-- con la misma forma, porque
/// son la misma decisión partida en dos: qué estoy despachando. Enseñar uno
/// como botones y el otro como texto hacía que el segundo no pareciera
/// pulsable, que es exactamente lo que pasó.
class _Picker extends StatelessWidget {
  const _Picker({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$label:',
        style: const TextStyle(fontSize: 12, color: didactaMuted),
      ),
      const SizedBox(width: 8),
      child,
    ],
  );
}

/// Lo que se ha marcado, y qué se puede hacer con ello.
class _PickedBar extends StatelessWidget {
  const _PickedBar({
    required this.count,
    required this.onClear,
    required this.onAll,
    required this.onTranslate,
  });

  final int count;
  final VoidCallback onClear;
  final VoidCallback onAll;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      color: didactaPanel,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            count == 1 ? '1 lección marcada' : '$count lecciones marcadas',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          key: const Key('pick-all'),
          onPressed: onAll,
          child: const Text('Todas'),
        ),
        TextButton(
          key: const Key('pick-none'),
          onPressed: onClear,
          child: const Text('Ninguna'),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          key: const Key('translate-picked'),
          icon: const Icon(Icons.auto_awesome_outlined, size: 15),
          label: const Text('Traducir'),
          onPressed: onTranslate,
        ),
      ],
    ),
  );
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.unit,
    required this.language,
    required this.showDivider,
    this.onTranslate,
    this.picked = false,
    this.onPick,
  });

  final Unit unit;
  final String language;
  final bool showDivider;

  /// Traducir esta unidad. Null cuando no se puede escribir en su repositorio
  /// o cuando no hay ninguna credencial puesta.
  final void Function(Unit unit)? onTranslate;

  /// Si está marcada para traducir en tanda.
  final bool picked;

  /// Marcarla o desmarcarla. Null donde no se puede escribir: marcar algo que
  /// no se va a poder traducir es ofrecer un trabajo que no se puede hacer.
  final void Function(bool on)? onPick;

  @override
  Widget build(BuildContext context) {
    final status = unit.statusIn(language);
    final uses = unit.usedBy.length;

    return InkWell(
      onTap: () => context.go(Routes.unit(unit.path)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
        child: Row(
          children: [
            // La casilla, delante de todo: es lo primero que se busca cuando
            // se viene a despachar veinte de golpe.
            SizedBox(
              width: 32,
              child: Checkbox(
                key: Key('pick-${unit.path}'),
                visualDensity: VisualDensity.compact,
                value: picked,
                onChanged: onPick == null ? null : (on) => onPick!(on ?? false),
              ),
            ),
            // How many documents this unblocks. The reason for the ordering,
            // so it is the first thing in the row.
            SizedBox(
              width: 40,
              child: uses == 0
                  ? const Text(
                      '—',
                      style: TextStyle(fontSize: 12, color: didactaMuted),
                    )
                  : Row(
                      children: [
                        const Icon(Icons.link, size: 12, color: didactaMuted),
                        const SizedBox(width: 3),
                        Text(
                          '$uses',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
            ),
            Container(
              width: 3,
              height: 26,
              margin: const EdgeInsets.only(right: 9),
              decoration: BoxDecoration(
                color: kindColour(unit.kind),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit.title(unit.reference),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    unit.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: didactaMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusName(status),
              style: TextStyle(fontSize: 11, color: statusColour(status)),
            ),
            const SizedBox(width: 8),
            StatusBadge(
              language: unit.reference,
              status: unit.statusIn(unit.reference),
            ),
            // Traducir con la máquina. Aquí y no dentro de la unidad porque
            // esta es la lista de trabajo: se entra a despachar lo que falta,
            // no a leer cada fichero.
            if (onTranslate != null)
              IconButton(
                key: Key('translate-${unit.path}'),
                tooltip: 'Traducir a $language con la máquina',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                onPressed: () => onTranslate!(unit),
              ),
            const Icon(Icons.chevron_right, size: 18, color: didactaMuted),
          ],
        ),
      ),
    );
  }
}
