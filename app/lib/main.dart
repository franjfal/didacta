/// Didacta, on the web.
///
/// Loads the generated index and shows the library. The index location can be
/// overridden at build time:
///
///     flutter build web --dart-define=DIDACTA_INDEX=/didacta-content/generated
///
/// so one build serves any content repository that publishes its `generated/`
/// directory, which is what makes a GitHub Pages deployment possible with no
/// server involved.
library;

import 'package:flutter/material.dart';

import 'data/catalogue_source.dart';
import 'model/catalogue.dart';
import 'ui/library_page.dart';
import 'ui/theme.dart';

/// Where to read the index from. Relative by default, so a build dropped next
/// to a content repository works unconfigured.
const String indexBase =
    String.fromEnvironment('DIDACTA_INDEX', defaultValue: 'generated');

void main() {
  runApp(const DidactaApp(source: HttpCatalogueSource(base: indexBase)));
}

class DidactaApp extends StatelessWidget {
  const DidactaApp({super.key, required this.source});

  final CatalogueSource source;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Didacta',
      debugShowCheckedModeBanner: false,
      theme: didactaTheme(),
      home: CatalogueLoader(source: source),
    );
  }
}

/// Loads the catalogue once and shows the library, or says why it could not.
class CatalogueLoader extends StatefulWidget {
  const CatalogueLoader({super.key, required this.source});

  final CatalogueSource source;

  @override
  State<CatalogueLoader> createState() => _CatalogueLoaderState();
}

class _CatalogueLoaderState extends State<CatalogueLoader> {
  late Future<Catalogue> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.source.load();
  }

  void _retry() {
    setState(() => _future = widget.source.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Catalogue>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _LoadFailure(
            error: snapshot.error!,
            where: widget.source.describe,
            onRetry: _retry,
          );
        }
        final catalogue = snapshot.data!;
        return Column(
          children: [
            // Whatever the engine complained about while reading the
            // repository, shown rather than swallowed: an interface built on a
            // repository that does not load cleanly should say so.
            if (catalogue.errors.isNotEmpty)
              _ErrorBanner(errors: catalogue.errors),
            Expanded(child: LibraryPage(catalogue: catalogue)),
          ],
        );
      },
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({
    required this.error,
    required this.where,
    required this.onRetry,
  });

  final Object error;
  final String where;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, color: didactaTeacher),
                    SizedBox(width: 8),
                    Text('No se pudo cargar el catálogo',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                // Where it read from, because "could not load" without a
                // location is not something anyone can act on.
                Text('Origen: $where',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        color: didactaMuted)),
                const SizedBox(height: 12),
                Text(
                  error is CatalogueFormatException
                      ? (error as CatalogueFormatException).message
                      : error.toString(),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 20),
                const Text(
                  'El catálogo lo genera el motor. Desde el repositorio de '
                  'contenido:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: didactaMuted.withValues(alpha: 0.10),
                  child: const Text('didacta index',
                      style: TextStyle(
                          fontFamily: 'monospace', fontSize: 13)),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                    onPressed: onRetry,
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: didactaTeacher.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 16, color: didactaTeacher),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                errors.length == 1
                    ? errors.first
                    : '${errors.length} problemas al leer el repositorio: '
                        '${errors.first}',
                style: const TextStyle(fontSize: 12.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              child: const Text('Ver todos'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Problemas al leer el repositorio'),
                  content: SizedBox(
                    width: 560,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final message in errors)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(message,
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
