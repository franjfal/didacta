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
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../model/latex_snippets.dart';
import '../model/slug.dart';
import '../model/snippet_check.dart';
import '../model/tex_check.dart' show TexWarning, inMathAt;
import '../model/tex_snippets.dart';
import '../model/tex_wrap.dart';
import '../router.dart';
import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Los botones de formato de la interfaz esencial. Los demás --monoespaciada,
/// término, resaltado-- salen en la completa y, siempre, en el selector.
const Set<String> _essentialFormats = {'textbf', 'emph'};

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
Map<String, String> get _channelLabels => {
  'onlyslides': tr('Diapositivas'),
  'onlynotes': tr('Apuntes'),
  'onlyteacher': tr('Profesor'),
  'onlystudent': tr('Alumno'),
};

/// De qué color se enciende cada canal.
///
/// Los mismos de `didacta-colours.sty`, para que un canal sea del mismo color
/// en la pantalla y en el PDF y no haya dos vocabularios que aprender.
Map<String, Color> _channelColoursIn(DidactaPalette palette) => {
  'onlyslides': palette.accentDark,
  'onlynotes': palette.thm,
  'onlyteacher': palette.teacher,
  'onlystudent': palette.ques,
};

class TexToolbar extends StatelessWidget {
  const TexToolbar({
    super.key,
    required this.controller,
    required this.enabled,
    this.focusNode,
    this.without = const {},
    this.onTidy,
    this.repo,
  });

  final TextEditingController controller;

  /// De qué repositorio es el fichero: decide qué snippets se ofrecen.
  ///
  /// Cada repositorio declara los suyos, y ofrecer en uno el de otro es
  /// ofrecer algo que ahí no compila. Null --una pantalla que no lo sabe--
  /// ofrece los de serie, que compilan en todas partes.
  final String? repo;

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

  /// Ordena la sangría del fichero entero, ahora.
  ///
  /// Nulo donde no significa nada --el campo «Respuesta» de un problema, un
  /// fragmento de un tema-- porque sangrar es una operación sobre un fichero
  /// completo y ahí no hay uno. Existe porque lo normal es que el fichero ya
  /// estuviera escrito antes que esto: al guardar se ordena solo, pero nadie
  /// va a abrir y guardar dos mil unidades para verlas bien puestas.
  final VoidCallback? onTidy;

