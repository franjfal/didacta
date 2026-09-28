/// El aviso del sistema al terminar de compilar: qué dice y cómo se enseña en
/// cada sistema.
///
/// Sin `dart:io`, por lo mismo que `launch.dart`: lo que cambia de un sistema
/// a otro es **qué se lanza**, y eso se prueba para los tres desde una sola
/// máquina. Lanzarlo es `data/notifier_io.dart`.
///
/// Sin paquetes de notificaciones, a propósito. Los tres sistemas traen ya
/// con qué hacerlo --`osascript` en el Mac, PowerShell en Windows,
/// `notify-send` en casi cualquier Linux--, y un complemento nativo más es
/// otra pieza que compilar en tres sistemas para un aviso que es opcional y
/// que, si no sale, no rompe nada.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'launch.dart';
import 'toolchain.dart' show Host;
import '../l10n/tr.dart';

/// Lo que dice el aviso de una compilación que acaba de terminar.
///
/// Null si no hay nada que decir: una compilación detenida la ha parado
/// alguien que ya lo sabe.
({String title, String body})? buildNotice({
  required String what,
  required bool ok,
  required bool stopped,
  String? summary,
}) {
  if (stopped) return null;
  final subject = what.trim().isEmpty
      ? tr('La compilación')
      : '«${what.trim()}»';
  if (ok) {
    return (
      title: tr('Compilado'),
      body: summary ?? tr('{0} ya está.', [subject]),
    );
  }
  return (
    title: tr('No ha compilado'),
    body: summary == null
        ? tr(
            '{0} tiene errores. Están en Didacta, con a dónde lleva cada uno.',
            [subject],
          )
        : tr('{0}. Los errores están en Didacta.', [summary]),
  );
}

/// Cómo se enseña un aviso en [host].
///
/// En el Mac, `display notification` de AppleScript, con «Didacta» de título
/// y [title] debajo. En Windows, una notificación de las suyas a través de
/// PowerShell, con la orden codificada --`-EncodedCommand`-- para que ninguna
/// comilla de un título pueda romperla. En Linux, `notify-send`, que está en
/// casi todos los escritorios; donde no esté, no sale nada.
LaunchCommand notificationLaunch({
  required String title,
  required String body,
  required Host host,
}) {
  switch (host) {
    case Host.macos:
      return LaunchCommand('/usr/bin/osascript', [
        '-e',
        'display notification ${_appleScript(body)} '
            'with title "Didacta" subtitle ${_appleScript(title)}',
      ]);
    case Host.linux:
      return LaunchCommand('notify-send', [
        '--app-name=Didacta',
        tr('Didacta · {0}', [_oneLine(title)]),
        _oneLine(body),
      ]);
    case Host.windows:
      return LaunchCommand('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        _encoded(
          _toastScript(tr('Didacta · {0}', [_oneLine(title)]), _oneLine(body)),
        ),
      ]);
  }
}

/// Una notificación de Windows con dos líneas.
///
/// Con el identificador de PowerShell y no con uno propio: Windows solo
/// enseña las de una aplicación que se ha registrado con un acceso directo en
/// el menú Inicio, y la de PowerShell está registrada siempre. El aviso sale
/// a nombre de PowerShell, que es el precio de no instalar nada más.
String _toastScript(String title, String body) => [
  '[Windows.UI.Notifications.ToastNotificationManager, '
      'Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null',
  r'$toast = [Windows.UI.Notifications.ToastNotificationManager]::'
      'GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::'
      'ToastText02)',
  r"$lines = $toast.GetElementsByTagName('text')",
  '\$lines.Item(0).AppendChild(\$toast.CreateTextNode(${_powerShell(title)}))'
      ' | Out-Null',
  '\$lines.Item(1).AppendChild(\$toast.CreateTextNode(${_powerShell(body)}))'
      ' | Out-Null',
  r"$app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\"
      "powershell.exe'",
  r'[Windows.UI.Notifications.ToastNotificationManager]::'
      r'CreateToastNotifier($app).Show('
      r'[Windows.UI.Notifications.ToastNotification]::new($toast))',
].join('\n');

/// Lo que espera `-EncodedCommand`: la orden en UTF-16 little-endian, en
/// base64.
String _encoded(String script) {
  final units = script.codeUnits;
  final bytes = ByteData(units.length * 2);
  for (var i = 0; i < units.length; i += 1) {
    bytes.setUint16(i * 2, units[i], Endian.little);
  }
  return base64.encode(bytes.buffer.asUint8List());
}

/// Un texto entre comillas de AppleScript.
String _appleScript(String text) =>
    '"${_oneLine(text).replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// Un texto entre comillas simples de PowerShell, donde la única que hay que
/// escapar es la propia comilla, doblándola.
String _powerShell(String text) => "'${text.replaceAll("'", "''")}'";

/// En una línea: un aviso no es sitio para un registro.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s*\n\s*'), ' ');
