/// The Firebase web configuration.
///
/// **None of this is a secret**, and it matters that that is understood,
/// because the requirement for this platform was that secrets never live in
/// the public frontend.
///
/// A Firebase web API key is an identifier, not a credential: it names the
/// project so Google knows which one a request is for. It grants nothing on
/// its own. What actually protects the material is:
///
/// * the sign-in providers enabled on the project, which decide who can get a
///   token at all;
/// * the authorised domains, which decide where a sign-in may be started from;
/// * `access.json` in the content repository, which decides what a signed-in
///   person may see and change;
/// * the GitHub token, which is a Worker secret and never leaves it.
///
/// Google's own documentation says API keys for Firebase services may be
/// included in client code. The credential that must never be here is a
/// service-account private key, and there is none.
///
/// Generated from `firebase apps:sdkconfig WEB`. Regenerate rather than edit.
library;

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDn2NmODMBH1EM7c51RjWHDhG9SThGfvhg',
    appId: '1:1022169859591:web:34c21a1d7c80d241c34ca2',
    messagingSenderId: '1022169859591',
    projectId: 'didacta-uv',
    authDomain: 'didacta-uv.firebaseapp.com',
    storageBucket: 'didacta-uv.firebasestorage.app',
  );

  /// The project id, also needed by the API layer so it can check that a token
  /// was minted for *this* project. Kept next to the options so the two cannot
  /// drift.
  static const String projectId = 'didacta-uv';
}
