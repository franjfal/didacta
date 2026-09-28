/// Traducir con la máquina: una lección o doscientas.
///
/// El mismo diálogo para las cuatro formas de llegar --una fila de la lista de
/// traducciones, un puñado marcado, una pestaña de idioma vacía dentro de una
/// lección, o los huecos de un tema entero-- porque las cuatro preguntan lo
/// mismo: **a qué idiomas y con qué proveedor**. Cuatro diálogos que se
/// parecen acabarían comportándose distinto sin que nadie lo decidiera.
///
/// Los idiomas se eligen aquí y no se heredan de la barra de arriba. Eso era
/// el fallo que había: la interfaz se mira en castellano, así que el botón
/// ofrecía traducir de castellano a castellano. Lo que hace falta saber no es
/// qué idioma estás mirando sino **cuáles le faltan a esto**, que es una
/// pregunta sobre el material y no sobre quien lo mira.
///
/// Lo que salga se guarda como borrador: es una traducción que no ha leído
/// nadie, y marcarla de otra forma la sacaría de la lista de lo que queda por
/// revisar, que es justo donde tiene que estar.
///
/// **De salida solo se traduce lo que no tiene texto.** Un borrador puede
/// estar ya corregido a mano, y una desactualizada es una traducción revisada
/// a la que le falta un cambio: pasarles la máquina por encima tira ese
/// trabajo. Rehacerlas es una casilla aparte, que dice eso mismo. Y de los
/// idiomas se marca el que se está mirando, no todos los que falten: una
/// tanda a tres idiomas sin haberlo pedido son tres veces más borradores que
/// revisar.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/translator_http.dart';
import '../model/catalogue.dart';
import '../model/translation.dart';
import '../model/translation_run.dart';
import '../router.dart';
import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Lo que se va a traducir: una lección en un idioma.
class TranslationJob {
  const TranslationJob({required this.unit, required this.language});

  final Unit unit;
  final String language;
}

/// Lo que pasó con una tanda.
class BatchResult {
  const BatchResult({
    required this.written,
    required this.failed,
    required this.stats,
    required this.warnings,
    this.stopped = false,
    this.commits = 0,
  });

  /// Lo que se escribió, para poder ir a mirarlo.
  ///
  /// Es lo siguiente que se quiere hacer después de traducir: abrirlo, leerlo
  /// y decidir si vale. Sin esto hay que apuntar el nombre, irse a la
  /// biblioteca y buscarlo, que es justo el paso que convierte «lo reviso
  /// ahora» en «lo reviso otro día».
  final List<TranslationJob> written;

  final int failed;
  final TranslationStats stats;
  final List<String> warnings;

  /// Si se paró antes de acabar. Lo traducido hasta ahí está guardado.
  final bool stopped;

  /// En cuántos cambios se guardó el material: uno por repositorio.
  final int commits;

  int get done => written.length;
}

/// Lo que cobra cada proveedor por millón de caracteres, a tarifa y en
/// dólares: Google Cloud Translation y Azure AI Translator (S1).
///
/// Para dar un orden de magnitud antes de pulsar, no una factura: no cuenta
/// lo gratuito de cada mes ni los descuentos por volumen, y por eso se enseña
/// con la tarifa al lado.
const Map<TranslationProvider, double> pricePerMillion = {
  TranslationProvider.google: 20,
  TranslationProvider.azure: 10,
  TranslationProvider.apertium: 0,
};

/// «1.234.567», con el punto de millares del castellano.
String thousands(int value) {
  final digits = '$value';
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i += 1) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Abre el diálogo para estas lecciones. Null si se cancela.
///
/// [only] limita los idiomas que se ofrecen, para cuando se llega desde una
/// pestaña concreta --«traducir esta lección al valenciano»-- en vez de desde
/// una lista.
Future<BatchResult?> translateWith(
  BuildContext context, {
  required Session session,
  required List<Unit> units,
  List<String>? only,
}) => showDialog<BatchResult>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      TranslateDialog(session: session, units: units, only: only),
);

class TranslateDialog extends StatefulWidget {
  const TranslateDialog({
    super.key,
    required this.session,
    required this.units,
    this.only,
  });

  final Session session;
  final List<Unit> units;

  /// Solo estos idiomas, cuando se viene de un sitio que ya sabe cuál.
  final List<String>? only;

  /// Lo que la máquina puede hacer sin tirar el trabajo de nadie: no hay
  /// texto que perder.
  static bool isEmptyIn(Unit unit, String language) =>
      unit.statusIn(language) == TranslationStatus.missing;

