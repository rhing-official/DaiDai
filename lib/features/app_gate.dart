import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';
import 'calendar/calendar_sync_bootstrap.dart';
import 'call/group_incoming_call_listener.dart';
import 'call/incoming_call_listener.dart';
import 'home/home_screen.dart';
import 'push_notification_bootstrap.dart';

/// アプリのルート画面。認証状態・Rhing ID登録状態に応じて表示を切り替える
/// （実体は[AuthGate]。ログイン済みならホーム画面を表示する）。
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthGate(
      builder: (context, currentUser) => PushNotificationBootstrap(
        currentUserId: currentUser.userId,
        child: CalendarSyncBootstrap(
          currentUserId: currentUser.userId,
          child: IncomingCallListener(
            currentUserId: currentUser.userId,
            child: GroupIncomingCallListener(
              currentUser: currentUser,
              child: HomeScreen(currentUser: currentUser),
            ),
          ),
        ),
      ),
    );
  }
}
