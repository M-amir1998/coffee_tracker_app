import 'package:coffee_tracker/app/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The current auth session; emits on sign-in, sign-out and token refresh.
final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final repository = ref.watch(authRepositoryProvider);
  yield repository.currentSession;
  yield* repository.authStateChanges().map((state) => state.session);
});

/// The signed-in user's id, or null when signed out.
final currentUserIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authSessionProvider);
  return session.value?.user.id ?? ref.watch(authRepositoryProvider).currentUser?.id;
});

/// Set when the user opened a password-recovery link (web/mobile), so the
/// router can show the "choose a new password" screen.
final passwordRecoveryProvider = NotifierProvider<PasswordRecoveryController, bool>(PasswordRecoveryController.new);

class PasswordRecoveryController extends Notifier<bool> {
  @override
  bool build() {
    final subscription = ref.watch(authRepositoryProvider).authStateChanges().listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) this.state = true;
    });
    ref.onDispose(subscription.cancel);
    return false;
  }

  void start() => state = true;

  void finish() => state = false;
}
