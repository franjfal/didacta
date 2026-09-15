/// La barra de entornos del editor.
///
/// Didacta tenía los canales —`\onlyslides`, `\onlynotes`, `\onlyteacher`— y
/// ninguna forma de aplicarlos que no fuera escribirlos: marcar un párrafo y
/// decir «esto no va al proyector» era teclear doce caracteres delante y una
/// llave detrás, sin equivocarse, en un fichero de otra persona.
///
/// Dos decisiones:
///
/// **Lo que se usa escribiendo, a la vista; lo que se usa al empezar, en un
/// menú.** Los canales y el formato se aplican sobre lo que acabas de marcar,
/// así que son botones. Los entornos y los símbolos se buscan, así que son
/// menús: una barra con setenta símbolos a la vista no es una barra.
///
/// **Los canales se ven; el resto está en un menú.** Los paneles del editor
/// pueden ser tres columnas de 300 px, así que una barra con veinte botones
/// no cabe en ninguna. A la vista van los cuatro que contestan la pregunta
/// que más se hace —«¿esto dónde sale?»—; los teoremas y las partes de un
/// problema, que se escriben al empezar y no se cambian, van en un menú.
///
/// **Encendidos los que te rodean.** Los botones leen dónde está el cursor
/// con la misma lectura del texto que hace la envoltura, así que la barra
/// dice en qué estás metido sin tener que mirar arriba a buscar el `\begin`.
library;

import 'package:flutter/material.dart';

import '../model/tex_snippets.dart';
import '../model/tex_wrap.dart';
import 'theme.dart';

/// El icono de cada botón de formato.
const Map<String, IconData> _formatIcons = {
  'textbf': Icons.format_bold,
  'emph': Icons.format_italic,
  'texttt': Icons.code,
  'keyterm': Icons.abc,
  'hl': Icons.format_color_fill,
};

/// Qué icono lleva cada canal. Solo los canales: son los que se ven.
const Map<String, IconData> _channelIcons = {
  'onlyslides': Icons.slideshow_outlined,
  'onlynotes': Icons.menu_book_outlined,
  'onlyteacher': Icons.school_outlined,
  'onlystudent': Icons.person_outline,
};

/// El rótulo corto del botón. El largo —«Solo diapositivas»— se queda en el
/// tooltip y en el menú: cuatro botones con «Solo» delante repiten la misma
/// palabra cuatro veces y se comen el ancho que necesita el editor.
const Map<String, String> _channelLabels = {
  'onlyslides': 'Diapositivas',
  'onlynotes': 'Apuntes',
  'onlyteacher': 'Profesor',
  'onlystudent': 'Alumno',
};

/// De qué color se enciende cada canal.
///
/// Los mismos de `didacta-colours.sty`, para que un canal sea del mismo color
/// en la pantalla y en el PDF y no haya dos vocabularios que aprender.
const Map<String, Color> _channelColours = {
  'onlyslides': didactaAccentDark,
  'onlynotes': didactaThm,
  'onlyteacher': didactaTeacher,
  'onlystudent': didactaQues,
};

class TexToolbar extends StatelessWidget {
  const TexToolbar({
    super.key,
    required this.controller,
    required this.enabled,
    this.focusNode,
    this.without = const {},
  });

  final TextEditingController controller;

  /// Falso cuando no se puede escribir en el repositorio: la barra se ve
  /// apagada en lugar de desaparecer, porque desaparecer deja la pantalla
  /// distinta según quién mire y nadie sabe que existe.
  final bool enabled;

  /// A quién se le devuelve el foco después de tocar el texto. Sin esto, el
  /// cursor se queda en el botón y hay que volver a hacer clic en el editor
  /// para seguir escribiendo.
  final FocusNode? focusNode;

  /// Grupos que aquí no significan nada.
  ///
  /// La barra es la misma en todas partes --lo que se aprende una vez sirve en
  /// las tres pantallas-- salvo lo que sería mentira: sobre el campo
  /// «Respuesta» de un problema, un botón que envuelve en `answer` envolvería
  /// la respuesta dentro de otra respuesta.
  final Set<TexWrapGroup> without;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // Sin cursor no hay dónde aplicar nada. Apagado y no adivinando: con
        // el cursor en ningún sitio, envolver «el párrafo 0» es una edición
        // que nadie ha pedido.
        final ready = enabled && value.selection.isValid;
        final active = ready
            ? {
                for (final each in wrappersAt(
                  value.text,
                  value.selection.baseOffset,
                ))
                  each.id,
              }
            : const <String>{};

