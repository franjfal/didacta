/// La barra de entornos del editor.
///
/// Didacta tenía los canales —`\onlyslides`, `\onlynotes`, `\onlyteacher`— y
/// ninguna forma de aplicarlos que no fuera escribirlos: marcar un párrafo y
/// decir «esto no va al proyector» era teclear doce caracteres delante y una
/// llave detrás, sin equivocarse, en un fichero de otra persona.
///
/// Dos decisiones:
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

import '../model/tex_wrap.dart';
import 'theme.dart';

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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _EnvironmentMenu(
                    active: active,
                    compact: tight,
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
    required this.onSelected,
  });

  final Set<String> active;
  final bool compact;
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
        for (final group in _titles.keys) ...[
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
