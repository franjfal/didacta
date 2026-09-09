/// The small non-secret settings: where the clone is, and whether to push.
///
/// Separate from [SecretStore] on purpose. A token belongs in the keychain
/// because it is a credential; a folder path does not, and putting it there
/// would mean every read of a path prompts for keychain access on some
/// systems. The distinction is worth keeping visible.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// What the app remembers between runs, other than secrets.
abstract class Preferences {
  Future<String?> clonePath();
  Future<void> setClonePath(String? path);

  Future<bool> pushOnCommit();
  Future<void> setPushOnCommit(bool value);
}

class StoredPreferences implements Preferences {
  const StoredPreferences({this.defaultClonePath = ''});

  /// Where the clone is when nothing has been chosen yet.
  ///
  /// A build-time default, so a desktop build can be handed to someone who
  /// already has the repository on disk and have it work on first launch
  /// instead of starting on the Ajustes screen.
  final String defaultClonePath;

  static const String _clone = 'didacta.clone.path';
  static const String _push = 'didacta.clone.push';

  /// The stored value, then the build-time default. A stored empty string is
  /// a real answer -- "I turned the clone off" -- and must win over the
  /// default, which is why [setClonePath] stores it rather than removing it.
  @override
  Future<String?> clonePath() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_clone)) {
      final value = prefs.getString(_clone);
      return (value == null || value.isEmpty) ? null : value;
    }
    return defaultClonePath.isEmpty ? null : defaultClonePath;
  }

  @override
  Future<void> setClonePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    // Stored empty rather than removed, so "stop using the clone" is not
    // undone by the build-time default on the next launch.
    await prefs.setString(_clone, path ?? '');
  }

  /// Defaults to true: a commit nobody else can see is not traceable, which
  /// is the whole point of committing.
  @override
  Future<bool> pushOnCommit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_push) ?? true;
  }

  @override
  Future<void> setPushOnCommit(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_push, value);
  }
}

/// For tests, and for a platform where nothing is remembered.
class MemoryPreferences implements Preferences {
  MemoryPreferences({this.path, this.push = true});

  String? path;
  bool push;

  @override
  Future<String?> clonePath() async => path;

  @override
  Future<void> setClonePath(String? value) async => path = value;

  @override
  Future<bool> pushOnCommit() async => push;

  @override
  Future<void> setPushOnCommit(bool value) async => push = value;
}
