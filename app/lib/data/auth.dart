/// Signing in, and carrying the result to the API.
///
/// Firebase is used for identity and nothing else. It answers one question --
/// "is this really this person" -- and every question about *permissions* is
/// answered by `access.json` in the content repository, which the Worker
/// applies. That split is deliberate: a permission change should be a commit
/// someone can review, not a click in a console nobody can audit afterwards.
///
/// Two things this layer is careful about:
///
/// **The ID token is short-lived and never stored.** It is asked for per
/// request and Firebase refreshes it when it is about to expire. Keeping a
/// copy in local storage would be creating a credential with a long life out
/// of one designed to have a short one.
///
/// **A signed-in user is not an authorised user.** `signedIn` says Firebase
/// recognises them; `role` comes from the API, which reads the policy. The
/// interface must never infer permission from the former, so the two are
/// separate fields here rather than one.
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Who the API says we are, which is not the same as who Firebase says.
class Authorisation {
  const Authorisation({
    required this.signedIn,
    this.email,
    this.role,
    this.admin = false,
    this.emailVerified = false,
    this.availableRoles = const [],
  });

  const Authorisation.anonymous()
    : signedIn = false,
      email = null,
      role = null,
      admin = false,
      emailVerified = false,
      availableRoles = const [];

  factory Authorisation.fromJson(Map<String, dynamic> json) => Authorisation(
    signedIn: json['signedIn'] == true,
    email: json['email'] as String?,
    role: json['role'] as String?,
    admin: json['admin'] == true,
    emailVerified: json['emailVerified'] == true,
    availableRoles: [
      for (final item in (json['roles'] as List?) ?? const []) item.toString(),
    ],
  );

  final bool signedIn;
  final String? email;

  /// Null for a signed-in user who is not in `access.json`. That is a real and
  /// expected state -- someone with a Google account who has not been given
  /// access -- and the interface has to say so rather than look broken.
  final String? role;

  final bool admin;
  final bool emailVerified;
  final List<String> availableRoles;

  bool get authorised => signedIn && role != null;

  /// Whether this account can change anything at all. Not a substitute for
  /// asking the API: the policy is per-path, and this only decides whether to
  /// show an editing affordance at all.
  bool get mayWriteSomething =>
      authorised &&
      (role == 'owner' || role == 'editor' || role == 'translator');
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the API needs from a session: a token, and nothing else.
///
/// Narrowed to this on purpose. `DidactaApi` has no business being able to
/// sign a user in or out, and a dependency on the whole auth object made it
/// impossible to exercise the API without Firebase running.
abstract class TokenSource {
  Future<String?> idToken({bool forceRefresh = false});
}

/// The little the rest of the app needs to know about who is signed in.
///
/// A Firebase `User` carries far more than that, and depending on it would
/// make every layer above this one need Firebase to exist -- including in a
/// test that only wants to check a screen.
class SignedInUser {
  const SignedInUser({
    this.email,
    this.displayName,
    this.emailVerified = false,
  });

  final String? email;
  final String? displayName;
  final bool emailVerified;

  /// Who to attribute a commit to. Falls back to the address when there is no
  /// display name, and a commit with no author at all is better than one
  /// attributed to nobody in particular.
  ({String name, String email})? get commitAuthor =>
      email == null ? null : (name: displayName ?? email!, email: email!);
}

/// A session, as the app needs it: who is in it, when that changes, and a way
/// out. Implemented by [DidactaAuth] over Firebase.
abstract class AuthSession implements TokenSource {
  /// Fires whenever the signed-in user changes.
  Stream<void> get changes;

  SignedInUser? get user;

  bool get signedIn;

  Future<void> signOut();

  // Getting in. Part of the interface rather than of the Firebase class
  // alone, because the settings screen needs all of it and should not have to
  // know what implements it.

  Future<void> signInWithPassword(String email, String password);

  Future<void> signInWithGoogle();

  Future<void> createAccount(String email, String password);

  Future<void> sendPasswordReset(String email);

