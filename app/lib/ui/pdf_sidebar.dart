/// El lateral de un PDF: por dónde va y a dónde se salta.
///
/// Un tema son sesenta unidades y ciento veinte páginas, y con la rueda del
/// ratón como única forma de moverse, «vamos al apartado de logaritmos» son
/// treinta segundos de arrastrar. Este lateral es lo que convierte el visor
/// en algo con lo que se puede dar una clase.
///
/// **Dos vistas, y el índice antes que las páginas.** El índice es el que
/// contesta la pregunta que se hace de verdad --a qué apartado ir-- y las
/// miniaturas contestan la otra, la de reconocer una página por su forma:
/// la diapositiva con la figura, la hoja que se quedó casi vacía. Un
/// documento sin marcadores no tiene índice que enseñar, así que entonces
/// no se ofrece la pestaña: un botón que lleva a una lista vacía es peor que
/// no tenerlo.
///
/// **Las miniaturas se pintan según se ven.** Una lista perezosa y no una
/// columna: pintar ciento veinte páginas para enseñar seis es lo que hace
/// que abrir una pestaña tarde un segundo.
library;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'theme.dart';

/// Qué enseña el lateral.
enum PdfSidebarView { outline, thumbnails }

class PdfSidebar extends StatefulWidget {
  const PdfSidebar({
    super.key,
    required this.document,
    required this.outline,
    required this.page,
    required this.onGoToPage,
    required this.onGoToDest,
    this.width = 178,
  });

  /// El documento abierto. Nulo mientras carga: el lateral se queda en
  /// blanco en lugar de parpadear con una lista que no es la definitiva.
  final PdfDocument? document;

  /// Los marcadores, ya cargados. Vacío cuando el PDF no trae ninguno.
  final List<PdfOutlineNode> outline;

  /// La página en la que está el visor, para marcarla.
  final int page;

  final ValueChanged<int> onGoToPage;
  final ValueChanged<PdfDest?> onGoToDest;

  final double width;

  @override
  State<PdfSidebar> createState() => _PdfSidebarState();
}

class _PdfSidebarState extends State<PdfSidebar> {
  PdfSidebarView? _chosen;

  /// Lo que se enseña: lo que se haya elegido, y si no, el índice cuando lo
  /// hay. Un tema compilado en apuntes tiene sus apartados; una hoja suelta
  /// no, y ahí lo útil son las páginas.
  PdfSidebarView get _view {
    if (_chosen != null &&
        !(_chosen == PdfSidebarView.outline && widget.outline.isEmpty)) {
      return _chosen!;
    }
    return widget.outline.isEmpty
        ? PdfSidebarView.thumbnails
        : PdfSidebarView.outline;
  }

  @override
  Widget build(BuildContext context) => Container(
    width: widget.width,
    decoration: const BoxDecoration(
      color: didactaPanel,
      border: Border(right: BorderSide(color: didactaRule)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.outline.isNotEmpty) _switcher(),
        Expanded(
          child: _view == PdfSidebarView.outline
              ? _Outline(nodes: widget.outline, onGoToDest: widget.onGoToDest)
              // Las miniaturas necesitan el documento y el índice no, así
              // que sólo ellas esperan: con el PDF abriéndose, el lateral
              // ya puede enseñar los apartados.
              : widget.document == null
              ? const SizedBox.shrink()
              : _Thumbnails(
                  document: widget.document!,
                  page: widget.page,
                  onGoToPage: widget.onGoToPage,
                ),
        ),
      ],
    ),
  );

  Widget _switcher() => Padding(
    padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
    child: Row(
      children: [
        Expanded(
          child: _Choice(
            key: const Key('pdf-sidebar-outline'),
            label: 'Índice',
            selected: _view == PdfSidebarView.outline,
            onTap: () => setState(() => _chosen = PdfSidebarView.outline),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _Choice(
            key: const Key('pdf-sidebar-pages'),
            label: 'Páginas',
            selected: _view == PdfSidebarView.thumbnails,
            onTap: () => setState(() => _chosen = PdfSidebarView.thumbnails),
          ),
        ),
      ],
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? didactaSelected : Colors.transparent,
    borderRadius: BorderRadius.circular(5),
    child: InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? didactaAccentDark : didactaMuted,
          ),
        ),
      ),
    ),
  );
}

/// El índice, aplanado con su nivel.
///
/// Aplanado y no un árbol plegable: los marcadores de un tema son dos
/// niveles --apartado y subapartado-- y plegarlos añade un clic para
/// esconder seis líneas. La sangría ya dice cuál cuelga de cuál.
class _Outline extends StatelessWidget {
  const _Outline({required this.nodes, required this.onGoToDest});

  final List<PdfOutlineNode> nodes;
  final ValueChanged<PdfDest?> onGoToDest;

  List<({PdfOutlineNode node, int level})> get _flat {
    final out = <({PdfOutlineNode node, int level})>[];
    void walk(List<PdfOutlineNode> children, int level) {
      for (final node in children) {
        out.add((node: node, level: level));
        walk(node.children, level + 1);
      }
    }

    walk(nodes, 0);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final flat = _flat;
    return ListView.builder(
      key: const Key('pdf-outline-list'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: flat.length,
      itemBuilder: (context, index) {
        final entry = flat[index];
        return InkWell(
          key: Key('pdf-outline-$index'),
          onTap: () => onGoToDest(entry.node.dest),
          child: Padding(
            padding: EdgeInsets.fromLTRB(8 + entry.level * 11.0, 5, 8, 5),
            child: Text(
              entry.node.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: entry.level == 0 ? 11.5 : 11,
                fontWeight: entry.level == 0
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: entry.level == 0 ? didactaInk : didactaMuted,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Thumbnails extends StatelessWidget {
  const _Thumbnails({
    required this.document,
    required this.page,
    required this.onGoToPage,
  });

  final PdfDocument document;
  final int page;
  final ValueChanged<int> onGoToPage;

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const Key('pdf-thumbnails'),
    padding: const EdgeInsets.symmetric(vertical: 6),
    itemCount: document.pages.length,
    itemBuilder: (context, index) {
      final number = index + 1;
      final here = number == page;
      return InkWell(
        key: Key('pdf-thumbnail-$number'),
        onTap: () => onGoToPage(number),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Column(
            children: [
              Container(
                height: 104,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: here ? didactaAccentDark : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: PdfPageView(document: document, pageNumber: number),
              ),
              const SizedBox(height: 2),
              Text(
                '$number',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: here ? FontWeight.w700 : FontWeight.w400,
                  color: here ? didactaAccentDark : didactaMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
