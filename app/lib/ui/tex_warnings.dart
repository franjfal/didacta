/// Los avisos de lo que va a romper la compilación, debajo del editor.
///
/// Con la línea pulsable: lleva el cursor allí. Sin avisos no ocupa nada --un
/// panel vacío que dice «todo bien» es un sitio más donde mirar-- y no
/// bloquea nada: guardar un fichero a medias es legítimo, y lo que se quiere
/// es saberlo antes de esperar treinta segundos a que LaTeX lo diga peor.
library;

import 'package:flutter/material.dart';

import '../model/formula_check.dart';
import '../model/tex_check.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class TexWarnings extends StatelessWidget {
  const TexWarnings({
    super.key,
    required this.controller,
    required this.language,
    required this.onGo,
    this.original,
  });

  /// El texto que se mira, que se vuelve a comprobar cada vez que cambia.
  final TextEditingController controller;

  /// El original, cuando lo que se mira es una traducción: sus fórmulas
  /// tienen que ser las mismas. Ver `model/formula_check.dart`.
  final TextEditingController? original;

  /// El de la pestaña: hay órdenes que solo existen en otro.
  final String language;

  /// Llevar el cursor a [offset].
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, ?original]),
    builder: (context, _) {
      final text = controller.text;
      final breaking = checkTex(text, language: language);
      // Con el original a medio cargar no se compara nada: un original vacío
      // haría que faltaran todas las fórmulas.
      final source = original?.text ?? '';
      final formulas = source.trim().isEmpty || text.trim().isEmpty
          ? const <TexWarning>[]
          : formulaWarnings(source, text);
      if (breaking.isEmpty && formulas.isEmpty) {
        return const SizedBox.shrink();
      }
      final warnings = [...breaking, ...formulas]
        ..sort((a, b) => a.offset.compareTo(b.offset));
      return _Panel(warnings: warnings, breaking: breaking.length, onGo: onGo);
    },
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.warnings,
    required this.breaking,
    required this.onGo,
  });

  final List<TexWarning> warnings;

  /// Cuántos de [warnings] rompen la compilación. Los demás son fórmulas
  /// que no coinciden con el original: compilan, y dicen otra cosa.
  final int breaking;
  final ValueChanged<int> onGo;

  /// Lo que dice la cabecera, según lo que haya.
  String get _title {
    final formulas = warnings.length - breaking;
    if (breaking == 0) {
      return formulas == 1
          ? tr('Una fórmula no coincide con el original')
          : tr('{0} fórmulas no coinciden con el original', [formulas]);
    }
    final base = breaking == 1
        ? tr('Esto no va a compilar')
        : tr('Esto no va a compilar · {0} avisos', [breaking]);
    if (formulas == 0) return base;
    return formulas == 1
        ? tr('{0} · y una fórmula distinta del original', [base])
        : tr('{0} · y {1} fórmulas distintas del original', [base, formulas]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('tex-warnings'),
      decoration: BoxDecoration(
        color: context.palette.panel,
        border: Border(top: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 15,
                color: context.palette.teacher,
              ),
              const SizedBox(width: 6),
              Text(
                _title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.palette.teacher,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Tres a la vista y el resto desplazándose: un fichero con una
          // llave de menos al principio puede dar veinte, y el editor sigue
          // siendo lo importante.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 84),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final (index, warning) in warnings.indexed)
                  _Row(
                    key: Key('tex-warning-$index'),
                    warning: warning,
                    onTap: () => onGo(warning.offset),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.warning, required this.onTap});

  final TexWarning warning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Hoverable(
    onTap: onTap,
    label: tr('Ir a la línea {0}: {1}', [warning.line, warning.message]),
    builder: (context, hovering) => Container(
      color: hovering ? context.palette.hover : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              tr('Línea {0}', [warning.line]),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.palette.accentDark,
                decoration: hovering ? TextDecoration.underline : null,
              ),
            ),
          ),
          Expanded(
            child: Text(warning.message, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    ),
  );
}
