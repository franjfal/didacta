/// El historial de un fichero: cómo estaba en cada versión, y qué cambió.
///
/// El material vive en git, y git sabe contestar eso. Hasta ahora la respuesta
/// estaba a un `git log` de distancia y aun así obligaba a salir a un terminal
/// --o a github.com-- con la ruta del fichero en la cabeza. Una unidad se
/// reescribe durante años: saber qué se quitó en septiembre es tan parte de
/// editarla como el texto que hay ahora.
///
/// La forma es una lista de versiones a la izquierda y, a la derecha, **el
/// fichero como estaba en la que se elija**, con lo que ese commit añadió en
/// verde y lo que quitó en rojo.
///
/// Cuatro decisiones que conviene dejar dichas:
///
/// **Se enseña el fichero entero, no el recorte del cambio.** Un diff con tres
/// líneas de contexto contesta «¿qué tocó este commit?», que es la pregunta de
/// quien revisa un cambio ajeno. Editando, la pregunta es «¿cómo estaba esto
/// en marzo?», y esa solo la contesta el texto completo. Las marcas de verde y
/// rojo van dentro, así que la primera pregunta también se sigue contestando.
///
/// **El commit se mira aparte.** Quién lo hizo, cuándo exactamente, con qué
/// mensaje y con qué hash están detrás de un botón, no delante del texto: eso
/// es información *sobre* el cambio, y lo que se viene a leer es el cambio.
///
/// **Se carga cuando se abre, no antes.** Es la razón de que sea una pestaña y
/// no un panel: `git log --follow` sobre un repositorio con años dentro cuesta,
/// y cobrárselo a quien solo venía a editar el castellano sería cobrarlo casi
/// siempre por nada.
///
/// **Es de solo lectura.** No hay «revertir» ni «restaurar esta versión», y no
/// por falta de sitio: deshacer tres meses de trabajo con un botón que se
/// pulsa por error es un fallo del que no se vuelve. Lo que hay es el texto,
/// seleccionable, para copiar el trozo que haga falta.
///
/// **Un fichero, no el repositorio.** La pregunta que se hace editando es
/// «¿qué le ha pasado a *esto*?», y un historial del repositorio entero la
/// contesta enterrada entre commits de otras cuarenta unidades.
library;

import 'package:flutter/material.dart';

import '../data/local_clone.dart';
import '../model/file_history.dart';
import '../state/session.dart';
import 'diff_view.dart';
import 'theme.dart';

/// El estado de mirar el historial de un fichero.
///
/// Fuera del widget por lo mismo que el de compilar: una pestaña de la que te
/// vas tiene que conservar lo que había, y volver a ella no puede costar otro
/// `git log`.
class HistoryState extends ChangeNotifier {
  HistoryState({
    required this.session,
    required this.repo,
    required this.path,
  }) {
    load();
  }

  final Session session;

  /// De qué repositorio es el fichero. Con varios abiertos, la ruta sola no
  /// dice de cuál.
  final String? repo;

  /// La ruta dentro del repositorio.
  final String path;

  List<FileCommit> commits = const [];
  FileCommit? selected;

  /// El fichero entero en la versión elegida, con las marcas de lo que ese
  /// commit añadió y quitó.
  FileDiff? diff;

  /// El contenido de la versión elegida cuando el commit **no** cambió el
  /// fichero --un renombrado, una fusión-- y por tanto no hay diff del que
  /// sacarlo.
  String? unchanged;

  bool loading = true;
  bool loadingDiff = false;
  Object? problem;

  LocalClone? get _clone => session.cloneFor(repo);

  /// Si aquí se puede mirar un historial. Falso en web y sin clon.
  bool get available => _clone != null;

  /// Si la versión elegida es la última, que es la que hay en el disco.
  bool get selectedIsLatest =>
      commits.isNotEmpty && commits.first.sha == selected?.sha;

