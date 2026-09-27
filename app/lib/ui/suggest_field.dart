/// Una caja de texto que sugiere lo que ya existe mientras se escribe.
///
/// Para los metadatos de una lección: la categoría, el tema, las etiquetas y
/// los prerrequisitos. Con ↑ y ↓ se elige, con Intro se acepta, y lo escrito
/// que no existe va el primero de la lista, marcado como nuevo, para que
/// Intro lo deje tal cual en lugar de cambiarlo por lo más parecido.
library;

import 'package:flutter/material.dart';

import '../model/metadata_suggestions.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class SuggestField extends StatefulWidget {
  const SuggestField({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.onSelected,
    this.focusNode,
    this.enabled = true,
    this.hintText,
    this.style,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// Lo que se ofrece para lo escrito.
  final List<Suggestion> Function(String typed) suggestions;

  /// Al elegir una, con el ratón o con Intro.
  final ValueChanged<String> onSelected;

  final ValueChanged<String>? onChanged;
  final bool enabled;
  final String? hintText;
  final TextStyle? style;

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => RawAutocomplete<Suggestion>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (suggestion) => suggestion.value,
      optionsBuilder: (value) =>
          widget.enabled ? widget.suggestions(value.text) : const [],
      onSelected: (suggestion) => widget.onSelected(suggestion.value),
      fieldViewBuilder: (context, controller, focusNode, submit) => TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        style: widget.style ?? const TextStyle(fontSize: 13),
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
        onSubmitted: (_) => submit(),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          key: const Key('suggestions'),
          color: context.palette.card,
          elevation: 6,
          shadowColor: context.palette.shadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
            side: BorderSide(color: context.palette.rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 260,
              maxWidth: constraints.maxWidth.clamp(260, 640),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              children: [
                for (final (index, suggestion) in options.indexed)
                  _Option(
                    suggestion: suggestion,
                    chosen: AutocompleteHighlightedOption.of(context) == index,
                    onTap: () => onSelected(suggestion),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.suggestion,
    required this.chosen,
    required this.onTap,
  });

  final Suggestion suggestion;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail =
        suggestion.detail ??
        (suggestion.uses == 1
            ? tr('1 lección')
            : suggestion.uses > 1
            ? tr('{0} lecciones', [suggestion.uses])
            : null);
    return InkWell(
      key: Key('suggestion-${suggestion.value}'),
      onTap: onTap,
      child: Container(
        color: chosen ? context.palette.selected : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            if (suggestion.isNew) ...[
              Icon(Icons.add, size: 14, color: context.palette.accentDark),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                suggestion.value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
                  color: suggestion.isNew
                      ? context.palette.accentDark
                      : context.palette.ink,
                ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: 10),
              // Pegado a la derecha y con tope: el título de una lección, en
              // los prerrequisitos, puede ser largo.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
