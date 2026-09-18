/// El visor de un diff: dos columnas de números, un signo y el texto.
///
/// Estaba dentro del historial de una unidad, que es donde se escribió. Vive
/// aparte desde que hay una segunda pregunta que se contesta igual --qué
/// cambió entre dos versiones congeladas-- porque dos visores de diff con los
/// mismos verdes y distinto comportamiento es exactamente la clase de
/// duplicado que acaba divergiendo.
///
/// Lo que lee es lo que dice git. El diff no se calcula aquí: un commit puede
/// renombrar, puede venir de una fusión y puede tocar un binario, y eso no se
/// deduce comparando dos textos.
library;

import 'package:flutter/material.dart';

import '../model/file_history.dart';
import '../model/line_diff.dart';
import 'theme.dart';

/// Los verdes y los rojos de lo que cambió.
///
/// Claros a propósito: lo que tiene que leerse es el texto, y un fondo
/// saturado detrás de LaTeX en monoespaciada cansa a los diez segundos. El
/// margen va un punto más fuerte que la fila, que es lo que deja seguir la
/// columna de cambios sin leer línea a línea.
const Color diffAddedBack = Color(0xFFE9F6EC);
const Color diffAddedGutter = Color(0xFFCFEAD8);
const Color diffRemovedBack = Color(0xFFFBECEC);
const Color diffRemovedGutter = Color(0xFFF2D4D4);

/// Un fichero tal como quedó, con lo que cambió marcado dentro.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.diff, this.unchanged});

  final FileDiff? diff;

  /// El contenido cuando el commit no cambió nada y no hay diff.
  final String? unchanged;

  @override
  Widget build(BuildContext context) {
    final found = diff;
    if (found == null) {
      return const DiffPlaceholder(icon: Icons.difference_outlined, text: '');
    }
    if (found.isBinary) {
      return const DiffPlaceholder(
        icon: Icons.image_outlined,
        text:
            'Es un fichero binario: git no guarda sus líneas, así que no hay '
            'contenido que enseñar.',
      );
    }

    final lines = <DiffLine>[];
    // Delante de qué líneas hay un salto. Pidiendo el fichero entero git da un
    // solo trozo, así que esto normalmente está vacío; se dibuja igualmente
    // porque un commit de fusión sí puede llegar partido, y un texto al que le
    // faltan líneas en medio sin decirlo es un texto que miente.
    final gaps = <int>{};
    for (final hunk in found.hunks) {
      if (lines.isNotEmpty) gaps.add(lines.length);
      lines.addAll(hunk.lines);
    }
    final text = unchanged;
    if (lines.isEmpty && text != null) {
      // El commit no cambió el contenido --lo renombró, le cambió los
      // permisos--, así que todas las líneas son las que ya había.
      final all = text.split('\n');
      for (var i = 0; i < all.length; i += 1) {
        lines.add(
          DiffLine(ChangeKind.kept, all[i], oldLine: i + 1, newLine: i + 1),
        );
      }
    }

    if (lines.isEmpty) {
      return const DiffPlaceholder(
        icon: Icons.help_outline,
        text:
            'De esta versión no se puede sacar el contenido: en este commit '
            'el fichero todavía estaba en otro sitio o con otro nombre.',
      );
    }

    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 28),
        itemCount: lines.length,
        itemBuilder: (context, index) =>
            DiffRow(line: lines[index], gap: gaps.contains(index)),
      ),
    );
  }
}

/// Una línea del fichero: dos números, un signo y el texto.
class DiffRow extends StatelessWidget {
  const DiffRow({super.key, required this.line, this.gap = false});

  final DiffLine line;

  /// Si delante de esta línea el texto se corta.
  final bool gap;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color gutter, String sign) = switch (line.kind) {
      ChangeKind.added => (diffAddedBack, diffAddedGutter, '+'),
      ChangeKind.removed => (diffRemovedBack, diffRemovedGutter, '−'),
      ChangeKind.kept => (Colors.white, didactaPanel, ' '),
    };

    final row = Container(
      color: background,
      // `IntrinsicHeight` y no `CrossAxisAlignment.stretch`: estirar dentro de
      // una fila cuya altura la deciden sus propios hijos es circular, y
      // Flutter lo dice pidiendo una altura infinita. Con esto los márgenes
      // de números llegan hasta abajo también cuando la línea de LaTeX es
      // larga y se parte en dos, que es lo que se quería del estirado.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Gutter(number: line.oldLine, colour: gutter),
            _Gutter(number: line.newLine, colour: gutter),
            Container(
              width: 18,
              color: gutter,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                sign,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: didactaMuted,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 1.5, 8, 1.5),
                child: Text(
                  // Una línea vacía sigue siendo una línea: sin esto la fila se
                  // encoge y el texto se lee como si faltara algo.
                  line.text.isEmpty ? ' ' : line.text,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!gap) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 22,
          color: didactaPanel,
          alignment: Alignment.center,
          child: const Text(
            '⋯',
            style: TextStyle(fontSize: 12, color: didactaMuted),
          ),
        ),
        row,
      ],
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({required this.number, required this.colour});

  final int? number;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    color: colour,
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.fromLTRB(0, 1.5, 7, 1.5),
    child: Text(
      number?.toString() ?? '',
      style: const TextStyle(
        fontSize: 11,
        height: 1.45,
        fontFamily: 'monospace',
        color: didactaMuted,
      ),
    ),
  );
}

/// El hueco donde iría un diff: un icono y una frase que dice por qué no hay.
class DiffPlaceholder extends StatelessWidget {
  const DiffPlaceholder({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: didactaMuted),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: didactaMuted),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