  /// Lo que tiene texto y aun así está en la lista: borradores y
  /// desactualizadas. Traducirlas sustituye lo que tengan.
  static bool isRedoableIn(Unit unit, String language) {
    final status = unit.statusIn(language);
    return status == TranslationStatus.draft ||
        status == TranslationStatus.outdated;
  }

  @override
  State<TranslateDialog> createState() => _TranslateDialogState();
}

class _TranslateDialogState extends State<TranslateDialog> {
  final Map<TranslationProvider, Credentials> _ready = {};
  TranslationProvider? _provider;

  /// El que se está mirando, si falta; si no, el primero que falte.
  late final Set<String> _languages = {
    if (_offered.any((e) => e.code == widget.session.language))
      widget.session.language
    else if (_offered.isNotEmpty)
      _offered.first.code,
  };

  /// Si también se rehacen las que ya tienen texto.
  bool _redo = false;

  bool _loading = true;
  bool _running = false;

  /// Si se ha pulsado «Detener»: se para antes de la siguiente lección.
  bool _stopping = false;

  /// Lo que costaría lo marcado, y para qué lo marcado se calculó: se
  /// recalcula al cambiar los idiomas o la casilla de rehacer.
  TranslationEstimate? _estimate;
  String _estimated = '';
  int _progressDone = 0;
  String _doing = '';
  String? _problem;
  BatchResult? _result;

  /// Qué idiomas tiene sentido ofrecer, y a cuántas lecciones les faltan.
  ///
  /// Solo los que le faltan **a algo**: ofrecer un idioma que ya tienen todas
  /// es un clic que no hace nada, y ofrecer el de referencia de una lección
  /// es lo que producía el «traducir de castellano a castellano».
  late final List<({String code, String name, int empty, int redoable})>
  _offered = () {
    // Los idiomas **a los que este espacio de trabajo traduce**, no los diez
    // a los que Didacta sabe imprimir. Ofrecer el resto sería ofrecer un
    // fichero que el repositorio no espera, que el motor rechaza al indexar
    // y que nadie va a compilar nunca.
    final names = {
      for (final option in widget.session.catalogue.languageOptions)
        option.code: option.name,
    };
    final wanted = widget.only;
    final found = <({String code, String name, int empty, int redoable})>[];
    for (final code in widget.session.languagesIn(null)) {
      if (wanted != null && !wanted.contains(code)) continue;
      final empty = _candidates(code, TranslateDialog.isEmptyIn).length;
      final redoable = _candidates(code, TranslateDialog.isRedoableIn).length;
      if (empty + redoable == 0) continue;
      found.add((
        code: code,
        name: names[code] ?? code,
        empty: empty,
        redoable: redoable,
      ));
    }
    return found;
  }();

  /// Las lecciones de este idioma que cumplen [test].
  ///
  /// Nunca la que lo tiene **como referencia**: traducir algo a su propio
  /// idioma no es una operación.
  List<Unit> _candidates(String language, bool Function(Unit, String) test) => [
    for (final unit in widget.units)
      if (unit.reference != language && test(unit, language)) unit,
  ];

  /// Lo que se traduciría en este idioma: lo vacío, y lo que ya tiene texto
  /// solo si se ha pedido rehacerlo.
  List<Unit> _pendingIn(String language) => [
    ..._candidates(language, TranslateDialog.isEmptyIn),
    if (_redo) ..._candidates(language, TranslateDialog.isRedoableIn),
  ];

  /// Cuántas de los idiomas marcados ya tienen texto.
  int get _redoableMarked => [
    for (final entry in _offered)
      if (_languages.contains(entry.code)) entry.redoable,
  ].fold(0, (sum, count) => sum + count);

  List<TranslationJob> get _jobs => [
    for (final entry in _offered)
      if (_languages.contains(entry.code))
        for (final unit in _pendingIn(entry.code))
          TranslationJob(unit: unit, language: entry.code),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    for (final provider in TranslationProvider.values) {
      final credentials = await widget.session.translationSecrets.read(
        provider,
      );
      if (credentials.complete(provider)) _ready[provider] = credentials;
    }
    if (!mounted) return;
    setState(() {
      _provider = _ready.keys.firstOrNull;
      _loading = false;
    });
  }

  /// Qué se está estimando: los mismos trabajos dan la misma cuenta.
  String _keyOf(List<TranslationJob> jobs) =>
      [for (final job in jobs) '${job.unit.path}:${job.language}'].join('|');

