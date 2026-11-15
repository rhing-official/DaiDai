/// 広場の通話で、ICEが確立しないまま固まった接続の復旧の判断（2026-11-15）。
///
/// 入室直後の1回目の接続が、相手の候補の取りこぼし等で固まり、誰かが抜けるまで送受信できない
/// ことがあった。PeerConnectionを作ってから[timeout]以内に確立しなければ、まずICEを
/// 再起動し、それでも確立しなければ接続を作り直す。作り直しは[maxRecreates]回まで。
enum PeerWatchdogAction { none, restartIce, recreate, giveUp }

const peerWatchdogTimeout = Duration(seconds: 8);
const peerWatchdogMaxRecreates = 2;

/// [established]は確立済みか。[sinceStageStart]は今の段階（作った直後／ICE再起動の後）を
/// 始めてからの経過。[iceRestarted]は今の接続でICE再起動をもう試したか。
/// [recreates]はこのペアでこれまでに作り直した回数。
PeerWatchdogAction peerWatchdogAction({
  required bool established,
  required Duration sinceStageStart,
  required bool iceRestarted,
  required int recreates,
  Duration timeout = peerWatchdogTimeout,
  int maxRecreates = peerWatchdogMaxRecreates,
}) {
  if (established || sinceStageStart < timeout) return PeerWatchdogAction.none;
  if (!iceRestarted) return PeerWatchdogAction.restartIce;
  if (recreates >= maxRecreates) return PeerWatchdogAction.giveUp;
  return PeerWatchdogAction.recreate;
}
