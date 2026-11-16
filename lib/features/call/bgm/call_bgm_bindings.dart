import '../webrtc_call_controller.dart';
import '../webrtc_group_call_controller.dart';
import 'call_bgm.dart';
import '../soundboard/call_soundboard_sheet.dart';
import 'call_bgm_sheet.dart';

/// 1対1の通話のBGM（Web以外はnull）。一対は2人とも流せる。
CallBgmBinding? oneToOneBgmBinding(WebrtcCallController controller) {
  if (!CallBgm.isSupported) return null;
  return CallBgmBinding(
    bgm: controller.bgm,
    controller: controller,
    otherPlayingTitle: () => controller.remoteBgmTitle,
  );
}

/// 広場の通話のBGM。[allowed]（`playBgm`権限）が無い、又はWeb以外はnull。
CallBgmBinding? groupBgmBinding(
  WebrtcGroupCallController controller, {
  required bool allowed,
}) {
  if (!CallBgm.isSupported || !allowed) return null;
  return CallBgmBinding(
    bgm: controller.bgm,
    controller: controller,
    otherPlayingTitle: () => controller.bgmPlayer?.bgmTitle,
  );
}

/// 1対1の通話のサウンドボード（Web以外はnull）。
CallSoundboardBinding? oneToOneSoundboardBinding(
  WebrtcCallController controller,
  String currentUserId,
) {
  if (!CallBgm.isSupported) return null;
  return CallSoundboardBinding(
    bgm: controller.bgm,
    isDm: true,
    conversationId: controller.call.dmId,
    userId: currentUserId,
  );
}

/// 広場の通話のサウンドボード（Web以外はnull。権限は不要で、メンバーなら誰でも使える）。
CallSoundboardBinding? groupSoundboardBinding(
  WebrtcGroupCallController controller,
  String groupId,
) {
  if (!CallBgm.isSupported) return null;
  return CallSoundboardBinding(
    bgm: controller.bgm,
    isDm: false,
    conversationId: groupId,
    userId: controller.currentUser.userId,
  );
}
