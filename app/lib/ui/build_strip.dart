/// Lo que se está compilando, abajo y en todas las pantallas.
///
/// Compilar un curso son treinta minutos, y hasta ahora solo se veía en la
/// ventana de la consola: al cerrarla, nada decía que seguía compilando, ni
/// por cuál iba, ni cómo pararlo. Esta tira lo dice desde cualquier pantalla
/// --«Compilando Análisis · 2025-2026 · 9/38»--, cuántas esperan detrás, y
/// tiene «Detener». Al acabar un lote, dice cómo fue --«36 bien, 2 con
/// errores»-- hasta que se cierra.
library;

import 'package:flutter/material.dart';

import '../state/build_console.dart';
import '../state/session.dart';
import 'build_console.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class BuildStrip extends StatefulWidget {
  const BuildStrip({super.key, required this.session});

  final Session session;

  @override
  State<BuildStrip> createState() => _BuildStripState();
}

class _BuildStripState extends State<BuildStrip> {
  /// Si se ha cerrado el resumen de la última. Una compilación nueva lo
  /// vuelve a enseñar.
  bool _dismissed = false;
  bool _wasRunning = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // La consola dice cómo va; la cola, cuántas esperan y si se está parando.
    listenable: Listenable.merge([
      widget.session.buildConsole,
      widget.session.builds,
    ]),
    builder: (context, _) {
      final console = widget.session.buildConsole;
      if (console.running && !_wasRunning) _dismissed = false;
      _wasRunning = console.running;
      final queued = widget.session.queuedBuilds;
      if (console.running) return _running(context, console, queued);
      if (!_dismissed && console.summary != null) {
        return _finished(context, console);
      }
      return const SizedBox.shrink();
    },
  );

  Widget _running(BuildContext context, BuildConsole console, int queued) {
    final count = console.total > 1
        ? ' · ${console.done}/${console.total}'
        : '';
    final waiting = queued == 0 ? '' : tr(' · {0} en cola', [queued]);
    return _Strip(
      key: const Key('build-strip'),
      leading: const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      text: tr('Compilando {0}{1}{2}', [console.title, count, waiting]),
      progress: console.total > 1 ? console.done / console.total : null,
      actions: [
        TextButton(
          key: const Key('build-strip-open'),
          onPressed: () => showBuildConsole(context, console),
          child: Text(tr('Ver')),
        ),
        TextButton(
          key: const Key('build-stop'),
          style: TextButton.styleFrom(foregroundColor: context.palette.teacher),
          onPressed: widget.session.stoppingBuild
              ? null
              : () => widget.session.stopBuilds(),
          child: Text(
            widget.session.stoppingBuild ? tr('Deteniendo…') : tr('Detener'),
          ),
        ),
      ],
    );
  }

  Widget _finished(BuildContext context, BuildConsole console) => _Strip(
    key: const Key('build-summary'),
    leading: Icon(
      console.ok ? Icons.check_circle_outline : Icons.error_outline,
      size: 15,
      color: console.ok ? context.palette.accentDark : context.palette.teacher,
    ),
    text: '${console.title}: ${console.summary}',
    actions: [
      TextButton(
        onPressed: () => showBuildConsole(context, console),
        child: Text(tr('Ver')),
      ),
      IconButton(
        key: const Key('build-summary-close'),
        tooltip: tr('Cerrar'),
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.close, size: 15, semanticLabel: tr('Cerrar')),
        onPressed: () => setState(() => _dismissed = true),
      ),
    ],
  );
}

class _Strip extends StatelessWidget {
  const _Strip({
    super.key,
    required this.leading,
    required this.text,
    required this.actions,
    this.progress,
  });

  final Widget leading;
  final String text;
  final List<Widget> actions;

  /// Cuánto va, de 0 a 1, en un lote.
  final double? progress;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.palette.panel,
      border: Border(top: BorderSide(color: context.palette.rule)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (progress != null)
          LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  key: const Key('build-strip-text'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ],
    ),
  );
}