  Future<void> load() async {
    final clone = _clone;
    if (clone == null) {
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    problem = null;
    notifyListeners();
    try {
      commits = await clone.history(path);
      // El más reciente abierto de entrada: es el que se viene a mirar nueve
      // de cada diez veces, y una pantalla que abre vacía pidiendo un clic
      // para enseñar lo obvio es una pantalla que sobra a medias.
      if (commits.isNotEmpty) {
        await select(commits.first);
      }
    } catch (thrown) {
      problem = thrown;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> select(FileCommit commit) async {
    selected = commit;
    diff = null;
    unchanged = null;
    loadingDiff = true;
    notifyListeners();

    final clone = _clone;
    if (clone == null) {
      loadingDiff = false;
      notifyListeners();
      return;
    }

    FileDiff? found;
    String? text;
    Object? failure;
    try {
      // El fichero entero, no los alrededores del cambio: lo que se viene a
      // ver es cómo estaba la unidad ese día.
      found = await clone.diffOf(
        sha: commit.sha,
        path: path,
        context: LocalClone.wholeFile,
      );
      // Sin trozos no hay contenido que sacar del diff, y sin embargo la
      // versión existe: se le pide a git directamente.
      if (found.hunks.isEmpty && !found.isBinary) {
        text = await clone.fileAt(sha: commit.sha, path: path);
      }
    } catch (thrown) {
      failure = thrown;
    }

    // Entre medias puede haberse pulsado otra versión, y la que manda es la
    // última: escribir aquí la respuesta de una petición vieja dejaría el
    // contenido de un commit debajo del nombre de otro.
    if (selected?.sha != commit.sha) return;

    diff = found;
    unchanged = text;
    problem = failure;
    loadingDiff = false;
    notifyListeners();
  }
}

/// El historial de un fichero, con el contenido de cada versión.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, required this.state});

  final HistoryState state;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    if (!state.available) {
      return const DiffPlaceholder(
        icon: Icons.history_toggle_off,
        text:
            'El historial sale de git, así que hace falta un clon del '
            'repositorio en el disco. Se elige en Ajustes.',
      );
    }
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.problem != null && state.commits.isEmpty) {
      return DiffPlaceholder(
        icon: Icons.error_outline,
        text: '${state.problem}',
      );
    }
    if (state.commits.isEmpty) {
      return const DiffPlaceholder(
        icon: Icons.history,
        text:
            'Este fichero todavía no tiene historial: no hay ningún commit '
            'que lo haya tocado.',
      );
    }

    // A dos columnas cuando cabe, y apilado cuando no. La lista de versiones
    // y el contenido se miran a la vez -- se va saltando de una a otra -- así
    // que ponerlos uno detrás de otro con navegación entre medias sería
    // convertir una comparación en un viaje de ida y vuelta.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 780;
        final list = _Timeline(
          commits: state.commits,
          selected: state.selected,
          onSelect: state.select,
          compact: !wide,
        );
        final detail = _Detail(
          commit: state.selected,
          diff: state.diff,
          unchanged: state.unchanged,
          loading: state.loadingDiff,
          isLatest: state.selectedIsLatest,
        );
        if (!wide) {
          return Column(
            children: [
              SizedBox(height: 132, child: list),
              const Divider(height: 1, color: didactaRule),
              Expanded(child: detail),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 290, child: list),
            const VerticalDivider(width: 1, color: didactaRule),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

/// La lista de versiones, de la más reciente a la más antigua.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.commits,
    required this.selected,
    required this.onSelect,
    required this.compact,
  });

  final List<FileCommit> commits;
  final FileCommit? selected;
  final ValueChanged<FileCommit> onSelect;

  /// En horizontal cuando la ventana es estrecha.
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    color: didactaPanel,
    child: ListView.builder(
      scrollDirection: compact ? Axis.horizontal : Axis.vertical,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      itemCount: commits.length,
      itemBuilder: (context, index) => _CommitTile(
        key: Key('commit-${commits[index].sha}'),
        commit: commits[index],
        selected: commits[index].sha == selected?.sha,
        // El primero es el de ahora. Decirlo evita la duda de si lo que se
        // está viendo es el fichero actual o una versión de antes.
        isLatest: index == 0,
        onTap: () => onSelect(commits[index]),
        compact: compact,
      ),
    ),
  );
}

class _CommitTile extends StatelessWidget {
  const _CommitTile({
    super.key,
    required this.commit,
    required this.selected,
    required this.isLatest,
    required this.onTap,
    required this.compact,
  });

