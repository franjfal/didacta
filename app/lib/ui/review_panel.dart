/// Revisar el material: lo que compila, o casi, y está mal.
///
/// Es `didacta check` con sus hallazgos a la vista: una orden del castellano
/// copiada en el valenciano, un entorno que no define nadie, una figura que
/// falta, un `\ref` que saldrá como «??», una diapositiva que se sale, una
/// traducción que se ha quedado atrás. Cada uno con su lección, su idioma, su
/// línea y **Abrir**, como los errores de compilar.
///
/// Se abre desde la biblioteca, para el repositorio entero, y antes de
/// exportar, para lo que se va a repartir: ahí es donde un «??» deja de ser
/// un detalle.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/compiler.dart';
import '../model/review.dart';
import '../state/session.dart';
import 'diagnostic_list.dart';
import 'theme.dart';
import '../data/diagnostics.dart';
import '../l10n/tr.dart';

/// Las comprobaciones de más que se han pedido, mientras dure la sesión: si
/// alguien quiere ver las fórmulas distintas, las quiere ver la vez
/// siguiente también.
final Set<String> _extra = {};

/// Revisar [repos] --o solo lo de [within]--, en un diálogo. Varios
/// repositorios se revisan uno detrás de otro y se enseñan juntos.
Future<void> showReview(
  BuildContext context,
  Session session, {
  List<String?> repos = const [null],
  List<String> within = const [],
  String? title,
}) => showDialog<bool>(
  context: context,
  builder: (_) => ReviewDialog(
    session: session,
    repos: repos,
    within: within,
    title: title,
  ),
);

/// Antes de exportar: si hay algo que mirar en lo que se va a repartir, se
/// enseña y se pregunta; si no, se sigue sin enseñar nada. Devuelve si se
/// exporta.
///
/// Si no se puede revisar --no hay motor, o falla--, se sigue: revisar ayuda
/// a exportar, pero no es quien decide si se puede.
Future<bool> reviewBeforeExport(
  BuildContext context,
  Session session, {
  String? repo,
  required List<String> within,
}) async {
  final compiler = session.compiler(repo: repo);
  if (compiler == null) return true;
  ReviewReport report;
  try {
    report = await compiler.review(within: within, extra: _extra.toList());
  } catch (caught, trace) {
    Diagnostics.instance.note('review_panel.reviewBeforeExport', caught, trace);
    return true;
  }
  if (report.clean || !context.mounted) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (_) => ReviewDialog(
      session: session,
      repos: [repo],
      within: within,
      title: tr('lo que se va a exportar'),
      forExport: true,
      initial: report,
    ),
  );
  return go ?? false;
}

class ReviewDialog extends StatefulWidget {
  const ReviewDialog({
    super.key,
    required this.session,
    this.repos = const [null],
    this.within = const [],
    this._title,
    this.forExport = false,
    this.initial,
  });

  final Session session;

  /// Los repositorios que se revisan; `null` es el primero.
  final List<String?> repos;
  final List<String> within;

  /// Qué se revisa: «el repositorio», «lo que se va a exportar».
  /// Qué se revisa, para el título: «el repositorio» si no se dice.
  String get title => _title ?? tr('el repositorio');
  final String? _title;

  /// Con «Exportar igualmente» y «Cancelar»: devuelve si se exporta.
  final bool forExport;