        return Container(
          decoration: const BoxDecoration(
            color: didactaPanel,
            border: Border(bottom: BorderSide(color: didactaRule)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Por debajo de esto los cuatro canales con rótulo no caben, y
              // un panel de un tercio de ventana está justo ahí.
              final tight = constraints.maxWidth < 620;
              return Row(
                children: [
                  // Los canales ceden el ancho y, si aun así no caben,
                  // ruedan. Una barra que desborda esconde sus propios
                  // botones, que es como se pierde media pantalla en una
                  // tableta.
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final wrapper in didactaWrappers.where(
                            (each) => each.group == TexWrapGroup.channel,
                          ))
                            _ChannelButton(
                              wrapper: wrapper,
                              on: active.contains(wrapper.id),
                              compact: tight,
                              onPressed: ready ? () => _apply(wrapper) : null,
                            ),
                          const _Separator(),
                          for (final wrapper in didactaWrappers.where(
                            (each) => each.group == TexWrapGroup.format,
                          ))
                            _FormatButton(
                              wrapper: wrapper,
                              on: active.contains(wrapper.id),
                              onPressed: ready ? () => _apply(wrapper) : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _PaletteButton(
                    id: 'math',
                    icon: Icons.functions,
                    label: 'Matemáticas',
                    palettes: const [texMathPalette],
                    compact: tight,
                    onPick: ready ? _insert : null,
                  ),
                  _PaletteButton(
                    id: 'symbols',
                    icon: Icons.emoji_symbols_outlined,
                    label: 'Símbolos',
                    palettes: texSymbolPalettes,
                    compact: tight,
                    onPick: ready ? _insert : null,
                  ),
                  _EnvironmentMenu(
                    active: active,
                    compact: tight,
                    without: without,
                    onSelected: ready ? _apply : null,
                  ),
                  _PauseButton(
                    compact: tight,
                    onPressed: ready ? _pause : null,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _apply(TexWrapper wrapper) {
    final selection = controller.selection;
    _write(
      toggleWrap(
        controller.text,
        selection.baseOffset,
        selection.extentOffset,
        wrapper,
      ),
    );
  }

  void _insert(TexSnippet snippet) {
    final selection = controller.selection;
    _write(
      insertAround(
        controller.text,
        selection.baseOffset,
        selection.extentOffset,
        snippet.before,
        snippet.after,
      ),
    );
  }

  void _pause() {
    final selection = controller.selection;
    _write(
      insertSnippet(
        controller.text,
        selection.baseOffset,
        selection.extentOffset,
        r'\dpause',
      ),
    );
  }

  void _write(TexEdit edit) {
    controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection(baseOffset: edit.start, extentOffset: edit.end),
    );
    focusNode?.requestFocus();
  }
}

/// Una raya entre dos grupos de botones.
class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: didactaRule,
  );
}

/// Negrita, cursiva y demás: icono solo, que son universales.
class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.wrapper,
    required this.on,
    required this.onPressed,
  });

  final TexWrapper wrapper;
  final bool on;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: Key('wrap-${wrapper.id}'),
    tooltip: on ? 'Quitar «${wrapper.label}»' : wrapper.label,
    visualDensity: VisualDensity.compact,
    style: on
        ? IconButton.styleFrom(
            backgroundColor: didactaAccentDark.withValues(alpha: 0.12),
          )
        : null,
    icon: Icon(
      _formatIcons[wrapper.id] ?? Icons.text_fields,
      size: 15,
      color: onPressed == null
          ? didactaMuted.withValues(alpha: 0.5)
          : (on ? didactaAccentDark : didactaMuted),
    ),
    onPressed: onPressed,
  );
}

/// Una paleta: una rejilla de cosas que se escriben al pulsarlas.
///
/// El rótulo de cada una es el glifo --se busca «≤», no «\leq»-- y lo que se
/// escribe es la orden de LaTeX, que es lo que va al fichero.
class _PaletteButton extends StatelessWidget {
  const _PaletteButton({
    required this.id,
    required this.icon,
    required this.label,
    required this.palettes,
    required this.compact,
    required this.onPick,
  });

  final String id;
  final IconData icon;
  final String label;
  final List<TexPalette> palettes;
  final bool compact;
  final ValueChanged<TexSnippet>? onPick;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, menu, child) => TextButton.icon(
        key: Key('palette-$id'),
        onPressed: onPick == null
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
        icon: Icon(
          icon,
          size: 15,
          color: onPick == null
              ? didactaMuted.withValues(alpha: 0.5)
              : didactaMuted,
        ),
        label: compact
            ? const SizedBox.shrink()
            : Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: onPick == null
                      ? didactaMuted.withValues(alpha: 0.5)
                      : didactaMuted,
                ),
              ),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: SizedBox(
            width: 330,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final palette in palettes) ...[
                  if (palettes.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        palette.name,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: didactaMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final snippet in palette.items)
                        _SnippetButton(snippet: snippet, onPick: onPick),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SnippetButton extends StatelessWidget {
  const _SnippetButton({required this.snippet, required this.onPick});

  final TexSnippet snippet;
  final ValueChanged<TexSnippet>? onPick;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: snippet.tooltip ?? '${snippet.before}${snippet.after}'.trim(),
    child: InkWell(
      key: Key('snippet-${snippet.label}'),
      onTap: onPick == null
          ? null
          : () {
              onPick!(snippet);
              // Cerrar la paleta al escribir: una fórmula se escribe símbolo
              // a símbolo, pero cada uno va a un sitio distinto del texto.
              MenuController.maybeOf(context)?.close();
            },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minWidth: 34, minHeight: 28),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border.all(color: didactaRule),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          snippet.label,
          style: const TextStyle(fontSize: 13, color: didactaInk),
        ),
      ),
    ),
  );
}