  Future<void> _reestimate(List<TranslationJob> jobs) async {
    final key = _keyOf(jobs);
    if (key == _estimated) return;
    _estimated = key;
    final estimate = jobs.isEmpty
        ? const TranslationEstimate()
        : await widget.session.estimateTranslation([
            for (final job in jobs)
              (unit: job.unit, from: job.unit.reference, to: job.language),
          ]);
    if (!mounted || key != _estimated) return;
    setState(() => _estimate = estimate);
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    if (!_loading && !_running && _result == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reestimate(jobs));
    }
    return AlertDialog(
      title: Text(
        widget.units.length == 1
            ? tr('Traducir «{0}»', [
                widget.units.single.title(widget.units.single.reference),
              ])
            : tr('Traducir {0} lecciones', [widget.units.length]),
      ),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              Note(tr('Mirando qué proveedores hay configurados…'))
            else if (_ready.isEmpty)
              Note(
                tr(
                  'No hay ningún proveedor puesto. En Ajustes → Traducción '
                  'automática se configuran Google o Azure, o se enciende '
                  'Apertium, que es gratuito.',
                ),
                tone: context.palette.ex,
              )
            else if (_result != null)
              _Summary(
                result: _result!,
                onOpen: (job) {
                  // Cerrar antes de navegar: dejar el diálogo encima de la
                  // pantalla a la que se acaba de ir es una ventana que hay
                  // que apartar para ver lo que se venía a ver.
                  Navigator.of(context).pop(_result);
                  goTo(
                    context,
                    Routes.unit(job.unit.path, language: job.language),
                  );
                },
              )
            else ...[
              if (_offered.isEmpty)
                Note(tr('No falta ningún idioma aquí. Nada que traducir.'))
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('A qué idiomas les falta'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.palette.muted,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('translate-toggle-all'),
                      onPressed: _running ? null : _toggleAll,
                      child: Text(
                        _languages.length == _offered.length
                            ? tr('Ninguno')
                            : tr('Todos'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final entry in _offered)
                      FilterChip(
                        key: Key('translate-language-${entry.code}'),
                        label: Text(
                          '${entry.name} · '
                          '${entry.empty + (_redo ? entry.redoable : 0)}',
                        ),
                        selected: _languages.contains(entry.code),
                        onSelected: _running
                            ? null
                            : (on) => setState(() {
                                if (on) {
                                  _languages.add(entry.code);
                                } else {
                                  _languages.remove(entry.code);
                                }
                              }),
                      ),
                  ],
                ),
                // Solo si hay algo que rehacer en lo marcado: la casilla
                // sin nada detrás es una pregunta que no viene a cuento.
                if (_redoableMarked > 0 || _redo) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const Key('translate-redo'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: context.palette.teacher,
                    value: _redo,
                    onChanged: _running
                        ? null
                        : (on) => setState(() => _redo = on ?? false),
                    title: Text(
                      _redoableMarked == 1
                          ? tr('Rehacer también la que ya tiene texto')
                          : tr(
                              'Rehacer también las {0} que ya '
                              'tienen texto',
                              [_redoableMarked],
                            ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      tr(
                        'Borradores y desactualizadas. Se sustituye lo que '
                        'tengan, también lo que alguien haya corregido a mano.',
                      ),
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
                if (_ready.length > 1) ...[
                  const SizedBox(height: 14),
                  Text(
                    tr('Con qué'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<TranslationProvider>(
                    key: const Key('translate-provider'),
                    initialValue: _provider,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      for (final provider in _ready.keys)
                        DropdownMenuItem(
                          value: provider,
                          child: Text(provider.label),
                        ),
                    ],
                    onChanged: _running
                        ? null
                        : (value) => setState(() => _provider = value),
                  ),
                ],
                const SizedBox(height: 12),
                // Lo que el proveedor va a traducir de verdad, cuando no es
                // exactamente lo que se le pidió. Antes y no después: quien
                // revise el borrador tiene que saber qué está revisando.
                for (final aviso in _approximations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Note(aviso, tone: context.palette.teacher),
                  ),
                Note(
                  jobs.isEmpty
                      ? _languages.isEmpty
                            ? tr('Marca algún idioma.')
                            : tr(
                                'En lo marcado no hay nada sin texto. Para '
                                'pasar la máquina por lo que ya tiene, '
                                'marca «Rehacer».',
                              )
                      : tr(
                          '{0}. '
                          'Lo que salga se guarda como '
                          'borrador, así que sigue apareciendo en la lista '
                          'de lo que hay que revisar. Las fórmulas y las '
                          'claves de `\\label` no se traducen.',
                          [
                            jobs.length == 1
                                ? tr('1 fichero')
                                : tr('{0} ficheros', [jobs.length]),
                          ],
                        ),
                ),
                if (jobs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _EstimateLine(
                    estimate: _estimated == _keyOf(jobs) ? _estimate : null,
                    provider: _provider,
                  ),
                ],
              ],
            ],

            if (_problem != null) ...[
              const SizedBox(height: 10),
              Note(_problem!, tone: context.palette.ex),
            ],
            if (_running) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: jobs.isEmpty ? null : _progressDone / jobs.length,
              ),
              const SizedBox(height: 6),
              Text(
                _doing,
                key: const Key('translate-progress'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_running)
          TextButton(
            key: const Key('translate-stop'),
            onPressed: _stopping
                ? null
                : () => setState(() => _stopping = true),
            child: Text(_stopping ? tr('Parando…') : tr('Detener')),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(_result),
            child: Text(_result == null ? tr('Cancelar') : tr('Cerrar')),
          ),
        if (_result == null)
          FilledButton(
            key: const Key('translate-go'),
            onPressed: _running || _provider == null || jobs.isEmpty
                ? null
                : _run,
            child: Text(
              jobs.length == 1
                  ? tr('Traducir')
                  : tr('Traducir {0}', [jobs.length]),
            ),
          ),
      ],
    );
  }

  /// Los idiomas marcados que el proveedor no traduce tal cual.
  ///
  /// Hoy es uno: el valenciano, que ningún traductor automático distingue del
  /// catalán. Sale catalán central --«aquest» donde el valenciano dice
  /// «este», «durada» donde dice «duració»-- y hay que ajustarlo al revisar.
  List<String> get _approximations {
    final provider = _provider;
    if (provider == null) return const [];
    final names = {
      for (final option in widget.session.catalogue.languageOptions)
        option.code: option.name,
    };
    final sources = {for (final unit in widget.units) unit.reference};
    return [
      for (final code in _languages)
        if (approximationFor(provider, code) case final actual?)
          tr(
            '{0}: {1} no lo distingue de '
            '«{2}» y traducirá a ese. Sale una traducción cercana que '
            'hay que ajustar al revisar.',
            [names[code] ?? code, provider.label, actual],
          ),
      for (final code in _languages)
        for (final source in sources)
          if (source != code && !supportsPair(provider, source, code))
            tr(
              '{0} no traduce de «{1}» a '
              '«{2}»: esas se quedarán sin hacer. Elige '
              'otro proveedor para ellas.',
              [provider.label, names[source] ?? source, names[code] ?? code],
            ),
    ];
  }

  void _toggleAll() => setState(() {
    if (_languages.length == _offered.length) {
      _languages.clear();
    } else {
      _languages.addAll(_offered.map((e) => e.code));
    }
  });

  Future<void> _run() async {
    final jobs = _jobs;
    final translator = translatorFor(_provider!, _ready[_provider]!);
    if (translator == null) {
      setState(
        () => _problem = tr('Falta algo en la credencial del proveedor.'),
      );
      return;
    }

    setState(() {
      _running = true;
      _problem = null;
      _progressDone = 0;
    });

    _stopping = false;
    TranslationBatch batch;
    try {
      batch = await widget.session.translateUnits(
        tasks: [
          for (final job in jobs)
            (unit: job.unit, from: job.unit.reference, to: job.language),
        ],
        translator: translator,
        stop: () => _stopping || !mounted,
        onProgress: (done, task) {
          if (!mounted) return;
          setState(() {
            _progressDone = done;
            final next = done < jobs.length ? jobs[done] : null;
            _doing = next == null
                ? tr('Guardando…')
                : '${next.unit.title(next.unit.reference)} → ${next.language}';
          });
        },
      );
    } catch (error) {
      // Lo que falla aquí es guardar: la traducción no ha llegado al disco.
      if (!mounted) return;
      setState(() {
        _running = false;
        _doing = '';
        _problem = tr('No se ha podido guardar lo traducido: {0}', [error]);
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _doing = '';
      _result = BatchResult(
        written: [
          for (final task in batch.written)
            TranslationJob(unit: task.unit, language: task.to),
        ],
        failed: batch.failed.length,
        stats: batch.stats,
        warnings: [
          ...batch.warnings,
          for (final failure in batch.failed)
            '${failure.task.unit.path} → ${failure.task.to}: '
                '${failure.error}',
        ],
        stopped: batch.stopped,
        commits: batch.commits,
      );
    });
  }
}

/// Cuánto se va a mandar, y cuánto costaría, antes de pulsar.
class _EstimateLine extends StatelessWidget {
  const _EstimateLine({required this.estimate, required this.provider});

  final TranslationEstimate? estimate;
  final TranslationProvider? provider;

  @override
  Widget build(BuildContext context) {
    final found = estimate;
    final price = provider == null ? null : pricePerMillion[provider];
    final String text;
    if (found == null) {
      text = tr('Calculando cuánto hay que mandar…');
    } else if (found.characters == 0 && found.unreadable > 0) {
      text = found.files == 0
          ? tr('No se ha podido leer el original: no se sabe cuánto costaría.')
          : found.unreadable == 1
          ? tr('No se ha podido leer 1 original: la cuenta no está completa.')
          : tr(
              'No se ha podido leer {0} originales: la cuenta no está '
              'completa.',
              [found.unreadable],
            );
    } else if (found.characters == 0) {
      text = tr(
        'Todo sale de la memoria: no hay que mandar nada al proveedor, '
        'y no cuesta nada.',
      );
    } else {
      final cost = price == null || price == 0
          ? null
          : found.characters / 1e6 * price;
      text = [
        found.characters == 1
            ? tr('1 carácter que mandar')
            : tr('{0} caracteres que mandar', [thousands(found.characters)]),
        if (found.reused > 0)
          tr(
            '{0} de {1} '
            'párrafos salen de la memoria',
            [thousands(found.reused), thousands(found.segments)],
          ),
        if (cost != null)
          tr(
            '{0} a la tarifa de {1} '
            '({2} \$ el millón)',
            [_money(cost), provider!.label, price!.toStringAsFixed(0)],
          ),
        if (price == 0) tr('gratis con {0}', [provider!.label]),
        if (found.unreadable > 0)
          tr('{0} sin poder leer, que no están en la cuenta', [
            found.unreadable,
          ]),
      ].join(' · ');
    }
    return Row(
      key: const Key('translate-estimate'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.payments_outlined,
            size: 14,
            color: context.palette.muted,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: context.palette.muted,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  static String _money(double value) {
    if (value < 0.01) return tr('menos de un céntimo de dólar');
    return tr('unos {0} \$', [value.toStringAsFixed(2).replaceAll('.', ',')]);
  }
}

/// Qué pasó, con lo que hay que mirar.
class _Summary extends StatelessWidget {
  const _Summary({required this.result, required this.onOpen});

  final BatchResult result;

  /// Abrir uno de los ficheros escritos, en su idioma.
  final void Function(TranslationJob job) onOpen;

  @override
  Widget build(BuildContext context) {
    final stats = result.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            result.failed == 0
                ? result.done == 1
                      ? tr('1 fichero traducido y guardado como borrador')
                      : tr(
                          '{0} ficheros traducidos y guardados como borrador',
                          [result.done],
                        )
                : tr('{0} traducidos, {1} sin hacer', [
                    result.done,
                    result.failed,
                  ]),
            if (result.stopped) tr('parado antes de acabar'),
            if (result.commits > 1)
              tr('en {0} cambios, uno por repositorio', [result.commits]),
          ].join(' · '),
          key: const Key('translate-summary'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: result.failed == 0
                ? context.palette.accentDark
                : context.palette.ex,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            '{0} párrafos · {1} de la memoria · '
            '{2} traducidos · '
            '{3} caracteres mandados',
            [stats.segments, stats.reused, stats.translated, stats.characters],
          ),
          style: TextStyle(fontSize: 11.5, color: context.palette.muted),
        ),
        if (result.written.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            tr('Para revisar y aprobar'),
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
          ),
          const SizedBox(height: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final job in result.written)
                    _WrittenRow(job: job, onOpen: () => onOpen(job)),
                ],
              ),
            ),
          ),
        ],
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            tr('Para mirar'),
            style: TextStyle(fontSize: 11.5, color: context.palette.teacher),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final warning in result.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '· $warning',
                        style: const TextStyle(fontSize: 11.5, height: 1.35),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Un fichero recién escrito, con el enlace para ir a leerlo.
///
/// Abre la unidad **en el idioma que se acaba de escribir**, no en el que se
/// estuviera mirando: lo que hay que revisar es la traducción, y tener que
/// buscar la pestaña es el paso que sobra.
class _WrittenRow extends StatelessWidget {
  const _WrittenRow({required this.job, required this.onOpen});

  final TranslationJob job;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('open-${job.unit.path}-${job.language}'),
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 24,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: context.palette.accentDark,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.unit.title(job.unit.reference),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${job.unit.path}/${job.language}.tex',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tr('Abrir'),
            style: TextStyle(
              fontSize: 11.5,
              color: context.palette.accentDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 16,
            color: context.palette.accentDark,
          ),
        ],
      ),
    ),
  );
}
