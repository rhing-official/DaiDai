import '../webrtc_call_controller.dart';
import '../webrtc_group_call_controller.dart';
import 'call_bgm.dart';
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

/// 広場の通話のBGM。[allowed]（`playBgm`権限）が無い、またはWeb以外はnull。
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