  /// Un informe ya hecho, para no revisar dos veces.
  final ReviewReport? initial;

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  ReviewReport? _report;
  Object? _problem;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _report = widget.initial;
    // Después de montarse: revisar empieza con un setState.
    if (_report == null) {
      _running = true;
      scheduleMicrotask(_run);
    }
  }

  Future<void> _run() async {
    final compilers = [
      for (final repo in widget.repos) ?widget.session.compiler(repo: repo),
    ];
    if (compilers.isEmpty) {
      setState(() {
        _running = false;
        _problem = tr('Revisar necesita el motor.');
      });
      return;
    }
    setState(() {
      _running = true;
      _problem = null;
    });
    try {
      final reports = [
        for (final compiler in compilers)
          await compiler.review(within: widget.within, extra: _extra.toList()),
      ];
      final report = ReviewReport(
        findings: [for (final report in reports) ...report.findings],
        titles: {for (final report in reports) ...report.titles},
        checks: reports.first.checks,
      );
      if (mounted) setState(() => _report = report);
    } on CompileException catch (error) {
      if (mounted) setState(() => _problem = error.message);
    } catch (error) {
      if (mounted) setState(() => _problem = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _toggle(String check) {
    setState(() {
      if (!_extra.remove(check)) _extra.add(check);
    });
    unawaited(_run());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final report = _report;
    return Dialog(
      key: const Key('review-dialog'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width * 0.72 > 960 ? 960 : size.width * 0.72,
        height: size.height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(report),
            Expanded(child: _body(report)),
            _footer(report),
          ],
        ),
      ),
    );
  }

  Widget _header(ReviewReport? report) => Container(
    decoration: BoxDecoration(
      color: context.palette.panel,
      border: Border(bottom: BorderSide(color: context.palette.rule)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 18,
              color: context.palette.accentDark,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Revisar {0}', [widget.title]),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_running)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (report != null)
              Text(
                _summary(report),
                key: const Key('review-summary'),
                style: TextStyle(
                  fontSize: 12,
                  color: report.errors > 0
                      ? context.palette.teacher
                      : context.palette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Text(
              tr('Además:'),
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
            for (final entry in optionalReviewChecks.entries.map(
              (entry) => MapEntry(entry.key, tr(entry.value)),
            ))
              FilterChip(
                key: Key('review-with-${entry.key}'),
                label: Text(entry.value, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                selected: _extra.contains(entry.key),
                onSelected: _running ? null : (_) => _toggle(entry.key),
              ),
          ],
        ),
      ],
    ),
  );

  static String _summary(ReviewReport report) {
    final parts = [
      if (report.errors > 0)
        report.errors == 1 ? tr('1 error') : tr('{0} errores', [report.errors]),
      if (report.warnings > 0)
        report.warnings == 1
            ? tr('1 aviso')
            : tr('{0} avisos', [report.warnings]),
    ];
    return parts.isEmpty ? tr('Todo en orden') : parts.join(' · ');
  }

  Widget _body(ReviewReport? report) {
    if (_problem != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Note('$_problem', tone: context.palette.teacher),
      );
    }
    if (report == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final groups = report.byCheck;
    if (groups.isEmpty) {
      return Center(
        key: const Key('review-clean'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 34, color: context.palette.accentDark),
            const SizedBox(height: 8),
            Text(
              tr('Nada que mirar.'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                'Ni órdenes de otro idioma, ni entornos sin definir, ni figuras '
                'que falten, ni referencias sin destino.',
              ),
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        for (final entry in groups.entries) ...[
          Row(
            children: [
              Text(
                report.titleOf(entry.key),
                key: Key('review-group-${entry.key}'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${entry.value.length}',
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          DiagnosticList(
            diagnostics: [for (final f in entry.value) _diagnostic(f)],
            session: widget.session,
            shown: 5,
            onOpen: () => Navigator.of(context).maybePop(false),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _footer(ReviewReport? report) => Container(
    decoration: BoxDecoration(
      color: context.palette.panel,
      border: Border(top: BorderSide(color: context.palette.rule)),
    ),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Row(
      children: [
        TextButton.icon(
          key: const Key('review-again'),
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(tr('Volver a revisar')),
          onPressed: _running ? null : _run,
        ),
        const Spacer(),
        if (widget.forExport) ...[
          TextButton(
            key: const Key('review-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancelar')),
          ),
          const SizedBox(width: 6),
          FilledButton(
            key: const Key('review-export'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Exportar igualmente')),
          ),
        ] else
          FilledButton(
            key: const Key('review-close'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cerrar')),
          ),
      ],
    ),
  );

  static CompileDiagnostic _diagnostic(ReviewFinding finding) =>
      CompileDiagnostic(
        severity: finding.severity,
        message: finding.message,
        path: finding.path,
        line: finding.line,
        unit: finding.unit,
        language: finding.language,
      );
}
