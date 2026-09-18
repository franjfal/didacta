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
library;

import 'package:flutter/material.dart';

import '../data/translator_http.dart';
import '../model/catalogue.dart';
import '../model/translation.dart';
import '../model/translation_run.dart';
import '../router.dart';
import '../state/session.dart';
import 'theme.dart';

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

  int get done => written.length;
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

  @override
  State<TranslateDialog> createState() => _TranslateDialogState();
}

class _TranslateDialogState extends State<TranslateDialog> {
  final Map<TranslationProvider, Credentials> _ready = {};
  TranslationProvider? _provider;

  late final Set<String> _languages = {..._offered.map((e) => e.code)};

  bool _loading = true;
  bool _running = false;
  int _progressDone = 0;
  String _doing = '';
  String? _problem;
  BatchResult? _result;

  /// Qué idiomas tiene sentido ofrecer, y a cuántas lecciones les faltan.
  ///
  /// Solo los que le faltan **a algo**: ofrecer un idioma que ya tienen todas
  /// es un clic que no hace nada, y ofrecer el de referencia de una lección
  /// es lo que producía el «traducir de castellano a castellano».
  late final List<({String code, String name, int pending})> _offered = () {
    // Los idiomas **a los que este espacio de trabajo traduce**, no los diez
    // a los que Didacta sabe imprimir. Ofrecer el resto sería ofrecer un
    // fichero que el repositorio no espera, que el motor rechaza al indexar
    // y que nadie va a compilar nunca.
    final names = {
      for (final option in widget.session.catalogue.languageOptions)
        option.code: option.name,
    };
    final wanted = widget.only;
    final found = <({String code, String name, int pending})>[];
    for (final code in widget.session.languagesIn(null)) {
      if (wanted != null && !wanted.contains(code)) continue;
      final pending = _pendingIn(code).length;
      if (pending == 0) continue;
      found.add((code: code, name: names[code] ?? code, pending: pending));
    }
    return found;
  }();

  /// Las lecciones a las que les falta este idioma.
  ///
  /// Se salta la que ya lo tiene al día, y la que lo tiene **como referencia**:
  /// traducir algo a su propio idioma no es una operación.
  List<Unit> _pendingIn(String language) => [
    for (final unit in widget.units)
      if (unit.reference != language && unit.statusIn(language).needsWork) unit,
  ];

  List<TranslationJob> get _jobs => [
    for (final entry in _offered)
      if (_languages.contains(entry.code))
        for (final unit in _pendingIn(entry.code))
          TranslationJob(unit: unit, language: entry.code),
  ];

  @override
  void initState() {
    super.initState();
    _load();
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

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    return AlertDialog(
      title: Text(
        widget.units.length == 1
            ? 'Traducir «${widget.units.single.title(widget.units.single.reference)}»'
            : 'Traducir ${widget.units.length} lecciones',
      ),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Note('Mirando qué proveedores hay configurados…')
            else if (_ready.isEmpty)
              const Note(
                'No hay ninguna clave puesta. En Ajustes → Traducción '
                'automática se configuran Google o Azure.',
                tone: didactaEx,
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
                const Note('No falta ningún idioma aquí. Nada que traducir.')
              else ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'A qué idiomas les falta',
                        style: TextStyle(fontSize: 11.5, color: didactaMuted),
                      ),
                    ),
                    TextButton(
                      key: const Key('translate-toggle-all'),
                      onPressed: _running ? null : _toggleAll,
                      child: Text(
                        _languages.length == _offered.length
                            ? 'Ninguno'
                            : 'Todos',
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
                        label: Text('${entry.name} · ${entry.pending}'),
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
                if (_ready.length > 1) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Con qué',
                    style: TextStyle(fontSize: 11.5, color: didactaMuted),
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
                    child: Note(aviso, tone: didactaTeacher),
                  ),
                Note(
                  jobs.isEmpty
                      ? 'Marca algún idioma.'
                      : '${jobs.length} ficheros. Lo que salga se guarda como '
                            'borrador, así que sigue apareciendo en la lista '
                            'de lo que hay que revisar. Las fórmulas y las '
                            'claves de `\\label` no se traducen.',
                ),
              ],
            ],

            if (_problem != null) ...[
              const SizedBox(height: 10),
              Note(_problem!, tone: didactaEx),
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
                style: const TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(_result),
          child: Text(_result == null ? 'Cancelar' : 'Cerrar'),
        ),
        if (_result == null)
          FilledButton(
            key: const Key('translate-go'),
            onPressed: _running || _provider == null || jobs.isEmpty
                ? null
                : _run,
            child: Text(
              jobs.length == 1 ? 'Traducir' : 'Traducir ${jobs.length}',
            ),
          ),
      ],
    );
  }

  /// Los idiomas marcados que el proveedor no traduce tal cual.
  ///
  /// Hoy es uno: el valenciano, que ningún traductor automático distingue del
  /// catalán. Sale catalán central --«Qüestió» donde el valenciano dice
  /// «Questió»-- y hay que ajustarlo al revisar.
  List<String> get _approximations {
    final provider = _provider;
    if (provider == null) return const [];
    final names = {
      for (final option in widget.session.catalogue.languageOptions)
        option.code: option.name,
    };
    return [
      for (final code in _languages)
        if (approximationFor(provider, code) case final actual?)
          '${names[code] ?? code}: ${provider.label} no lo distingue de '
              '«$actual» y traducirá a ese. Sale una traducción cercana que '
              'hay que ajustar al revisar.',
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
      setState(() => _problem = 'Falta algo en la credencial del proveedor.');
      return;
    }

    setState(() {
      _running = true;
      _problem = null;
      _progressDone = 0;
    });

    var stats = const TranslationStats();
    final warnings = <String>[];
    final written = <TranslationJob>[];
    var failed = 0;

    for (final job in jobs) {
      if (!mounted) return;
      setState(
        () =>
            _doing = '${job.unit.title(job.unit.reference)} → ${job.language}',
      );
      try {
        final result = await widget.session.translateUnit(
          unit: job.unit,
          from: job.unit.reference,
          to: job.language,
          translator: translator,
        );
        stats = stats.plus(result.stats);
        warnings.addAll(result.warnings);
        written.add(job);
      } catch (error) {
        // Una que falla no para la tanda: las otras doscientas no tienen la
        // culpa, y quedarse a medias sin decir cuál falló es peor.
        failed += 1;
        warnings.add('${job.unit.path} → ${job.language}: $error');
      }
      if (mounted) setState(() => _progressDone += 1);
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _doing = '';
      _result = BatchResult(
        written: written,
        failed: failed,
        stats: stats,
        warnings: warnings,
      );
    });
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
          result.failed == 0
              ? '${result.done} fichero(s) traducidos y guardados como '
                    'borrador.'
              : '${result.done} traducidos, ${result.failed} sin hacer.',
          key: const Key('translate-summary'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: result.failed == 0 ? didactaAccentDark : didactaEx,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${stats.segments} párrafos · ${stats.reused} de la memoria · '
          '${stats.translated} traducidos · '
          '${stats.characters} caracteres mandados',
          style: const TextStyle(fontSize: 11.5, color: didactaMuted),
        ),
        if (result.written.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Para revisar y aprobar',
            style: TextStyle(fontSize: 11.5, color: didactaMuted),
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
          const Text(
            'Para mirar',
            style: TextStyle(fontSize: 11.5, color: didactaTeacher),
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
              color: didactaAccentDark,
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
          const Text(
            'Abrir',
            style: TextStyle(
              fontSize: 11.5,
              color: didactaAccentDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: didactaAccentDark),
        ],
      ),
    ),
  );
}
