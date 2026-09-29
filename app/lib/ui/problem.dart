/// Un fallo, dicho de forma que se entienda y con qué hacer.
///
/// Había unos cuarenta sitios que enseñaban el error tal cual --a menudo lo
/// que escribe git, en inglés-- en un aviso que se iba a los cuatro segundos.
/// Esto los junta en uno: [problemOf] traduce los casos que de verdad pasan
/// (hay cambios nuevos en GitHub, la sesión ha caducado, no hay red, dos
/// cambios chocan, dos historias no se pueden juntar, la carpeta está
/// ocupada, GitHub rechaza el envío) a qué ha pasado y qué hacer, con el
/// botón que lo hace cuando lo hay; y lo que dijo el programa queda debajo,
/// en «Detalles», para copiarlo o contarlo.
///
/// Los choques son dos a propósito. «Dos cambios chocan» es el editor con una
/// copia vieja de un fichero, y se arregla recargando; dos historias que no
/// se juntan solas se arreglan con git, y mandar a recargar no sirve de nada.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/browser.dart';
import '../data/content_gateway.dart';
import '../data/diagnostics.dart';
import '../data/local_clone.dart';
import '../router.dart';
import '../state/session.dart';
import '../state/update_service.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Lo que se puede hacer para arreglarlo, si hay algo que hacer desde aquí.
enum ProblemFix {
  /// Traer lo que hay en GitHub.
  pull,

  /// Volver a entrar en GitHub.
  signIn,

  /// Leer en la ayuda cómo se hace, cuando es trabajo de fuera de Didacta.
  help,
}

/// Un fallo, traducido.
class Problem {
  const Problem({
    required this.title,
    this.advice = '',
    this.fix,
    this.help,
    required this.detail,
  });

  /// Qué ha pasado, en una línea.
  final String title;

  /// Qué hacer, o por qué no es grave.
  final String advice;

  final ProblemFix? fix;

  /// La página de la ayuda de [ProblemFix.help], desde la raíz de la web.
  final String? help;

  /// Lo que dijo el programa, tal cual.
  final String detail;

  String? get fixLabel => switch (fix) {
    ProblemFix.pull => tr('Traer'),
    ProblemFix.signIn => tr('Volver a entrar'),
    ProblemFix.help => tr('Cómo juntarlos'),
    null => null,
  };
}

/// La clase de fallo que hay debajo de [error], si se sabe.
CloneFailure? _failureOf(Object error) => switch (error) {
  CloneException() => error.kind,
  ContentException(:final cause?) => _failureOf(cause),
  ContentException(kind: ContentFailure.unauthenticated) =>
    CloneFailure.unauthenticated,
  ContentException(kind: ContentFailure.conflict) => CloneFailure.conflict,
  TimeoutException() => CloneFailure.offline,
  // Por el nombre y no importando `dart:io`, que en la web no existe: son los
  // que lanzan la red y el cliente HTTP cuando no se llega.
  _ when _offlineTypes.contains(error.runtimeType.toString()) =>
    CloneFailure.offline,
  _ => null,
};

const Set<String> _offlineTypes = {
  'SocketException',
  'HandshakeException',
  'ClientException',
};