  final FileCommit commit;
  final bool selected;
  final bool isLatest;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: compact
          ? const EdgeInsets.only(right: 6)
          : const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? didactaSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: compact ? 240 : null,
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  commit.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      commit.shortSha,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: didactaMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${commit.author} · ${describeWhen(commit.when)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: didactaMuted,
                        ),
                      ),
                    ),
                    if (isLatest) const _NowChip(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La marca de «esta es la versión que hay en el disco».
class _NowChip extends StatelessWidget {
  const _NowChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: didactaAccentDark.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(3),
    ),
    child: const Text(
      'ahora',
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: didactaAccentDark,
      ),
    ),
  );
}

/// La versión elegida: su contenido, con lo que cambió marcado.
class _Detail extends StatelessWidget {
  const _Detail({
    required this.commit,
    required this.diff,
    required this.unchanged,
    required this.loading,
    required this.isLatest,
  });

  final FileCommit? commit;
  final FileDiff? diff;
  final String? unchanged;
  final bool loading;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final chosen = commit;
    if (chosen == null) {
      return const DiffPlaceholder(
        icon: Icons.history,
        text: 'Elige una versión para ver cómo estaba el fichero.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VersionBar(commit: chosen, diff: diff, isLatest: isLatest),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : DiffView(diff: diff, unchanged: unchanged),
        ),
      ],
    );
  }
}

/// La barra de encima del texto: qué versión es esto y cuánto cambió.
///
/// Una sola línea a propósito. Lo que ocupa la pantalla tiene que ser el
/// contenido; de la versión solo hacen falta dos cosas para no perderse --de
/// cuándo es y si es la de ahora--, y el resto está a un clic en el botón de
/// información.
class _VersionBar extends StatelessWidget {
  const _VersionBar({
    required this.commit,
    required this.diff,
    required this.isLatest,
  });

  final FileCommit commit;
  final FileDiff? diff;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final found = diff;
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: didactaCard,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
      child: Row(
        children: [
          // El grupo de la izquierda dentro de un `Expanded` y no suelto con
          // un `Spacer` detrás: un `Flexible` que no gasta lo que se le da
          // deja el hueco al final de la fila, y los contadores se quedarían
          // flotando en medio en cuanto la fecha fuera corta.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Versión del ${exactDay(commit.when)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  commit.shortSha,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: didactaMuted,
                  ),
                ),
                if (isLatest) ...[const SizedBox(width: 8), const _NowChip()],
              ],
            ),
          ),
          if (found != null && !found.isBinary) ...[
            Text(
              '+${found.added}',
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: didactaAccentDark,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '−${found.removed}',
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: didactaTeacher,
              ),
            ),
          ],
          IconButton(
            key: const Key('commit-info'),
            icon: const Icon(Icons.info_outline, size: 17),
            color: didactaMuted,
            visualDensity: VisualDensity.compact,
            tooltip: 'Información del commit',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => _CommitDialog(commit: commit, diff: found),
            ),
          ),
        ],
      ),
    );
  }
}

/// El commit entero, cuando se pide.
class _CommitDialog extends StatelessWidget {
  const _CommitDialog({required this.commit, required this.diff});

  final FileCommit commit;
  final FileDiff? diff;

  @override
  Widget build(BuildContext context) {
    final found = diff;
    return AlertDialog(
      backgroundColor: didactaCard,
      title: SelectableText(
        commit.subject,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (commit.body.isNotEmpty) ...[
                SelectableText(
                  commit.body,
                  style: const TextStyle(fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 14),
              ],
              _Field(
                label: 'Autor',
                value: '${commit.author} <${commit.email}>',
              ),
              _Field(label: 'Fecha', value: exactMoment(commit.when)),
              _Field(label: 'Commit', value: commit.sha, monospace: true),
              if (found != null && !found.isBinary)
                _Field(
                  label: 'Cambio',
                  value: '+${found.added} −${found.removed} líneas',
                  monospace: true,
                ),
              if (found?.renamedFrom != null)
                _Field(label: 'Antes estaba en', value: found!.renamedFrom!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: didactaMuted),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    ),
  );
}

/// El día, para decir de cuándo es una versión.
String exactDay(DateTime when) {
  final local = when.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

/// El día y la hora. En la lista se dice «hace tres días», que es lo que se lee
/// de un vistazo; aquí se dice cuál, que es lo que hace falta para citarlo o
/// para cruzarlo con otra cosa.
String exactMoment(DateTime when) {
  final local = when.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${exactDay(when)} ${two(local.hour)}:${two(local.minute)}';
}

/// El fichero como estaba en esa versión, con lo que el commit añadió en verde
/// y lo que quitó en rojo.
