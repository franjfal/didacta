/// La pestaña de un editor, del visor de un PDF o de los metadatos.
///
/// En un fichero propio porque la usan dos pantallas: la de una unidad --sus
/// idiomas, su `unit.yaml`, sus PDF-- y la de un tema --su composición, su
/// compilación, sus PDF--. Son la misma pestaña haciendo el mismo trabajo, y
/// dos copias con el mismo aspecto se separan en el primer retoque.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class DidactaTab extends StatelessWidget {
  const DidactaTab({
    super.key,
    required this.label,
    required this.selected,
    required this.dirty,
    required this.onTap,
    this.status,
    this.icon,
    this.iconColour,
    this.tooltip,
    this.onClose,
  });

  final String label;

  /// Para una pestaña que no es un idioma: dice que hace algo, en lugar de
  /// que muestra algo.
  final IconData? icon;

  /// Para el aviso de que lo compilado se ha quedado viejo.
  final Color? iconColour;

  /// Lo que dice al pasar por encima, cuando hay algo que decir.
  final String? tooltip;

  /// Puesto en una pestaña que se puede cerrar, que son las de PDF. Los
  /// idiomas y `unit.yaml` no se cierran: son la unidad.
  final VoidCallback? onClose;

  /// Null for the metadata tab, which has no translation state.
  final TranslationStatus? status;
  final bool selected;
  final bool dirty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = status;
    final tab = _build(context, state);
    return tooltip == null ? tab : Tooltip(message: tooltip!, child: tab);
  }

  Widget _build(BuildContext context, TranslationStatus? state) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          // La pestaña activa, además del subrayado, con el fondo de la
          // página: así se lee como la hoja que está delante y no como un
          // botón más de una fila de botones.
          color: selected
              ? context.palette.card
              : (hovering ? context.palette.hover : Colors.transparent),
          border: Border(
            bottom: BorderSide(
              color: selected ? context.palette.accentDark : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color:
                    iconColour ??
                    (selected
                        ? context.palette.accentDark
                        : context.palette.muted),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                // Un idioma que no existe, en rojo. Aquí sí y en la
                // biblioteca no: allí «falta» es el estado de dos tercios de
                // las dos mil unidades y pintarlo de rojo sería una pantalla
                // roja que nadie mira; aquí es *esta* unidad, y es lo que hay
                // que ir a arreglar.
                color: state != null && !state.exists
                    ? context.palette.teacher
                    : (selected ? context.palette.ink : context.palette.muted),
              ),
            ),
            if (state != null) ...[
              const SizedBox(width: 6),
              // El estado, también con palabras: el color solo no lo lee un
              // lector de pantalla, ni quien no distingue el verde del azul.
              Tooltip(
                message: state.exists ? statusName(state) : tr('no existe'),
                child: Semantics(
                  label: tr('estado: {0}', [
                    state.exists ? statusName(state) : tr('no existe'),
                  ]),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: state.exists
                          ? context.palette.status(state)
                          : Colors.transparent,
                      border: Border.all(
                        color: state.exists
                            ? context.palette.status(state)
                            : context.palette.teacher,
                        width: state.exists ? 1 : 1.4,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
            if (dirty) ...[
              const SizedBox(width: 4),
              // A dot rather than a word: it has to survive in a 38-pixel tab
              // and "sin guardar" is already spelled out in the editor bar.
              Icon(
                Icons.circle,
                size: 6,
                color: context.palette.ex,
                semanticLabel: tr('sin guardar'),
              ),
            ],
            if (onClose != null) ...[
              const SizedBox(width: 4),
              // Con una etiqueta que diga qué cierra, y el blanco más grande
              // que cabe en la pestaña: una cruz de dieciséis píxeles cuesta
              // acertarla.
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: context.palette.muted,
                    semanticLabel: tr('Cerrar la pestaña'),
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
