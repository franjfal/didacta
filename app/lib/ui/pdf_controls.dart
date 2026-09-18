/// Los mandos del visor: a qué página, y de qué tamaño.
///
/// Van juntos en un fichero porque son lo mismo --lo que se hace con un PDF
/// que se está mirando-- y porque los usan los dos visores: el de la pestaña
/// y el del diálogo. Dos visores del mismo programa con distintos gestos
/// para lo mismo es de lo que se acaba acordando uno en mitad de una clase.
///
/// **El zoom llega a su sitio por el ajuste, no por el porcentaje.** Nadie
/// quiere el 137%: quiere que la hoja quepa de ancho para leerla, o entera
/// para ver cómo ha quedado la página. Así que los tres ajustes son botones
/// y el porcentaje es un rótulo, no un campo.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// El número de página, escribible.
///
/// Un rótulo `7 / 120` dice dónde estás y no deja ir a ningún sitio; con
/// ciento veinte páginas, «ir a la 84» con las flechas son setenta y siete
/// clics. Se escribe el número y se pulsa Intro.
///
/// Lo que se teclea no se aplica hasta Intro, y al perder el foco vuelve a
/// lo que hay: escribir un `1` camino del `14` no puede saltar a la primera.
class PdfPageField extends StatefulWidget {
  const PdfPageField({
    super.key,
    required this.page,
    required this.pages,
    required this.onGoToPage,
    this.showTotal = true,
  });

  final int page;
  final int pages;
  final ValueChanged<int> onGoToPage;

  /// El `/ 120` de al lado. Es lo primero que sobra cuando el panel es un
  /// tercio de ventana: dice cuántas hay, y cuántas hay también lo dice el
  /// lateral y la barra de desplazamiento.
  final bool showTotal;

  @override
  State<PdfPageField> createState() => _PdfPageFieldState();
}

class _PdfPageFieldState extends State<PdfPageField> {
  late final TextEditingController _text = TextEditingController(
    text: '${widget.page}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _reset();
    });
  }

  @override
  void didUpdateWidget(PdfPageField old) {
    super.didUpdateWidget(old);
    // Mientras se teclea no se pisa lo escrito; pasar página con la rueda
    // sí tiene que verse reflejado aquí.
    if (widget.page != old.page && !_focus.hasFocus) _reset();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reset() => _text.text = '${widget.page}';

  void _submit(String value) {
    final wanted = int.tryParse(value.trim());
    if (wanted == null || widget.pages <= 0) {
      _reset();
      return;
    }
    widget.onGoToPage(wanted.clamp(1, widget.pages));
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 34,
        height: 22,
        child: TextField(
          key: const Key('pdf-page-field'),
          controller: _text,
          focusNode: _focus,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: _submit,
          style: const TextStyle(
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            border: OutlineInputBorder(),
          ),
        ),
      ),
      if (widget.showTotal)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '/ ${widget.pages}',
            style: const TextStyle(
              fontSize: 12,
              color: didactaMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
    ],
  );
}

/// Alejar, acercar, y los tres ajustes.
///
/// El porcentaje se enseña entre los dos botones porque es donde se mira
/// para saber si lo que se ve es tamaño real; pulsarlo devuelve al 100%,
/// que es el gesto que todo el mundo prueba.
///
/// Con [compact] los tres ajustes se pliegan en un menú. No es un adorno:
/// en modo lado a lado un panel es un tercio de ventana, y una barra que se
/// desborda esconde sus propios botones (D75).
class PdfZoomControls extends StatelessWidget {
  const PdfZoomControls({
    super.key,
    required this.zoom,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onActualSize,
    required this.onFitWidth,
    required this.onFitHeight,
    required this.onFitPage,
    this.compact = false,
    this.showZoom = true,
  });

  final bool compact;

  /// El porcentaje. Se apaga en la barra más estrecha: es un rótulo, y lo
  /// que no puede irse de una barra son los botones.
  final bool showZoom;

