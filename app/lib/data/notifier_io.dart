/// Los avisos del sistema, con las órdenes de `model/notification.dart`.
library;

import 'dart:io';

import '../model/notification.dart';
import 'diagnostics.dart';
import 'toolchain_io.dart' show currentHost;

bool get supported => true;

Future<bool> show({required String title, required String body}) async {
  final command = notificationLaunch(
    title: title,
    body: body,
    host: currentHost,
  );
  try {
    final result = await Process.run(command.executable, command.arguments);
    return result.exitCode == 0;
  } on ProcessException catch (caught, trace) {
    // Un Linux sin `notify-send`: no hay aviso, y no pasa nada más.
    Diagnostics.instance.note('notifier.show', caught, trace);
    return false;
  }
}