/// [error], traducido. Sin contexto: lo que dice depende solo del fallo.
Problem problemOf(Object error) {
  final detail = '$error'.trim();
  return switch (_failureOf(error)) {
    CloneFailure.behind => Problem(
      title: tr('Hay cambios nuevos en GitHub'),
      advice: tr(
        'Alguien ha enviado algo desde la última vez. Trae primero sus '
        'cambios y vuelve a intentarlo: lo tuyo no se pierde.',
      ),
      fix: ProblemFix.pull,
      detail: detail,
    ),
    CloneFailure.unauthenticated => Problem(
      title: tr('GitHub no acepta tu sesión'),
      advice: tr(
        'Puede que haya caducado o que no tengas permiso para escribir en '
        'este repositorio. Vuelve a entrar.',
      ),
      fix: ProblemFix.signIn,
      detail: detail,
    ),
    CloneFailure.offline => Problem(
      title: tr('No se llega a GitHub'),
      advice: tr(
        'Parece que no hay red. Lo guardado está a salvo en tu ordenador: '
        'se enviará cuando vuelva.',
      ),
      detail: detail,
    ),
    CloneFailure.conflict => Problem(
      title: tr('Dos cambios chocan'),
      advice: tr(
        'El mismo fichero ha cambiado en otro sitio desde que lo abriste. '
        'Vuelve a cargarlo y aplica otra vez tu cambio; lo tuyo sigue en '
        'el editor mientras tanto.',
      ),
      detail: detail,
    ),
    CloneFailure.diverged => Problem(
      title: tr('Tus cambios y los de GitHub no se pueden juntar solos'),
      advice: tr(
        'Tienes cambios sin enviar, y en GitHub han entrado otros que tocan '
        'lo mismo. Didacta lo ha dejado todo como estaba --lo tuyo sigue '
        'guardado en tu ordenador--; juntarlos es cosa de git, a mano.',
      ),
      fix: ProblemFix.help,
      help: 'ayuda/problemas/#historias-separadas',
      detail: detail,
    ),
    CloneFailure.locked => Problem(
      title: tr('La carpeta del repositorio está ocupada'),
      advice: tr(
        'Otro programa, u otro git, la está usando ahora mismo. Espera un '
        'momento, o ciérralo, y vuelve a intentarlo.',
      ),
      detail: detail,
    ),
    CloneFailure.rejected => Problem(
      title: tr('GitHub ha rechazado el envío'),
      advice: tr(
        'Una regla del repositorio no lo permite: una rama protegida o una '
        'comprobación. Lo tuyo sigue guardado en tu ordenador.',
      ),
      detail: detail,
    ),
    _ => Problem(title: _firstLine(error), detail: detail),
  };
}

/// La primera línea del mensaje, que suele ser la frase que se escribió
/// para esto; lo demás va a «Detalles».
String _firstLine(Object error) {
  final text = switch (error) {
    CloneException(:final message) => message,
    ContentException(:final message) => message,
    _ => '$error',
  }.trim();
  final line = text.split('\n').first.trim();
  if (line.isEmpty) return tr('Algo ha fallado');
  return line.length > 160 ? '${line.substring(0, 157)}…' : line;
}

/// Cuenta [error] en un aviso que no se va solo en cuatro segundos, con el
/// arreglo a un botón y los detalles a otro.
void showProblem(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) showProblemIn(messenger, error);
}

/// Lo mismo, con el [messenger] que se cogió antes de un `await`: para cuando
/// llega el fallo la pantalla puede haberse ido, y el aviso tiene que salir
/// igual. Lo demás --la sesión para traer, el router para ir a entrar-- lo
/// busca desde él.
void showProblemIn(ScaffoldMessengerState messenger, Object error) => _show(
  messenger,
  problemOf(error),
  session: _readOrNull<Session>(messenger.context),
  router: _readOrNull<GoRouter>(messenger.context),
);

T? _readOrNull<T>(BuildContext context) {
  try {
    return context.read<T?>();
  } catch (caught, trace) {
    Diagnostics.instance.note('problem.showProblemIn', caught, trace);
    return null;
  }
}

