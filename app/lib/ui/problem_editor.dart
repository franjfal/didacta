/// Un problema, en tres campos.
///
/// El fichero sigue siendo el mismo `.tex` con los mismos entornos --es lo
/// que hace que una fuente dé la hoja de clase, la de resultados y la del
/// profesor-- pero escribirlo deja de ser acordarse de `\begin{answer}`.
///
/// De los 429 ficheros de `problems/` del repositorio, ninguno usa `answer`.
/// El entorno lleva ahí desde el principio, documentado como «el resultado,
/// una línea», y no lo usa nadie: para usarlo hay que saber que existe. Un
/// campo con su nombre y su explicación debajo lo convierte en algo que se
/// rellena.
library;

import 'package:flutter/material.dart';

import '../model/problem_file.dart';
import '../model/tex_wrap.dart';
import 'tex_field.dart';
import 'tex_highlight.dart';
import 'tex_toolbar.dart';
import 'theme.dart';

class ProblemFields extends StatefulWidget {
  const ProblemFields({
    super.key,
    required this.text,
    required this.readOnly,
    required this.onChanged,
  });

  /// El fichero entero. Sigue siendo la fuente de la verdad: los campos son
  /// una vista de él, y guardar guarda esto.
  final String text;

  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  State<ProblemFields> createState() => _ProblemFieldsState();
}

class _ProblemFieldsState extends State<ProblemFields> {
  /// Cada campo pinta su LaTeX: dentro de un enunciado hay fórmulas, órdenes
  /// y entornos como en cualquier otro trozo del fichero.
  final Map<ProblemPart, TexEditingController> _fields = {
    for (final part in ProblemPart.values) part: TexEditingController(),
  };

  /// Un foco por campo, para que la barra sepa sobre cuál actuar.
  final Map<ProblemPart, FocusNode> _focus = {
    for (final part in ProblemPart.values) part: FocusNode(),
  };

  /// El campo que tiene el cursor. Se apunta al **ganar** el foco y no al
  /// perderlo: pulsar un botón de la barra se lo quita al campo, y apagarla
  /// por eso la dejaría inservible.
  ProblemPart _focused = ProblemPart.statement;

  /// Lo último que escribieron los campos, para no recargarlos con lo que
  /// ellos mismos acaban de producir: reescribir un controlador mientras se
  /// teclea manda el cursor al principio.
  String _ours = '';

  @override
  void initState() {
    super.initState();
    for (final entry in _focus.entries) {
      entry.value.addListener(() {
        if (!mounted || !entry.value.hasFocus || _focused == entry.key) return;
        setState(() => _focused = entry.key);
      });
    }
    _load(widget.text);
  }

  @override
  void didUpdateWidget(ProblemFields old) {
    super.didUpdateWidget(old);
    if (widget.text != old.text && widget.text != _ours) _load(widget.text);
  }

  void _load(String text) {
    final problem = ProblemFile(text);
    for (final part in ProblemPart.values) {
      _fields[part]!.text = problem.part(part);
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _write(ProblemPart part, String value) {
    final text = ProblemFile(widget.text).withPart(part, value);
    _ours = text;
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    final problem = ProblemFile(widget.text);
    if (!problem.shape.fits) {
      return _DoesNotFit(reason: problem.shape.reason!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // La misma barra que en todas partes, menos lo que aquí sería mentira:
        // envolver en `answer` el campo de la respuesta.
        TexToolbar(
          controller: _fields[_focused]!,
          focusNode: _focus[_focused],
          enabled: !widget.readOnly,
          without: const {TexWrapGroup.problem},
        ),
        Expanded(child: _list(problem)),
      ],
    );
  }

  Widget _list(ProblemFile problem) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 60),
      children: [
        for (final part in ProblemPart.values) ...[
          _Field(
            part: part,
            controller: _fields[part]!,
            focusNode: _focus[part]!,
            readOnly: widget.readOnly,
            // El enunciado es lo que más se escribe; los otros dos suelen
            // ser cortos, y darles el mismo alto de entrada haría una
            // pantalla de tres cajas iguales donde no hay tres cosas
            // iguales.
            minLines: part == ProblemPart.statement ? 6 : 2,
            onChanged: (value) => _write(part, value),
          ),
          const SizedBox(height: 16),
        ],
        if (problem.bare)
          const Note(
            'Este fichero es solo el enunciado, sin entornos. Al escribir un '
            'resultado o una solución se envuelve en `exercise`, que es lo '
            'que los numera y los encuadra.',
          ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.part,
    required this.controller,
    required this.focusNode,
    required this.readOnly,
    required this.minLines,
    required this.onChanged,
  });

  final ProblemPart part;
  final TexEditingController controller;
  final FocusNode focusNode;
  final bool readOnly;
  final int minLines;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            labelFor(part),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          // El entorno que va a salir en el fichero. No es un detalle de
          // implementación que haya que esconder: es lo que hace que quien
          // ya escribe LaTeX reconozca lo que está editando, y lo que
          // permite volver al texto sin sorpresas.
          Text(
            '\\begin{${environmentFor(part)}}',
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: didactaMuted,
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        hintFor(part),
        style: const TextStyle(fontSize: 11.5, color: didactaMuted),
      ),
      const SizedBox(height: 6),
      // La misma caja que en todas partes: el LaTeX coloreado y una columna
      // por cada entorno que envuelve a la línea. Dentro de un enunciado hay
      // fórmulas, listas y entornos como en cualquier otro trozo del fichero.
      Container(
        decoration: BoxDecoration(
          color: didactaCard,
          border: Border.all(color: didactaRule),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: TexField(
          key: Key('problem-${environmentFor(part)}'),
          controller: controller,
          focusNode: focusNode,
          readOnly: readOnly,
          minLines: minLines,
          onChanged: onChanged,
          padding: const EdgeInsets.all(10),
          hintText: switch (part) {
            ProblemPart.statement => 'Derivar \$f(x) = x^2\$.',
            ProblemPart.answer => '\$f\'(x) = 2x\$',
            ProblemPart.solution => 'Por la regla de la potencia…',
          },
        ),
      ),
    ],
  );
}

/// Cuando el fichero no son tres campos.
class _DoesNotFit extends StatelessWidget {
  const _DoesNotFit({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Este problema no son tres campos',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(reason, style: const TextStyle(fontSize: 13, height: 1.45)),
            const SizedBox(height: 12),
            const Note(
              'Se sigue editando como texto, con el botón de arriba. Los '
              'campos vuelven en cuanto el fichero tenga un solo problema.',
            ),
          ],
        ),
      ),
    ),
  );
}
