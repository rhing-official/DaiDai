import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/auth_repository.dart';
import '../repositories/direct_message_repository.dart';
import '../repositories/group_repository.dart';
import '../repositories/user_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return FirestoreUserRepository();
});

final directMessageRepositoryProvider = Provider<DirectMessageRepository>((ref) {
  return FirestoreDirectMessageRepository();
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return FirestoreGroupRepository();
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});