void _show(
  ScaffoldMessengerState messenger,
  Problem problem, {
  required Session? session,
  required GoRouter? router,
}) {
  // La del tema en el que sale el aviso: el del messenger, que está debajo.
  final palette = messenger.context.palette;
  VoidCallback? fix;
  switch (problem.fix) {
    case ProblemFix.pull:
      if (session != null) {
        fix = () async {
          final result = await session.pullAll();
          final failed = result.values.where((each) => each is! int);
          if (failed.isEmpty) {
            messenger.showSnackBar(
              SnackBar(content: Text(tr('Traído. Vuelve a intentarlo.'))),
            );
            return;
          }
          // Lo que impidió traer, contado como cualquier otro aviso y no
          // con el texto de la excepción pegado detrás.
          _show(
            messenger,
            problemOf(failed.first),
            session: session,
            router: router,
          );
        };
      }
    case ProblemFix.signIn:
      if (router != null) {
        fix = () => router.go(Routes.settings(section: 'repositorios'));
      }
    case ProblemFix.help:
      final help = problem.help;
      if (help != null) fix = () => openLink('$didactaDocs$help');
    case null:
      break;
  }

  messenger.showSnackBar(
    SnackBar(
      key: const Key('problem'),
      backgroundColor: palette.teacher,
      duration: const Duration(seconds: 12),
      // Con acción, Flutter lo dejaría puesto hasta que se pulse; este se va
      // solo, a su tiempo.
      persist: false,
      content: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  problem.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (problem.advice.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(problem.advice),
                ],
              ],
            ),
          ),
          if (problem.detail.isNotEmpty && problem.detail != problem.title)
            TextButton(
              key: const Key('problem-details'),
              style: TextButton.styleFrom(foregroundColor: palette.onAccent),
              onPressed: () {
                messenger.hideCurrentSnackBar();
                // Sobre la pantalla que haya ahora: el aviso dura más que
                // algunas, y la que lo lanzó puede haberse ido.
                final where =
                    router?.routerDelegate.navigatorKey.currentContext;
                if (where != null) {
                  unawaited(showProblemDetails(where, problem));
                }
              },
              child: Text(tr('Detalles')),
            ),
        ],
      ),
      action: fix == null || problem.fixLabel == null
          ? null
          : SnackBarAction(
              key: const Key('problem-fix'),
              label: problem.fixLabel!,
              textColor: palette.onAccent,
              onPressed: fix,
            ),
    ),
  );
}

/// La dirección de una incidencia nueva, con la versión y [detail] escritos.
///
/// Un informe sin versión ni sistema necesita un viaje de ida y vuelta antes
/// de poder mirarse, y quien lo escribe no tiene por qué saber cuál es.
String issueLink(BuildContext context, {String detail = ''}) {
  final info = context.read<UpdateService?>()?.info;
  final body = Uri.encodeComponent(
    tr(
      '## Qué pasó\n\n\n\n'
      '## Qué esperabas que pasara\n\n\n\n'
      '## Cómo repetirlo\n\n\n\n'
      '{0}'
      '---\n'
      'Didacta {1}\n',
      [
        detail.isEmpty
            ? ''
            : tr('## Lo que dijo Didacta\n\n```\n{0}\n```\n\n', [detail]),
        info?.describe ?? tr('(versión desconocida)'),
      ],
    ),
  );
  return '$didactaIssues/new?body=$body';
}

/// Lo que dijo el programa, plegado, con Copiar y Contar el problema.
Future<void> showProblemDetails(
  BuildContext context,
  Problem problem,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: const Key('problem-dialog'),
    title: Text(problem.title),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (problem.advice.isNotEmpty)
            Text(problem.advice, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('problem-said'),
              tilePadding: EdgeInsets.zero,
              title: Text(
                tr('Lo que dijo el programa'),
                style: TextStyle(fontSize: 12.5, color: context.palette.muted),
              ),
              children: [
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 240),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.palette.panel,
                    border: Border.all(color: context.palette.rule),
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      problem.detail,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('problem-copy'),
        onPressed: () async {
          await Clipboard.setData(
            ClipboardData(text: '${problem.title}\n\n${problem.detail}'),
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(tr('Copiado.'))));
        },
        child: Text(tr('Copiar')),
      ),
      TextButton(
        key: const Key('problem-report'),
        onPressed: () => openLink(
          issueLink(context, detail: '${problem.title}\n\n${problem.detail}'),
        ),
        child: Text(tr('Contar el problema')),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('Cerrar')),
      ),
    ],
  ),
);