  /// La sesión, si la hay: una prueba de la barra sola no la monta.
  static Session? _sessionOf(BuildContext context) {
    try {
      return context.watch<Session>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _sessionOf(context);
    final offered = [
      for (final snippet in session?.snippetsIn(repo) ?? didactaSnippets)
        if (snippet.usable &&
            !without.contains(snippet.base?.group ?? TexWrapGroup.custom))
          snippet,
    ];
    // Lo que se reconoce para encender y quitar: lo de este repositorio y,
    // detrás, lo de Didacta aunque aquí no se ofrezca. Un `\onlyslides` del
    // material migrado se tiene que poder quitar aunque este repositorio lo
    // haya sacado de su barra.
    final recognised = [
      for (final snippet in offered) snippet.wrapper,
      for (final wrapper in didactaWrappers)
        if (!offered.any((snippet) => snippet.id == wrapper.id)) wrapper,
    ];
    final library = session?.snippetLibrary ?? const <SnippetEntry>[];
    // En la interfaz esencial, lo que se usa para corregir una errata: los
    // canales, negrita y cursiva, las paletas y los snippets. Sin sesión --una
    // prueba de la barra sola-- se ve entera.
    final complete = session?.completeInterface ?? true;
    final onBar = {
      for (final wrapper in didactaWrappers)
        if (wrapper.group == TexWrapGroup.channel ||
            (wrapper.group == TexWrapGroup.format &&
                (complete || _essentialFormats.contains(wrapper.id))))
          wrapper.id,
    };
    final here = session?.snippetsIn(repo) ?? didactaSnippets;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // Sin cursor no hay dónde aplicar nada. Apagado y no adivinando: con
        // el cursor en ningún sitio, envolver «el párrafo 0» es una edición
        // que nadie ha pedido.
        final ready = enabled && value.selection.isValid;
        final around = ready
            ? [
                for (final each in wrappersAt(
                  value.text,
                  value.selection.baseOffset,
                  among: recognised,
                ))
                  each.id,
              ]
            : const <String>[];
        final active = around.toSet();
        final warnings = library.isEmpty
            ? const <TexWarning>[]
            : checkSnippets(
                value.text,
                here: here,
                library: library,
                repoName: (id) => session?.workspace.byId(id)?.label ?? id,
              );

        return Container(
          decoration: BoxDecoration(
            color: context.palette.panel,
            border: Border(bottom: BorderSide(color: context.palette.rule)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Por debajo de esto los cuatro canales con rótulo no caben, y
              // un panel de un tercio de ventana está justo ahí.
              //
              // Subió de 620 a 760 al entrar «Sangrar» en el grupo de la
              // derecha: a 643 px la fila se salía diez píxeles, y una barra
              // que desborda esconde sus propios botones. Con los cinco
              // rótulos convertidos en iconos sobra sitio de sobra, y lo que
              // dice cada uno sigue estando en su tooltip.
              final tight = constraints.maxWidth < 760;
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
                            (each) =>
                                each.group == TexWrapGroup.format &&
                                (complete ||
                                    _essentialFormats.contains(each.id)),
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
                    label: tr('Matemáticas'),
                    palettes: const [texMathPalette],
                    compact: tight,
                    onPick: ready ? _insert : null,
                  ),
                  _PaletteButton(
                    id: 'symbols',
                    icon: Icons.emoji_symbols_outlined,
                    label: tr('Símbolos'),
                    palettes: texSymbolPalettes,
                    compact: tight,
                    onPick: ready ? _insert : null,
                  ),
                  _SnippetPicker(
                    snippets: offered,
                    onBar: onBar,
                    active: around,
                    compact: tight,
                    onSelected: ready ? _apply : null,
                    onManage: session == null
                        ? null
                        : () =>
                              context.go(Routes.settings(section: 'snippets')),
                  ),
                  if (complete)
                    _PauseButton(
                      compact: tight,
                      onPressed: ready ? _pause : null,
                    ),
                  // En el grupo fijo y no dentro de lo que rueda: ahí está
                  // siempre en el mismo sitio, y un botón que hay que buscar
                  // rodando la barra es un botón que no existe para quien no
                  // sabe que está.
                  if (complete && onTidy != null)
                    _TidyButton(
                      compact: tight,
                      // Sobre el fichero entero, así que no necesita cursor:
                      // el resto de la barra sí --sin saber dónde estás, no
                      // hay dónde envolver-- pero esto no envuelve nada.
                      onPressed: enabled ? onTidy : null,
                    ),
                  if (warnings.isNotEmpty)
                    _SnippetWarnings(
                      warnings: warnings,
                      compact: tight,
                      onGo: _goTo,
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
    final start = selection.start;
    final end = selection.end;
    if (snippet.opensMath || inMathAt(controller.text, start)) {
      _write(
        insertAround(
          controller.text,
          selection.baseOffset,
          selection.extentOffset,
          snippet.before,
          snippet.after,
        ),
      );
      return;
    }
    // Fuera de una fórmula, dentro de una nueva, con el cursor antes del
    // `$` que la cierra: lo siguiente que se pulse o se escriba sigue en la
    // fórmula. Un símbolo suelto no se come lo marcado --se escribe delante,
    // como hacía--; una estructura, como `\sqrt{}`, lo mete dentro.
    _write(
      snippet.wraps
          ? insertAround(
              controller.text,
              start,
              end,
              '\$${snippet.before}',
              '${snippet.after}\$',
            )
          : insertAround(
              controller.text,
              start,
              start,
              '\$${snippet.before}',
              r'$',
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

  /// Lleva el cursor a [offset], en el editor.
  void _goTo(int offset) {
    controller.selection = TextSelection.collapsed(
      offset: offset.clamp(0, controller.text.length),
    );
    focusNode?.requestFocus();
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
    color: context.palette.rule,
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
    tooltip: on ? tr('Quitar «{0}»', [wrapper.label]) : wrapper.label,
    visualDensity: VisualDensity.compact,
    style: on
        ? IconButton.styleFrom(
            backgroundColor: context.palette.accentDark.withValues(alpha: 0.12),
          )
        : null,
    icon: Icon(
      _formatIcons[wrapper.id] ?? Icons.text_fields,
      size: 15,
      color: onPressed == null
          ? context.palette.muted.withValues(alpha: 0.5)
          : (on ? context.palette.accentDark : context.palette.muted),
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
              ? context.palette.muted.withValues(alpha: 0.5)
              : context.palette.muted,
        ),
        label: compact
            ? const SizedBox.shrink()
            : Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: onPick == null
                      ? context.palette.muted.withValues(alpha: 0.5)
                      : context.palette.muted,
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
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: context.palette.muted,
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
          border: Border.all(color: context.palette.rule),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          snippet.label,
          style: TextStyle(fontSize: 13, color: context.palette.ink),
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
    final colour =
        _channelColoursIn(context.palette)[wrapper.id] ??
        context.palette.accentDark;
    final icon = Icon(
      _channelIcons[wrapper.id],
      size: 15,
      color: onPressed == null
          ? context.palette.muted.withValues(alpha: 0.5)
          : (on ? colour : context.palette.muted),
    );
    // El mismo botón pone y quita, así que el rótulo tiene que decir cuál de
    // las dos cosas va a pasar.
    final tooltip = on ? tr('Quitar «{0}»', [wrapper.label]) : wrapper.label;

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
                  ? context.palette.muted.withValues(alpha: 0.5)
                  : (on ? colour : context.palette.muted),
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

/// El selector de snippets: todo lo que no está a la vista, con buscador.
///
/// Era un menú con los treinta y tantos de Didacta en cuatro grupos, y con
/// los snippets de cada repositorio pueden ser muchos más: un menú que hay
/// que recorrer con la vista deja de servir en cuanto no cabe. Aquí se
/// escribe y se filtra --por el nombre, el entorno, la orden o los nombres
/// heredados--, con las flechas y la tecla Intro, sin soltar el teclado.
///
/// Arriba, lo que rodea al cursor, para quitarlo: es la mitad del trabajo de
/// la barra y no puede depender de acordarse de cómo se llamaba.
class _SnippetPicker extends StatefulWidget {
  const _SnippetPicker({
    required this.snippets,
    required this.onBar,
    required this.active,
    required this.compact,
    required this.onSelected,
    this.onManage,
  });

  /// Los que ofrece el repositorio del fichero, ya sin lo que aquí no
  /// significa nada.
  final List<LatexSnippet> snippets;

  /// Los que ya son un botón de la barra: no se repiten en la lista, salvo
  /// buscándolos.
  final Set<String> onBar;

  /// Los ids de los que rodean al cursor, de fuera adentro.
  final List<String> active;
  final bool compact;
  final ValueChanged<TexWrapper>? onSelected;

  /// Ir al gestor. Null donde no hay adónde ir.
  final VoidCallback? onManage;

  @override
  State<_SnippetPicker> createState() => _SnippetPickerState();
}

class _SnippetPickerState extends State<_SnippetPicker> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onSelected != null;
    final tint = enabled
        ? context.palette.muted
        : context.palette.muted.withValues(alpha: 0.5);
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(context.palette.card),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.card),
            side: BorderSide(color: context.palette.rule),
          ),
        ),
      ),
      menuChildren: [
        _PickerPanel(
          snippets: widget.snippets,
          onBar: widget.onBar,
          active: widget.active,
          onPick: (wrapper) {
            _menu.close();
            widget.onSelected?.call(wrapper);
          },
          onClose: _menu.close,
          onManage: widget.onManage == null
              ? null
              : () {
                  _menu.close();
                  widget.onManage!();
                },
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: tr('Envolver en un snippet, o quitar el que rodea al cursor'),
        child: InkWell(
          key: const Key('wrap-menu'),
          borderRadius: BorderRadius.circular(Radii.small),
          onTap: enabled
              ? () => menu.isOpen ? menu.close() : menu.open()
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.data_object, size: 15, color: tint),
                if (!widget.compact) ...[
                  const SizedBox(width: 5),
                  Text(
                    tr('Snippets'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: tint,
                    ),
                  ),
                ],
                Icon(Icons.arrow_drop_down, size: 16, color: tint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se abre: el buscador, lo que se puede quitar y la lista.
class _PickerPanel extends StatefulWidget {
  const _PickerPanel({
    required this.snippets,
    required this.onBar,
    required this.active,
    required this.onPick,
    required this.onClose,
    this.onManage,
  });

  final List<LatexSnippet> snippets;
  final Set<String> onBar;
  final List<String> active;
  final ValueChanged<TexWrapper> onPick;
  final VoidCallback onClose;
  final VoidCallback? onManage;

  @override
  State<_PickerPanel> createState() => _PickerPanelState();
}

/// Para buscar: sin tildes y sin mayúsculas, «teor» encuentra «Teoría».
String _folded(String text) => fold(text).toLowerCase();

class _PickerPanelState extends State<_PickerPanel> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Cuál está marcado para la tecla Intro: el índice en [_choices].
  int _cursor = 0;

  static const double _rowHeight = 34;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Lo que se ve, en orden: primero lo que se puede quitar, después lo que
  /// casa con lo escrito.
  List<({LatexSnippet snippet, bool remove})> get _choices {
    final words = _folded(_query.text).split(' ').where((w) => w.isNotEmpty);
    bool matches(LatexSnippet snippet) {
      final haystack = _folded(snippet.searchable);
      return words.every(haystack.contains);
    }

    final byId = {for (final snippet in widget.snippets) snippet.id: snippet};
    // Los que ya son un botón de la barra --los canales, el formato-- no se
    // repiten en la lista: empujaban lo demás fuera de la vista. Buscándolos
    // sí salen, porque quien escribe «diapositivas» no tiene por qué saber
    // que es el botón de al lado.
    final searching = words.isNotEmpty;
    bool listed(LatexSnippet snippet) =>
        searching || !widget.onBar.contains(snippet.id);
    return [
      // De dentro afuera: lo que se quiere quitar casi siempre es lo último
      // que se puso.
      for (final id in widget.active.reversed)
        if (byId[id] != null && matches(byId[id]!))
          (snippet: byId[id]!, remove: true),
      for (final snippet in widget.snippets)
        if (listed(snippet) && matches(snippet))
          (snippet: snippet, remove: false),
    ];
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final choices = _choices;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (choices.isEmpty) return KeyEventResult.handled;
      setState(() {
        final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
        _cursor = (_cursor + step) % choices.length;
        if (_cursor < 0) _cursor += choices.length;
      });
      _reveal();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (choices.isNotEmpty) {
        widget.onPick(
          choices[_cursor.clamp(0, choices.length - 1)].snippet.wrapper,
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Que el marcado se vea: la lista rueda para seguir a las flechas.
  void _reveal() {
    if (!_scroll.hasClients) return;
    // Aproximado: las cabeceras de grupo también ocupan, pero seguir al
    // cursor de cerca basta para no perderlo de vista.
    final target = _cursor * _rowHeight;
    final view = _scroll.position.viewportDimension;
    if (target < _scroll.offset) {
      _scroll.jumpTo(target);
    } else if (target + _rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(
        (target + _rowHeight - view).clamp(0, _scroll.position.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    final cursor = choices.isEmpty ? -1 : _cursor.clamp(0, choices.length - 1);
    final rows = <Widget>[];
    String? group;
    var removing = false;
    for (final (index, choice) in choices.indexed) {
      if (choice.remove && !removing) {
        removing = true;
        rows.add(_PickerHeader(tr('Quitar lo que rodea al cursor')));
      }
      if (!choice.remove && choice.snippet.group != group) {
        group = choice.snippet.group;
        rows.add(_PickerHeader(group));
      }
      rows.add(
        _PickerRow(
          key: Key(
            choice.remove
                ? 'unwrap-item-${choice.snippet.id}'
                : 'wrap-item-${choice.snippet.id}',
          ),
          snippet: choice.snippet,
          remove: choice.remove,
          on: widget.active.contains(choice.snippet.id),
          marked: index == cursor,
          height: _rowHeight,
          onTap: () => widget.onPick(choice.snippet.wrapper),
          onHover: () => setState(() => _cursor = index),
        ),
      );
    }

    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _key,
              child: TextField(
                key: const Key('snippet-search'),
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() => _cursor = 0),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('Buscar un snippet…'),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 16,
                    color: context.palette.muted,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: choices.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: Text(
                      widget.snippets.isEmpty
                          ? tr('Este repositorio no ofrece ningún snippet.')
                          : tr('Ningún snippet con «{0}».', [
                              _query.text.trim(),
                            ]),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.palette.muted,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 6),
                    // Una columna y no una lista perezosa: el menú mide el
                    // ancho de lo que lleva dentro, y una lista perezosa no
                    // se deja medir. Son unas decenas de filas.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    ),
                  ),
          ),
          if (widget.onManage != null) ...[
            Divider(height: 1, color: context.palette.rule),
            InkWell(
              key: const Key('manage-snippets'),
              onTap: widget.onManage,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune,
                      size: 14,
                      color: context.palette.accentDark,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tr('Gestionar los snippets…'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.palette.accentDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('↑ ↓ para elegir · Intro'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 3),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: context.palette.muted,
        letterSpacing: 0.6,
      ),
    ),
  );
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    super.key,
    required this.snippet,
    required this.remove,
    required this.on,
    required this.marked,
    required this.height,
    required this.onTap,
    required this.onHover,
  });

  final LatexSnippet snippet;

  /// Si pulsarla quita el snippet en lugar de ponerlo.
  final bool remove;

  /// Si el cursor está dentro de uno de estos.
  final bool on;

  /// Si es la que coge la tecla Intro.
  final bool marked;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final label = remove ? tr('Quitar «{0}»', [snippet.label]) : snippet.label;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color: marked ? context.palette.selected : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: remove
                      ? Icon(
                          Icons.remove_circle_outline,
                          size: 14,
                          color: context.palette.teacher,
                        )
                      : (on
                            ? Icon(
                                Icons.check,
                                size: 14,
                                color: context.palette.accentDark,
                              )
                            : null),
                ),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: marked ? FontWeight.w600 : FontWeight.w500,
                      color: remove
                          ? context.palette.teacher
                          : context.palette.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    snippet.opening,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: monoStyle.copyWith(
                      fontSize: 11,
                      color: context.palette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que un snippet ha dejado de cumplir, en la propia barra.
///
/// Aquí y no en el panel de avisos de debajo del editor porque la barra está
/// en las tres pantallas donde se escribe --la lección, el tema y los campos
/// de un problema-- y el panel solo en la primera. Al pulsar un aviso, el
/// cursor va a donde está.
class _SnippetWarnings extends StatelessWidget {
  const _SnippetWarnings({
    required this.warnings,
    required this.compact,
    required this.onGo,
  });

  final List<TexWarning> warnings;
  final bool compact;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final many = warnings.length;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      // El menú ya rueda solo: una lista dentro con su propio desplazamiento
      // se pelea con él por la barra de desplazamiento.
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, warning) in warnings.indexed)
                MenuItemButton(
                  key: Key('snippet-warning-$index'),
                  onPressed: () => onGo(warning.offset),
                  leadingIcon: Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: context.palette.teacher,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        tr('Línea {0}: {1}', [warning.line, warning.message]),
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: many == 1
            ? warnings.single.message
            : tr('{0} snippets que no van a salir bien', [many]),
        child: TextButton.icon(
          key: const Key('snippet-warnings'),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          icon: Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: context.palette.teacher,
          ),
          label: compact
              ? Text(
                  '$many',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.palette.teacher,
                  ),
                )
              : Text(
                  many == 1 ? tr('1 aviso') : tr('{0} avisos', [many]),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.palette.teacher,
                  ),
                ),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: context.palette.tint(
              context.palette.teacher,
              0.12,
            ),
          ),
        ),
      ),
    );
  }
}

/// «Ordenar»: ordena la sangría del fichero ahora, sin esperar a guardarlo.
///
/// Se llamaba «Beautify», en inglés y repetido en la barra de la lección.
///
/// No pide confirmación porque no hace falta: deja el cambio **sin guardar**,
/// a la vista, con «Descartar» al lado. Lo que hace es lo mismo que haría el
/// guardado, hecho antes para poder mirarlo.
class _TidyButton extends StatelessWidget {
  const _TidyButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        key: const Key('tidy-now'),
        tooltip: tr('Ordena la sangría de este fichero ahora'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.format_indent_increase, size: 15),
        onPressed: onPressed,
      );
    }
    return Tooltip(
      message: tr('Ordena la sangría de este fichero ahora'),
      child: TextButton.icon(
        key: const Key('tidy-now'),
        icon: Icon(
          Icons.format_indent_increase,
          size: 15,
          color: context.palette.muted,
        ),
        label: Text(
          tr('Ordenar'),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: context.palette.muted,
          ),
        ),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: onPressed,
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
        tooltip: tr('Pausa'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.more_horiz, size: 15),
        onPressed: onPressed,
      );
    }
    return TextButton.icon(
      key: const Key('wrap-dpause'),
      icon: Icon(Icons.more_horiz, size: 15, color: context.palette.muted),
      label: Text(
        tr('Pausa'),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: context.palette.muted,
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