  Future<void> resendVerification();
}

/// Somewhere to keep a secret. Implemented by [TokenStore] over the OS
/// keychain; a test supplies its own.
abstract class SecretStore {
  /// Whether keeping a secret here is actually safe. False in a browser.
  bool get canStoreSafely;

  Future<String?> read();

  Future<void> write(String value);

  Future<void> clear();
}

/// An [AuthSession] for when Firebase is not there.
///
/// Not a defensive nicety: it is the normal state of the desktop build. There
/// is no `GoogleService-Info.plist` in it, Firebase does not come up, and it
/// does not need to -- a clone on your own disk takes its commit author from
/// git and never talks to the Worker.
///
/// It exists because the alternative bit hard. `DidactaAuth` reads
/// `FirebaseAuth.instance` in its constructor, so constructing it without
/// Firebase throws from `main` before `runApp` is ever reached: the window
/// opens and stays black, with the real reason only in a log nobody sees.
/// A null object that answers "nobody is signed in" turns that into a
/// working app that says what it cannot do.
class UnavailableAuth implements AuthSession {
  const UnavailableAuth([this.reason = 'Firebase no está configurado.']);

  /// Why, for the interface to show instead of an empty sign-in form.
  final String reason;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  SignedInUser? get user => null;

  @override
  bool get signedIn => false;

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => null;

  /// Signing out of nothing is a no-op, not an error: the interface may call
  /// it while tidying up and should not have to check first.
  @override
  Future<void> signOut() async {}

  @override
  Future<void> signInWithPassword(String email, String password) async =>
      throw AuthException(reason);

  @override
  Future<void> signInWithGoogle() async => throw AuthException(reason);

  @override
  Future<void> createAccount(String email, String password) async =>
      throw AuthException(reason);

  @override
  Future<void> sendPasswordReset(String email) async =>
      throw AuthException(reason);

  @override
  Future<void> resendVerification() async => throw AuthException(reason);
}

/// Sign-in, and the token the API needs.
class DidactaAuth implements AuthSession {
  DidactaAuth({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Stream<void> get changes => _auth.authStateChanges();

  /// The Firebase user, for the few places that need more than [user].
  User? get current => _auth.currentUser;

  @override
  SignedInUser? get user {
    final signedInUser = _auth.currentUser;
    if (signedInUser == null) return null;
    return SignedInUser(
      email: signedInUser.email,
      displayName: signedInUser.displayName,
      emailVerified: signedInUser.emailVerified,
    );
  }

  @override
  bool get signedIn => _auth.currentUser != null;

  /// A fresh ID token, or null when nobody is signed in.
  ///
  /// Not cached here: `getIdToken` returns the current one and refreshes it
  /// when it is close to expiring, which is exactly the behaviour wanted and
  /// exactly what a cache of our own would break.
  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } on FirebaseAuthException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  @override
  Future<void> signInWithPassword(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      final provider = GoogleAuthProvider()
        // Forces the account chooser. Without it a shared machine silently
        // reuses whoever signed in last, which for a permission-bearing
        // session is the wrong default.
        ..setCustomParameters({'prompt': 'select_account'});
      await _auth.signInWithPopup(provider);
    } on FirebaseAuthException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  /// Creates an account and immediately asks for the address to be verified.
  ///
  /// The API refuses writes from an unverified address, because an unverified
  /// address is one anybody can claim -- including one that appears in
  /// `access.json`.
  @override
  Future<void> createAccount(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _auth.currentUser?.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  @override
  Future<void> resendVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw AuthException(_describe(error));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  /// Firebase's codes turned into something a person can act on.
  ///
  /// Note what is *not* distinguished: a wrong password and an unknown address
  /// give the same message, because telling them apart tells a stranger which
  /// addresses have accounts.
  static String _describe(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Esa dirección no tiene forma de correo.';
      case 'user-disabled':
        return 'Esta cuenta está deshabilitada.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Correo o contraseña incorrectos.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese correo.';
      case 'weak-password':
        return 'La contraseña es demasiado corta.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera un momento.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Se ha cerrado la ventana de acceso.';
      case 'operation-not-allowed':
        // The most likely failure on a fresh project, and the one whose cause
        // is least guessable from a generic message.
        return 'Este método de acceso no está habilitado en el proyecto de '
            'Firebase. Actívalo en Authentication → Sign-in method.';
      case 'unauthorized-domain':
        return 'Este dominio no está autorizado en Firebase '
            '(Authentication → Settings → Authorized domains).';
      case 'network-request-failed':
        return 'No se ha podido contactar con Firebase.';
      default:
        return error.message ??
            'No se ha podido iniciar sesión (${error.code}).';
    }
  }
}

/// The authenticated side of the API.
///
/// Reads and writes go through the Worker, which holds the GitHub token. The
/// app never sees it, and there is no code path here that could.
class DidactaApi {
  DidactaApi({required this.base, required this.auth, http.Client? client})
    : _client = client ?? http.Client();

