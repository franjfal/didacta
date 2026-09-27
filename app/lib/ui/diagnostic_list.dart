/// Los errores de una compilación, cada uno con a dónde lleva.
///
/// «Lección Límites (es) · línea 42 · Undefined control sequence · \foo ·
/// [Abrir]». Antes era la ruta tal como la dice el log --relativa a la
/// carpeta de compilación, `../../../content/…`--, como mucho seis, y sin
/// forma de llegar a la línea más que buscarla a mano.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/compiler.dart';
import '../router.dart';
import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class DiagnosticList extends StatefulWidget {
  const DiagnosticList({
    super.key,
    required this.diagnostics,
    required this.session,
    this.shown = 6,
    this.onOpen,
  });

  final List<CompileDiagnostic> diagnostics;
  final Session session;

  /// Cuántos a la vista antes de «Ver todos».
  final int shown;

  /// Antes de ir a la lección: cerrar el diálogo en el que está la lista.
  final VoidCallback? onOpen;

  @override
  State<DiagnosticList> createState() => _DiagnosticListState();
}

class _DiagnosticListState extends State<DiagnosticList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.diagnostics;
    final visible = _all ? all : all.take(widget.shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final diagnostic in visible)
          _Row(
            diagnostic: diagnostic,
            session: widget.session,
            onOpen: widget.onOpen,
          ),
        if (all.length > visible.length)
          TextButton(
            key: const Key('diagnostics-all'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            onPressed: () => setState(() => _all = true),
            child: Text(tr('Ver los {0}', [all.length])),
          ),
      ],
    );
  }
}

/// Cómo se dice dónde está, con el título de la lección si se sabe.
String describeDiagnostic(CompileDiagnostic diagnostic, Session session) {
  final unit = diagnostic.unit == null
      ? null
      : session.unitByPath(diagnostic.unit!);
  final parts = <String>[
    if (unit != null)
      '«${unit.title(diagnostic.language ?? session.language)}» '
          '(${diagnostic.language})'
    else
      ?(diagnostic.path ?? diagnostic.file),
    if (diagnostic.line case final line?) tr('línea {0}', [line]),
    diagnostic.message,
    if (diagnostic.context case final context? when context.isNotEmpty) context,
  ];
  return parts.join(' · ');
}

class _Row extends StatelessWidget {
  const _Row({required this.diagnostic, required this.session, this.onOpen});

  final CompileDiagnostic diagnostic;
  final Session session;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final unit = diagnostic.unit == null
        ? null
        : session.unitByPath(diagnostic.unit!);
    // Lo que es solo para saber --«no hay diccionario de inglés»-- no se
    // pinta como un aviso: no hay nada que arreglar en el material.
    final tone = diagnostic.isError
        ? context.palette.teacher
        : diagnostic.severity == 'info'
        ? context.palette.muted
        : context.palette.ex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SelectableText(
              describeDiagnostic(diagnostic, session),
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: tone,
              ),
            ),
          ),
          if (unit != null)
            TextButton(
              key: Key('diagnostic-open-${unit.path}-${diagnostic.line}'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 22),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                // El router antes de cerrar nada: si la lista está en un
                // diálogo, al cerrarlo este contexto deja de valer.
                final router = GoRouter.maybeOf(context);
                final url = Routes.unit(
                  unit.path,
                  language: diagnostic.language,
                  line: diagnostic.line,
                );
                onOpen?.call();
                if (router != null) {
                  router.go(url);
                } else {
                  goTo(context, url);
                }
              },
              child: Text(
                tr('Abrir'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