class _ChannelButton extends StatelessWidget {
  const _ChannelButton({
    required this.wrapper,
    required this.on,
    required this.compact,
    required this.onPressed,
  });

  final TexWrapper wrapper;
  final bool on;
  final bool compact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colour = _channelColours[wrapper.id] ?? didactaAccentDark;
    final icon = Icon(
      _channelIcons[wrapper.id],
      size: 15,
      color: onPressed == null
          ? didactaMuted.withValues(alpha: 0.5)
          : (on ? colour : didactaMuted),
    );
    // El mismo botón pone y quita, así que el rótulo tiene que decir cuál de
    // las dos cosas va a pasar.
    final tooltip = on ? 'Quitar «${wrapper.label}»' : wrapper.label;

    if (compact) {
      return IconButton(
        key: Key('wrap-${wrapper.id}'),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        style: on
            ? IconButton.styleFrom(
                backgroundColor: colour.withValues(alpha: 0.12),
              )
            : null,
        icon: icon,
        onPressed: onPressed,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      // Con rótulo también lleva tooltip: el rótulo dice el canal y el
      // tooltip dice qué va a pasar al pulsar, que con un interruptor no es
      // lo mismo.
      child: Tooltip(
        message: tooltip,
        child: TextButton.icon(
          key: Key('wrap-${wrapper.id}'),
          icon: icon,
          label: Text(
            _channelLabels[wrapper.id] ?? wrapper.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: onPressed == null
                  ? didactaMuted.withValues(alpha: 0.5)
                  : (on ? colour : didactaMuted),
            ),
          ),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: on ? colour.withValues(alpha: 0.12) : null,
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Todo lo demás: la diapositiva, las partes de un problema y los teoremas.
class _EnvironmentMenu extends StatelessWidget {
  const _EnvironmentMenu({
    required this.active,
    required this.compact,
    required this.without,
    required this.onSelected,
  });

  final Set<String> active;
  final bool compact;
  final Set<TexWrapGroup> without;
  final ValueChanged<TexWrapper>? onSelected;

  static const Map<TexWrapGroup, String> _titles = {
    TexWrapGroup.slide: 'Diapositiva',
    TexWrapGroup.problem: 'Problema',
    TexWrapGroup.theory: 'Teoría',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TexWrapper>(
      key: const Key('wrap-menu'),
      enabled: onSelected != null,
      tooltip: 'Envolver en un entorno',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final group in _titles.keys.where(
          (each) => !without.contains(each),
        )) ...[
          PopupMenuItem<TexWrapper>(
            enabled: false,
            height: 28,
            child: Text(
              _titles[group]!,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: didactaMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final wrapper in didactaWrappers.where(
            (each) => each.group == group,
          ))
            PopupMenuItem<TexWrapper>(
              key: Key('wrap-item-${wrapper.id}'),
              value: wrapper,
              height: 34,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: active.contains(wrapper.id)
                        ? const Icon(Icons.check, size: 14)
                        : null,
                  ),
                  Text(wrapper.label, style: const TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.data_object,
              size: 15,
              color: onSelected == null
                  ? didactaMuted.withValues(alpha: 0.5)
                  : didactaMuted,
            ),
            if (!compact) ...[
              const SizedBox(width: 5),
              Text(
                'Entorno',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: onSelected == null
                      ? didactaMuted.withValues(alpha: 0.5)
                      : didactaMuted,
                ),
              ),
            ],
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: onSelected == null
                  ? didactaMuted.withValues(alpha: 0.5)
                  : didactaMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        key: const Key('wrap-dpause'),
        tooltip: 'Pausa',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.more_horiz, size: 15),
        onPressed: onPressed,
      );
    }
    return TextButton.icon(
      key: const Key('wrap-dpause'),
      icon: const Icon(Icons.more_horiz, size: 15, color: didactaMuted),
      label: const Text(
        'Pausa',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: didactaMuted,
        ),
      ),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: onPressed,
    );
  }
}
