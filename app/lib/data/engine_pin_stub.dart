import '../model/app_version.dart';
import 'engine_pin.dart';
import '../l10n/tr.dart';

Future<EngineVersion> inspectEngine(String engine, AppVersion app) async =>
    EngineVersion(app: app, blocked: tr('Aquí no hay motor que mover.'));

Future<void> pinEngine(String engine, AppVersion app) async =>
    throw EnginePinException(tr('Aquí no hay motor que mover.'));

Future<void> markManaged(String engine) async {}