  /// The Worker's origin, e.g. `https://didacta-api.<subdomain>.workers.dev`.
  final String base;

  /// Where the ID token comes from. Only a [TokenSource]: this class must not
  /// be able to change the session it reads from.
  final TokenSource auth;

  final http.Client _client;

  Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = <String, String>{};
    final token = await auth.idToken();
    // Sent only when there is one: some paths are public, and the API decides
    // that, not this client.
    if (token != null) {
      headers['authorization'] = 'Bearer $token';
    }
    if (json) headers['content-type'] = 'application/json';
    return headers;
  }

  /// What the API says this caller may do. The authority on permissions.
  Future<Authorisation> whoAmI() async {
    final response = await _client.get(
      Uri.parse('$base/v1/me'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _message(response));
    }
    return Authorisation.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Whether the Worker is reachable and configured, for a diagnostics view.
  Future<Map<String, dynamic>> health() async {
    final response = await _client.get(Uri.parse('$base/v1/health'));
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _message(response));
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<RepositoryFile> readFile(String path) async {
    final uri = Uri.parse(
      '$base/v1/file',
    ).replace(queryParameters: {'path': path});
    final response = await _client.get(uri, headers: await _headers());
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _message(response));
    }
    return RepositoryFile.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Writes a file, passing back the sha that was read.
  ///
  /// The sha makes this a compare-and-set: if the file changed underneath, the
  /// API answers 409 and nobody's work is silently overwritten. Callers should
  /// surface that rather than retry.
  Future<RepositoryFile> writeFile({
    required String path,
    required String text,
    required String sha,
    String? message,
  }) async {
    final response = await _client.put(
      Uri.parse('$base/v1/file'),
      headers: await _headers(json: true),
      body: jsonEncode({
        'path': path,
        'text': text,
        'sha': sha,
        ?message == null ? null : 'message': message,
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _message(response));
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return RepositoryFile(
      path: body['path'] as String? ?? path,
      text: text,
      sha: body['sha'] as String? ?? '',
    );
  }

  static String _message(http.Response response) {
    try {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final error = body['error'];
      if (error is String && error.isNotEmpty) return error;
    } catch (_) {
      // Not JSON: fall through to something generic rather than showing the
      // raw body, which for a proxy error is a page of HTML.
    }
    return 'La API respondió ${response.statusCode}.';
  }
}

class RepositoryFile {
  const RepositoryFile({
    required this.path,
    required this.text,
    required this.sha,
  });

  factory RepositoryFile.fromJson(Map<String, dynamic> json) => RepositoryFile(
    path: json['path'] as String? ?? '',
    text: json['text'] as String? ?? '',
    sha: json['sha'] as String? ?? '',
  );

  final String path;
  final String text;

  /// The version this content was read at. Required to write it back.
  final String sha;
}

class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  /// A 409 means someone else changed the file; the caller has to re-read
  /// rather than retry, and the interface should say so in those words.
  bool get isConflict => status == 409;

  bool get isForbidden => status == 403;

  bool get isUnauthenticated => status == 401;

  @override
  String toString() => message;
}