  /// El zoom actual. Nulo mientras el visor no está listo: entonces los
  /// mandos salen apagados en lugar de mentir con un 100%.
  final double? zoom;

  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onActualSize;
  final VoidCallback? onFitWidth;
  final VoidCallback? onFitHeight;
  final VoidCallback? onFitPage;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: const Key('pdf-zoom-out'),
        tooltip: 'Alejar',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.zoom_out, size: 18),
        onPressed: onZoomOut,
      ),
      if (showZoom)
        InkWell(
          key: const Key('pdf-zoom-actual'),
          onTap: onActualSize,
          borderRadius: BorderRadius.circular(4),
          child: Tooltip(
            message: 'Tamaño real',
            child: SizedBox(
              width: 44,
              child: Text(
                zoom == null ? '—' : '${(zoom! * 100).round()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: didactaMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      IconButton(
        key: const Key('pdf-zoom-in'),
        tooltip: 'Acercar',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.zoom_in, size: 18),
        onPressed: onZoomIn,
      ),
      const SizedBox(width: 2),
      if (compact)
        MenuAnchor(
          builder: (context, controller, child) => IconButton(
            key: const Key('pdf-fit-menu'),
            tooltip: 'Ajustar',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.fit_screen, size: 17),
            onPressed: onFitWidth == null
                ? null
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
          ),
          menuChildren: [
            MenuItemButton(
              key: const Key('pdf-fit-width'),
              onPressed: onFitWidth,
              child: const Text('Ajustar al ancho'),
            ),
            MenuItemButton(
              key: const Key('pdf-fit-height'),
              onPressed: onFitHeight,
              child: const Text('Ajustar al alto'),
            ),
            MenuItemButton(
              key: const Key('pdf-fit-page'),
              onPressed: onFitPage,
              child: const Text('Página entera'),
            ),
          ],
        )
      else ...[
        IconButton(
          key: const Key('pdf-fit-width'),
          tooltip: 'Ajustar al ancho',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.swap_horiz, size: 18),
          onPressed: onFitWidth,
        ),
        IconButton(
          key: const Key('pdf-fit-height'),
          tooltip: 'Ajustar al alto',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.swap_vert, size: 18),
          onPressed: onFitHeight,
        ),
        IconButton(
          key: const Key('pdf-fit-page'),
          tooltip: 'Página entera',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.fit_screen, size: 17),
          onPressed: onFitPage,
        ),
      ],
    ],
  );
}

/// La barra de un visor: el lateral, la página, el tamaño, y lo que añada
/// quien la use.
///
/// Compartida entre la pestaña y el diálogo porque es la misma barra; lo que
/// cambia entre los dos es lo de la derecha --separar una versión, elegir
/// otras-- y eso entra por [trailing].
///
/// **Se mide, no se supone.** Encoge en dos pasos según el ancho: primero se
/// va el rótulo y el botón de la primera página, después los tres ajustes se
/// pliegan en un menú. Un panel de un tercio de ventana es tan real como una
/// ventana entera (D75).
class PdfViewerBar extends StatelessWidget {
  const PdfViewerBar({
    super.key,
    required this.page,
    required this.pages,
    required this.sidebar,
    required this.zoom,
    required this.onSidebar,
    required this.onGoToPage,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onActualSize,
    required this.onFitWidth,
    required this.onFitHeight,
    required this.onFitPage,
    this.label,
    this.labelDirection = TextDirection.ltr,
    this.trailing = const [],
  });

  final int page;
  final int pages;
  final bool sidebar;
  final double? zoom;
  final VoidCallback onSidebar;
  final ValueChanged<int> onGoToPage;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onActualSize;
  final VoidCallback? onFitWidth;
  final VoidCallback? onFitHeight;
  final VoidCallback? onFitPage;

  /// Lo que se está mirando. Es lo primero que se va cuando falta sitio.
  final String? label;

  /// De derecha a izquierda para una ruta: lo que hay que leer de un nombre
  /// largo es el final.
  final TextDirection labelDirection;

  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: didactaSurface,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Tres escalones, medidos: con sitio va todo; a partir de ahí se
        // van el rótulo y la primera página, y los tres ajustes se pliegan
        // en un menú; y en la más estrecha se van también los dos números
        // que son rótulo --el total y el porcentaje--, que es lo único que
        // se puede quitar sin quitar un botón.
        final room = constraints.maxWidth - trailing.length * 40;
        final roomy = room >= 560;
        final compact = room < 560;
        final tight = room < 440;
        return Row(
          children: [
            IconButton(
              key: const Key('pdf-sidebar-toggle'),
              tooltip: sidebar ? 'Ocultar el lateral' : 'Índice y páginas',
              visualDensity: VisualDensity.compact,
              isSelected: sidebar,
              color: sidebar ? didactaAccentDark : null,
              icon: const Icon(Icons.vertical_split_outlined, size: 17),
              onPressed: onSidebar,
            ),
            const SizedBox(width: 2),
            if (roomy)
              IconButton(
                key: const Key('pdf-first-page'),
                tooltip: 'Primera página',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.first_page, size: 18),
                onPressed: pages > 1 && page > 1 ? () => onGoToPage(1) : null,
              ),
            IconButton(
              key: const Key('pdf-previous-page'),
              tooltip: 'Anterior',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left, size: 18),
              onPressed: page > 1 ? () => onGoToPage(page - 1) : null,
            ),
            PdfPageField(
              page: page,
              pages: pages,
              onGoToPage: onGoToPage,
              showTotal: !tight,
            ),
            IconButton(
              key: const Key('pdf-next-page'),
              tooltip: 'Siguiente',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right, size: 18),
              onPressed: page < pages ? () => onGoToPage(page + 1) : null,
            ),
            const SizedBox(width: 4),
            PdfZoomControls(
              zoom: zoom,
              compact: compact,
              showZoom: !tight,
              onZoomOut: onZoomOut,
              onZoomIn: onZoomIn,
              onActualSize: onActualSize,
              onFitWidth: onFitWidth,
              onFitHeight: onFitHeight,
              onFitPage: onFitPage,
            ),
            Expanded(
              child: label == null || !roomy
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        label!,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        textDirection: labelDirection,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: didactaMuted,
                        ),
                      ),
                    ),
            ),
            ...trailing,
          ],
        );
      },
    ),
  );
}
