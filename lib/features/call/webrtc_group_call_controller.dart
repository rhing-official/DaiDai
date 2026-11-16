import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_user.dart';
import '../../models/group_call.dart';
import '../../repositories/group_call_repository.dart';
import 'call_log.dart';
import 'ice_diagnostics.dart';
import 'call_sound_player.dart';
import 'acquire_with_video_fallback.dart';
import 'peer_answer_match.dart';
import 'peer_connect_guard.dart';
import 'peer_watchdog.dart';
import 'screen_share.dart';
import 'send_gain.dart';
import 'rtc_config.dart';
import '../../utils/page_exit/page_exit.dart';
import 'audio_route.dart';
import 'bgm/bgm_storage.dart';
import 'bgm/bgm_now_playing.dart';
import 'mic_busy.dart';
import 'mic_denoiser.dart';
import '../../providers/bgm_preferences_provider.dart';
import 'bgm/bgm_queue.dart';
import 'bgm/call_bgm.dart';
import 'webrtc_media_constraints.dart';

enum GroupCallConnectionState { connecting, active, ended }

/// 参加者毎の在室確認ハートビートの送信間隔。
const _presenceHeartbeatInterval = Duration(seconds: 15);

/// これより長くハートビートが途絶えた参加者は離脱扱いにする。
const _presenceStaleAfter = kGroupCallPresenceStaleAfter;

/// 広場（グループ）通話のWebRTCシグナリング・複数`RTCPeerConnection`の
/// ライフサイクルを管理する。メッシュ型P2Pの為、参加者が増減するたびに
/// 自分以外の全参加者との接続を動的に張り直す。通話毎に1つ生成され、
/// `lib/features/call/active_call_session.dart`の`activeCallSessionProvider`が
/// 所有する（2026-08-19変更、以前は`GroupCallScreen`が`initState`/`dispose`で
/// 生成・破棄していたが、PC埋め込み表示・ピン留めミニ表示に対応するため
/// 画面のマウント状態から寿命を切り離した）。破棄は`state`が
/// `GroupCallConnectionState.ended`になったことを検知した
/// `activeCallSessionProvider`側でのみ行う。
class WebrtcGroupCallController extends ChangeNotifier {
  WebrtcGroupCallController({
    required this.groupCallId,
    required this.currentUser,
    required bool isVideo,
    required GroupCallRepository groupCallRepository,
    IceServersLoader? iceServersLoader,
    this.bgmPreferences = const BgmPreferences(),
    this.onBgmPreferencesChanged,
    this.onBgmLastPlayedChanged,
  }) : _isVideo = isVideo,
       _repository = groupCallRepository,
       _iceServersLoader = iceServersLoader;

  final String groupCallId;
  final AppUser currentUser;
  final GroupCallRepository _repository;

  /// BGMの前回の状態（音量・再生順）と、変えた時の保存（2026-11-16）。
  final BgmPreferences bgmPreferences;
  final void Function(double volume, BgmPlayOrder order)?
  onBgmPreferencesChanged;
  final void Function(BgmLastPlayed last)? onBgmLastPlayedChanged;

  /// 中継（TURN）の認証情報の取得（nullならSTUNのみ、2026-10-21）。
  final IceServersLoader? _iceServersLoader;

  /// 現在ビデオ通話として動作しているか（通話中の音声⇔ビデオ切替を
  /// 反映する可変の状態。コンストラクタの`isVideo`は開始時点の初期値）。
  bool _isVideo;
  bool get isVideo => _isVideo;
  bool _localRendererInitialized = false;

  bool _switchingCallType = false;
  bool get switchingCallType => _switchingCallType;

  /// 映像をオンにできなかった（カメラが他で使用中・許可が無い等、2026-11-03）。
  /// 数秒後、又は次に切り替えた時に消える。画面が注意書きを出す。
  bool _videoFailed = false;
  bool get videoFailed => _videoFailed;
  Timer? _videoFailedTimer;

  void _setVideoFailed(bool value) {
    _videoFailedTimer?.cancel();
    _videoFailed = value;
    if (value) {
      _videoFailedTimer = Timer(const Duration(seconds: 8), () {
        _videoFailed = false;
        notifyListeners();
      });
    }
  }

  /// ビデオ通話時の自分のカメラプレビュー用。音声のみの通話では使わない。
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  /// 相手毎のリモート映像（音声のみの通話でも、音声再生の為に
  /// レンダラー自体は保持する）。UI側はこのMapのキー（=相手のuserId）を
  /// 元にグリッドを組む。
  final Map<String, RTCVideoRenderer> remoteRenderers = {};

  // 画面共有（配信、2026-11-15）。取得した画面は[_screenDisplay]、相手へ送る時の入れ物（ストリーム）は
  // [_screenContainer]で、共有を止めて始め直しても同じ（相手のストリームが変わらず、送信側は
  // `replaceTrack`で差し替えるだけで済む）。
  MediaStream? _screenDisplay;
  MediaStream? _screenContainer;
  ScreenShareQuality _screenQuality = ScreenShareQuality.standard;

  /// 画面共有を始める時に、自動でマイクをミュートにしたか（やめる時に戻す）。
  bool _mutedByScreenShare = false;

  /// 相手の画面共有の音声の音量（0〜1）。
  double _remoteScreenVolume = 1;
  double get remoteScreenVolume => _remoteScreenVolume;
  ScreenShareQuality get screenQuality => _screenQuality;
  bool _screenAudio = false;
  bool get isScreenSharing => _screenDisplay != null;

  /// 「音声も共有」を求めたのに、音が取れなかった（ブラウザ・共有する対象による）。
  bool screenAudioMissing = false;

  /// 自分の配信のプレビュー用（音は出さない）。
  final RTCVideoRenderer localScreenRenderer = RTCVideoRenderer();
  bool _localScreenRendererInitialized = false;

  /// 共有している画面の映像のトラック（共有していなければnull。自分のプレビューの静止画の取得に使う）。
  MediaStreamTrack? get screenVideoTrack =>
      _screenDisplay?.getVideoTracks().firstOrNull;

  /// 他の参加者の配信（画面）の映像・音声。カメラとは別のストリームで届く。
  final Map<String, RTCVideoRenderer> screenRenderers = {};

  /// 相手の最初に届いたストリーム＝カメラ・マイク。これと違うストリームが画面。
  final Map<String, String> _cameraStreamIds = {};
  final Map<String, RTCRtpSender> _screenVideoSenders = {};
  final Map<String, RTCRtpSender> _screenAudioSenders = {};

  /// [p]の配信を画面に出してよいか（配信中と申告し、映像も届いている）。
  /// （2026-11-16: 映像のストリームが届くのを待たず、配信中と申告された時点でウィンドウを出す。
  /// ストリームは再ネゴシエーションを経て数秒遅れて届く。映像を出せるかは[remoteScreenReady]。）
  bool remoteScreenShown(CallParticipant p) => p.screenLabel != null;

  /// [p]の画面のストリームが描画の部品に入っていて、映像を出せるか。
  bool remoteScreenReady(CallParticipant p) =>
      p.screenLabel != null && screenRenderers[p.userId]?.srcObject != null;

  /// 配信と申告されてから20秒経っても、映像が届かなかったか（案内を出す）。
  bool remoteScreenTimedOut(CallParticipant p) =>
      p.screenLabel != null &&
      !remoteScreenReady(p) &&
      _screenTimedOut.contains(p.userId);
  final Set<String> _screenTimedOut = {};
  final Map<String, Timer> _screenTimeouts = {};
  final Map<String, Stopwatch> _screenOnWatch = {};

  /// 相手ごとに最後に受け取った画面のストリーム。共有をやめて再開した時、送信側は`replaceTrack`で
  /// 差し替えるだけで`onTrack`が来ない為、これを描画の部品へ入れ直す。
  final Map<String, MediaStream> _remoteScreenStreams = {};

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, StreamSubscription> _peerLinkSubs = {};
  final Map<String, StreamSubscription> _peerCandidateSubs = {};

  // peerLink（相手1人ぶんのペア）のoffer/answerフィールドは初回接続時の
  // 1回きりではなく、通話中の音声⇔ビデオ切替のたびに上書きされる。
  // 「新着かどうか」は一意な採番ではなくSDP文字列そのものの差分で判定し、
  // 自分が直前に送った値でも既に適用済みの値でも無い場合だけ相手からの
  // 新規オファー/アンサーとして扱う（1対1のWebrtcCallControllerと同じ設計）。
  final Map<String, String?> _pendingLocalOfferSdp = {};

  /// 自分が最後に送ったofferのid。answerは、このidへの返事だけを適用する（`peer_answer_match.dart`）。
  final Map<String, String?> _pendingLocalOfferId = {};
  final Map<String, String?> _pendingLocalAnswerSdp = {};
  final Map<String, String?> _lastAppliedOfferSdp = {};
  final Map<String, String?> _lastAppliedAnswerSdp = {};

  // setRemoteDescriptionが完了するより先にICE candidateが届くと、
  // addCandidateが例外を投げて無言で失われてしまう競合状態があった為、
  // 相手毎に完了するまで候補をバッファし、完了後にまとめて適用する。
  // watchPeerCandidatesは毎回累積リスト全体を再送してくる為、適用済みの
  // 候補をキーで重複排除する。
  final Map<String, bool> _remoteDescriptionSet = {};
  final Map<String, List<Map<String, dynamic>>> _pendingRemoteCandidates = {};
  final Map<String, Set<String>> _appliedCandidateKeys = {};

  /// 相手毎のICE接続状態に問題があるか（failed/disconnected）。
  /// UI側はこれを見て、シグナリングは完了しているのに実際には映像/音声が
  /// 流れていない参加者のタイルに控えめな表示を重ねる。
  final Map<String, bool> peerConnectionIssues = {};

  // ICEが確立しないまま固まった接続の見張り（[peerWatchdogAction]、2026-11-15）。
  final Map<String, Timer> _watchdogs = {};
  final Map<String, DateTime> _watchStageStart = {};
  final Map<String, bool> _watchIceRestarted = {};
  final Set<String> _iceEstablished = {};

  /// [userId]との音声・映像の通り道（ICE）が確立したか。確立するまでの数秒は、参加していても
  /// 音声も映像も届かない為、画面は「接続中」を出す（2026-11-16）。
  bool isPeerEstablished(String userId) => _iceEstablished.contains(userId);

  /// このペアで、固まって接続を作り直した回数（確立したら0に戻す）。作り直しをまたいで保つ。
  final Map<String, int> _watchRecreates = {};

  /// 相手の候補の数（診断用: 受信・適用・失敗）。
  final Map<String, List<int>> _candidateCounts = {};

  /// この参加（端末1台ぶん）を区別する値（2026-10-21追加）。参加者ドキュメントの
  /// `sessionId`に書き、他の値になったら別の端末に乗っ取られたとして通話から抜ける。
  final String _sessionId = _newSessionId();

  /// 相手毎の、つながっている相手の`sessionId`。変わったら（相手が別の端末で
  /// 入り直したら）古い接続を切ってつなぎ直す。
  final Map<String, String?> _peerSessionIds = {};

  static String _newSessionId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  MediaStream? _localStream;

  /// マイクのノイズ除去（RNNoise、Webで設定がオンの時だけ）。
  MicDenoiser? _micDenoiser;
  StreamSubscription<List<CallParticipant>>? _participantsSub;
  Timer? _presenceTimer;

  /// 参加者の入退室ブリップ再生。
  final _soundPlayer = CallSoundPlayer();
  Set<String> _previousLiveOtherIds = {};
  bool _hasReceivedFirstSnapshot = false;

  GroupCallConnectionState _state = GroupCallConnectionState.connecting;
  GroupCallConnectionState get state => _state;

  /// スピーカーで鳴らしているか。LINEと同じく、音声通話は受話口、映像通話は
  /// スピーカーから始める（2026-11-01変更、以前はどちらもスピーカー）。
  late bool _speakerOn = _isVideo;
  bool get speakerOn => _speakerOn;

  /// Bluetooth・有線ヘッドセットなど外部のオーディオに接続中か（2026-11-01追加）。
  /// 接続中は出力先をOSに任せ、スピーカー/受話口の切替ボタンも出さない。
  bool _externalAudio = false;
  bool get showSpeakerToggle =>
      isSpeakerToggleCapablePlatform && !_externalAudio;
  bool _watchingAudioDevices = false;

  Future<void> _refreshExternalAudio() async {
    final external = await hasExternalAudioOutput();
    if (_state == GroupCallConnectionState.ended || external == _externalAudio)
      return;
    _externalAudio = external;
    await _applySpeakerphone(_speakerOn);
    notifyListeners();
  }

  void _watchAudioDevices() {
    if (_watchingAudioDevices || !isSpeakerToggleCapablePlatform) return;
    _watchingAudioDevices = true;
    navigator.mediaDevices.ondevicechange = (_) =>
        unawaited(_refreshExternalAudio());
    unawaited(_refreshExternalAudio());
  }

  /// 直前に使っていたカメラの`deviceId`。映像をオフ→オンした時に同じカメラで
  /// 取り直す（2026-10-31追加）。
  String? _cameraDeviceId;

  void Function()? _removePageExitListener;

  bool _switchingCamera = false;
  bool get switchingCamera => _switchingCamera;

  /// 現在のカメラが前面（インカメラ）かどうか（2026-08-30追加、
  /// `webrtc_call_controller.dart`の同名フィールドと同じ考え方）。
  bool _isFrontCamera = true;

  /// 自分のプレビューを左右反転する（前面カメラ）かの、画面に出す値。カメラを切り替えた直後は、
  /// 新しいカメラの最初の映像が出るまで少し間があり、その間に反転だけが先に切り替わって
  /// 古い映像が一瞬反転して見えた為、反転の切り替えを遅らせる（2026-11-16）。
  bool _mirrorFront = true;
  Timer? _mirrorTimer;
  bool get isFrontCamera => _mirrorFront;

  List<CallParticipant> _participants = [];

  /// 通話のBGM（2026-11-03、Webのみ）。流している間は、マイクと曲を混ぜたトラックを
  /// 全ての相手へ送る。
  late final CallBgm bgm = CallBgm(
    storage: createBgmStorage(),
    micTrack: () => _localStream?.getAudioTracks().firstOrNull,
    replaceOutgoingAudio: _replaceOutgoingAudio,
    initialVolume: bgmPreferences.volume,
    initialOrder: bgmPreferences.order,
    onPreferencesChanged: onBgmPreferencesChanged,
    onLastPlayedChanged: onBgmLastPlayedChanged,
    onPlayingChanged: (nowPlaying) => _repository
        .updateParticipantState(
          groupCallId: groupCallId,
          userId: currentUser.userId,
          bgmTitle: nowPlaying?.title,
          bgmPaused: nowPlaying?.paused,
          bgmCover: nowPlaying?.thumbBase64,
          clearBgm: nowPlaying == null,
        )
        .catchError((_) {}),
  )..addListener(notifyListeners);

  Future<void> _replaceOutgoingAudio(MediaStreamTrack track) async {
    for (final pc in _peerConnections.values) {
      for (final sender in await pc.getSenders()) {
        if (sender.track?.kind == 'audio') await sender.replaceTrack(track);
      }
    }
  }

  /// 映像トラックが実際に届いて流れている相手（2026-11-03）。相手が申告した
  /// `isVideo`だけで映像の枠を出すと、トラックが届かない間は中身の無い透明な画面になる。
  final Set<String> _remoteVideoReady = {};

  /// [p]の映像を画面に出してよいか（相手が映像オンと申告し、トラックも届いている）。
  bool remoteVideoShown(CallParticipant p) =>
      p.isVideo && _remoteVideoReady.contains(p.userId);

  void _setRemoteVideoReady(String userId, bool ready) {
    final changed = ready
        ? _remoteVideoReady.add(userId)
        : _remoteVideoReady.remove(userId);
    if (changed) notifyListeners();
  }

  /// 今BGMを流している他の参加者（いなければnull）。
  /// 他の参加者が流している曲の表示用の情報（いなければnull）。
  BgmNowPlaying? get remoteBgm {
    final p = bgmPlayer;
    final title = p?.bgmTitle;
    if (p == null || title == null) return null;
    return BgmNowPlaying(
      title: title,
      paused: p.bgmPaused,
      thumb: BgmNowPlaying.thumbFromBase64(p.bgmCover),
    );
  }

  CallParticipant? get bgmPlayer =>
      remoteParticipants.firstWhereOrNull((p) => p.bgmTitle != null);

  /// 自分以外の参加者（ハートビートが途絶えている＝離脱扱いの相手は除く）。
  List<CallParticipant> get remoteParticipants => _participants
      .where((p) => p.userId != currentUser.userId && !_isStale(p))
      .toList();

  /// ピン留めミニ表示・PC埋め込み表示で「代表1人」として映す相手。
  /// 直近に発声した相手（[_lastRemoteSpeakerId]、発声が止んでも次に誰かが話す
  /// まで保つ。2026-11-01変更、以前は常に「映像onで最初の相手」で固定されていた）。
  /// まだ誰も話していない間は従来の代理指標（映像onかつミュートしていない最初の
  /// 相手 → 映像onの最初の相手）を使い、それも無ければ`null`。
  CallParticipant? get pinnedParticipant {
    final lastSpeakerId = _lastRemoteSpeakerId;
    if (lastSpeakerId != null) {
      final speaker = remoteParticipants.firstWhereOrNull(
        (p) => p.userId == lastSpeakerId,
      );
      if (speaker != null) return speaker;
    }
    return remoteParticipants.firstWhereOrNull(
          (p) => p.isVideo && !p.micMuted,
        ) ??
        remoteParticipants.firstWhereOrNull((p) => p.isVideo);
  }

  String? _lastRemoteSpeakerId;

  bool _isStale(CallParticipant participant) {
    final lastSeenAt = participant.lastSeenAt;
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt.toDate()) > _presenceStaleAfter;
  }

  bool _muted = false;
  bool get muted => _muted;

  /// いま発声している参加者（自分を含む、2026-10-31追加）。通話タイルを緑の枠で
  /// 囲むのに使う。flutter_webrtcに音声レベルのイベントは無い為、
  /// [_speakingPollInterval]毎に`getStats()`の`audioLevel`を見て判定する。
  Set<String> _speakingUserIds = const {};
  Set<String> get speakingUserIds => _speakingUserIds;
  Timer? _speakingTimer;
  bool _pollingSpeaking = false;

  static const _speakingPollInterval = Duration(milliseconds: 500);

  /// 0〜1の音声レベルがこれを超えたら発声中とみなす。
  static const _speakingThreshold = 0.02;

  Future<void> _pollSpeaking() async {
    if (_pollingSpeaking || _state != GroupCallConnectionState.active) return;
    _pollingSpeaking = true;
    try {
      final speaking = <String>{};
      for (final entry in [..._peerConnections.entries]) {
        List<StatsReport> reports;
        try {
          reports = await entry.value.getStats();
        } catch (_) {
          continue;
        }
        for (final report in reports) {
          final level = double.tryParse('${report.values['audioLevel']}');
          if (level == null || level <= _speakingThreshold) continue;
          final kind = report.values['kind'] ?? report.values['mediaType'];
          if (kind != null && kind != 'audio') continue;
          if (report.type == 'inbound-rtp') {
            speaking.add(entry.key);
          } else if ((report.type == 'media-source' ||
                  report.type == 'outbound-rtp') &&
              !_muted) {
            speaking.add(currentUser.userId);
          }
        }
      }
      if (_state != GroupCallConnectionState.active) return;
      // 直近に話した相手を覚える。今の話者が話し続けている間は切り替えない。
      final remoteSpeakers = speaking.where((id) => id != currentUser.userId);
      final lastBefore = _lastRemoteSpeakerId;
      if (remoteSpeakers.isNotEmpty && !remoteSpeakers.contains(lastBefore)) {
        _lastRemoteSpeakerId = remoteSpeakers.first;
      }
      if (!setEquals(speaking, _speakingUserIds) ||
          lastBefore != _lastRemoteSpeakerId) {
        _speakingUserIds = speaking;
        notifyListeners();
      }
    } finally {
      _pollingSpeaking = false;
    }
  }

  /// 前後（イン/アウト）カメラ切替ボタンの表示可否に使う、映像入力
  /// デバイスの台数（2026-08-19追加）。`getUserMedia`成功後（＝端末の
  /// カメラ利用許可が下りた後）にだけ正確に取得出来る為、映像取得の
  /// 直後（[initialize]・[_enableLocalVideoTrackForAllPeers]）に1回だけ
  /// 取得し直す（継続的な監視は行わない）。
  int? _localCameraCount;
  bool get hasMultipleCameras => (_localCameraCount ?? 0) >= 2;

  Future<void> _refreshCameraCount() async {
    try {
      _localCameraCount = (await Helper.cameras).length;
      notifyListeners();
    } catch (_) {
      // 取得に失敗しても前後切替ボタンを出さないだけで通話自体は継続する。
    }
  }

  String? _error;
  String? get error => _error;

  /// 他のアプリ（別の通話など）にマイクを奪われ、声が届かない状態か（2026-11-16）。
  /// ミュートとは別。OSが自分のマイクを無音にした（Android）／ブラウザがマイクを止めた（Web）時。
  bool _micUnavailable = false;
  bool get micUnavailable => _micUnavailable;

  /// 通話に入る時に、他のアプリがマイクを使っていた（注意を出す。数秒で消える）。
  bool _micBusyAtJoin = false;
  bool get micBusyAtJoin => _micBusyAtJoin;
  Timer? _micBusyAtJoinTimer;

  void setMicUnavailable(bool value) {
    if (_micUnavailable == value) return;
    _micUnavailable = value;
    callLog('group: mic unavailable: $value');
    _repository
        .updateParticipantState(
          groupCallId: groupCallId,
          userId: currentUser.userId,
          micUnavailable: value,
        )
        .catchError((_) {});
    notifyListeners();
  }

  /// 生のマイクのトラックが、ブラウザに止められた（他のアプリがマイクを使っている）か（Web）。
  void _watchMicTrack(MediaStream? stream) {
    if (!kIsWeb) return;
    final track = stream?.getAudioTracks().firstOrNull;
    if (track == null) return;
    track.onMute = () => setMicUnavailable(true);
    track.onUnMute = () => setMicUnavailable(false);
  }

  Future<void> initialize() async {
    try {
      // 音声制約はプラットフォーム毎の既知の問題を踏まえて
      // webrtc_media_constraints.dartに集約している（本格的なRNNoise統合は
      // フェーズ3の別プロジェクト。詳細は会話参照）。
      // 映像を求められてもカメラが使えなければ、音声のみで参加する（2026-10-23）。
      // 他のアプリがマイクを使っていたら、数秒だけ注意を出す（自分の録音を始める前に調べる）。
      if (await isMicBusyNow()) {
        _micBusyAtJoin = true;
        callLog('group: mic is busy by another app at join');
        _micBusyAtJoinTimer?.cancel();
        _micBusyAtJoinTimer = Timer(const Duration(seconds: 8), () {
          _micBusyAtJoin = false;
          notifyListeners();
        });
        notifyListeners();
      }
      final denoise = await shouldDenoiseMic();
      final acquired = await acquireWithVideoFallback(
        wantVideo: _isVideo,
        acquire: (video) => navigator.mediaDevices.getUserMedia({
          'audio': buildAudioConstraints(rnnoise: denoise),
          'video': video
              ? buildVideoConstraints(
                  frontCamera: _isFrontCamera,
                  deviceId: _cameraDeviceId,
                )
              : false,
        }),
      );
      _localStream = acquired.stream;
      _isVideo = acquired.usedVideo;
      await ensureEchoCancellation(_localStream);
      _watchMicTrack(_localStream);
      _micDenoiser = await applyMicDenoise(_localStream, denoise);

      if (_isVideo) {
        await localRenderer.initialize();
        _localRendererInitialized = true;
        localRenderer.srcObject = _localStream;
        muteLocalPlayback(localRenderer);
        _syncCameraFromStream();
        unawaited(_refreshCameraCount());
      }

      await _repository.joinGroupCall(
        groupCallId: groupCallId,
        user: currentUser,
        isVideo: _isVideo,
        sessionId: _sessionId,
      );

      _state = GroupCallConnectionState.active;
      notifyListeners();
      unawaited(_applySpeakerphoneWithRetry());

      _speakingTimer = Timer.periodic(
        _speakingPollInterval,
        (_) => unawaited(_pollSpeaking()),
      );

      // タブを閉じた時も参加者として残らないよう、退出を試みる（Webのみ）。
      _removePageExitListener = onPageExit(() => unawaited(leave()));

      _presenceTimer = Timer.periodic(_presenceHeartbeatInterval, (_) {
        // 別の端末が同じ通話に入り直していたら（購読が届かなかった時の保険）、この端末は抜ける。
        _repository
            .touchPresence(
              groupCallId: groupCallId,
              userId: currentUser.userId,
              sessionId: _sessionId,
            )
            .then((stillMine) {
              if (!stillMine) _endByTakeover('heartbeat');
            })
            .catchError((Object e) {
              callLog('group: presence heartbeat failed: $e');
            });
        // ハートビート失効による離脱反映は新しいFirestoreスナップショットが
        // 来ないと再評価されない為、定期的にUIへ再描画を促す。
        notifyListeners();
      });

      // 自分以外の参加者の音声⇔ビデオ状態はCallParticipant.isVideo
      // （このStream経由で届く）を見るだけで、こちらの映像トラックには
      // 一切触れない（切替は本人側にのみ適用される。setVideoEnabled参照）。
      _subscribeParticipants();
    } catch (e) {
      _error = '通話を開始出来ませんでした（マイク・カメラの利用を許可して下さい）: $e';
      _state = GroupCallConnectionState.ended;
      notifyListeners();
    }
  }

  void _subscribeParticipants() {
    _participantsSub?.cancel();
    _participantsSub = _repository
        .watchParticipants(groupCallId)
        .listen(
          _onParticipants,
          onError: (Object e) {
            // 購読がエラーで終わると、別端末への乗っ取りなどを検知できなくなる為、再購読する。
            callLog('group: participants watch error: $e');
            Future<void>.delayed(const Duration(seconds: 3), () {
              if (_state != GroupCallConnectionState.ended) {
                _subscribeParticipants();
              }
            });
          },
        );
  }

  /// 同じアカウントの別の端末が、同じ通話に入り直した。参加者ドキュメントは新しい端末のものなので
  /// 消さず、この端末だけ通話から抜ける（[via]は検知した経路のログ用）。
  void _endByTakeover(String via) {
    if (_state == GroupCallConnectionState.ended) return;
    callLog('group: session taken over by another device (via $via)');
    _presenceTimer?.cancel();
    _participantsSub?.cancel();
    _state = GroupCallConnectionState.ended;
    notifyListeners();
  }

  void _onParticipants(List<CallParticipant> participants) {
    if (_state == GroupCallConnectionState.ended) return;

    // 同じアカウントの別の端末が、同じ通話に入り直した（自分の参加者ドキュメントの
    // sessionIdが自分のものでなくなった）。参加者ドキュメントは新しい端末のものなので
    // 消さず、この端末だけ通話から抜ける（2026-10-21追加）。
    final mine = participants.firstWhereOrNull(
      (p) => p.userId == currentUser.userId,
    );
    if (isSessionTakenOver(
      mySessionId: _sessionId,
      participantSessionId: mine?.sessionId,
    )) {
      _endByTakeover('snapshot');
      return;
    }

    // 同時に流せるのは1人。他の参加者が流し始めたら、自分のは止める。
    if (bgm.playing &&
        participants.any(
          (p) => p.userId != currentUser.userId && p.bgmTitle != null,
        ) &&
        !_participants.any(
          (p) => p.userId != currentUser.userId && p.bgmTitle != null,
        )) {
      unawaited(bgm.stop());
    }
    _participants = participants;

    final liveOtherIds = participants
        .where((p) => p.userId != currentUser.userId && !_isStale(p))
        .map((p) => p.userId)
        .toSet();

    // 参加者リストそのものの出現/消失を検知して入退室音を鳴らす
    // （_peerConnections.keysとの差分だと接続確立タイミングに引きずられる為、
    // 別途スナップショットを保持する）。初回スナップショットは既に居た人を
    // 「新規参加」と誤検知しないよう無音でシードする（Discordと同じ挙動）。
    if (!_hasReceivedFirstSnapshot) {
      _hasReceivedFirstSnapshot = true;
      _previousLiveOtherIds = liveOtherIds;
    } else {
      if (liveOtherIds.difference(_previousLiveOtherIds).isNotEmpty) {
        _soundPlayer.playJoinBlip();
      }
      if (_previousLiveOtherIds.difference(liveOtherIds).isNotEmpty) {
        _soundPlayer.playLeaveBlip();
      }
      _previousLiveOtherIds = liveOtherIds;
    }

    // 相手が別の端末で入り直した（sessionIdが変わった）ら、古い端末との接続を
    // 切って、つなぎ直す。
    for (final p in participants) {
      if (!liveOtherIds.contains(p.userId)) continue;
      final known = _peerSessionIds[p.userId];
      if (_peerConnections.containsKey(p.userId) &&
          p.sessionId != null &&
          known != null &&
          known != p.sessionId) {
        _disconnectFromPeer(p.userId);
      }
      _peerSessionIds[p.userId] = p.sessionId;
    }
    // 配信をやめた相手の画面は片付ける（再開すると、同じストリームで届き直す）。
    for (final p in participants) {
      if (p.userId == currentUser.userId) continue;
      if (p.screenLabel == null) {
        final screen = screenRenderers[p.userId];
        if (screen != null) screen.srcObject = null;
        _screenTimeouts.remove(p.userId)?.cancel();
        _screenTimedOut.remove(p.userId);
        _screenOnWatch.remove(p.userId)?.stop();
        continue;
      }
      // 配信が始まった（または再開した）。
      if (!_screenOnWatch.containsKey(p.userId)) {
        _screenOnWatch[p.userId] = Stopwatch()..start();
        callLog('group: ${p.userId} screen: on received');
        _screenTimeouts[p.userId] = Timer(const Duration(seconds: 20), () {
          final still = remoteScreenReady(p);
          if (!still) {
            _screenTimedOut.add(p.userId);
            callLog('group: ${p.userId} screen: stream did not arrive in 20s');
            notifyListeners();
          }
        });
      }
      // 2回目以降の共有（`onTrack`が来ない）は、前のストリームを入れ直す。
      final screen = screenRenderers[p.userId];
      final kept = _remoteScreenStreams[p.userId];
      if (screen != null && screen.srcObject == null && kept != null) {
        screen.srcObject = kept;
        callLog('group: ${p.userId} screen: re-attached the kept stream');
      }
    }
    for (final userId in liveOtherIds) {
      if (!_peerConnections.containsKey(userId) &&
          !_connectGuard.isConnecting(userId)) {
        _connectToPeer(userId);
      }
    }
    for (final userId in [..._peerConnections.keys]) {
      if (!liveOtherIds.contains(userId)) {
        _disconnectFromPeer(userId);
      }
    }

    notifyListeners();
  }

  /// 同じ相手への接続処理の重複を防ぐ（[PeerConnectGuard]参照）。
  final _connectGuard = PeerConnectGuard();

  Future<void> _connectToPeer(String otherUserId) async {
    if (!_connectGuard.tryBegin(otherUserId)) return;
    try {
      await _connectToPeerOnce(otherUserId);
    } catch (e) {
      // 途中で失敗した接続を残さない（残ると「接続済み」と見なされ、再試行されない）。
      callLog('group: $otherUserId connect failed: $e');
      _disconnectFromPeer(otherUserId);
    } finally {
      _connectGuard.end(otherUserId);
    }
  }

  Future<void> _connectToPeerOnce(String otherUserId) async {
    final isUserA = currentUser.userId.compareTo(otherUserId) < 0;
    final pairId = CallPeerLink.idFor(currentUser.userId, otherUserId);

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final turnWatch = Stopwatch()..start();
    final configuration = await loadRtcConfiguration(_iceServersLoader);
    callLog(
      'group: $otherUserId TURN fetched ${turnWatch.elapsedMilliseconds}ms '
      '(iceServers=${(configuration['iceServers'] as List?)?.length})',
    );
    callLog(
      'group: $otherUserId iceServers='
      '${summarizeIceServers(configuration['iceServers'])}',
    );
    final peerConnection = await createPeerConnection(configuration);
    final connectWatch = Stopwatch()..start();
    // 待っている間に相手が退室した・通話を抜けた場合は、作ったものを閉じて中断する。
    if (_connectGuard.isCancelled(otherUserId) ||
        _state == GroupCallConnectionState.ended) {
      await peerConnection.close();
      await renderer.dispose();
      return;
    }
    remoteRenderers[otherUserId] = renderer;
    _peerConnections[otherUserId] = peerConnection;
    _remoteDescriptionSet[otherUserId] = false;
    _pendingRemoteCandidates[otherUserId] = [];
    _appliedCandidateKeys[otherUserId] = {};
    _startWatchdog(otherUserId, peerConnection);

    for (final track in _localStream!.getTracks()) {
      // BGMを流している間に入ってきた相手には、マイクの代わりに混合トラックを送る。
      final mixed = bgm.mixedTrack;
      await peerConnection.addTrack(
        track.kind == 'audio' && mixed != null ? mixed : track,
        _localStream!,
      );
    }
    // 今画面を共有していれば、入ってきた相手にも画面を送る（カメラの後に追加する。受信側は
    // 最初のストリームをカメラとして扱う）。
    if (_screenDisplay != null) {
      await _attachScreenTracks(otherUserId, peerConnection);
    }
    // カメラ無し・カメラオフで入る時も、相手の映像を受け取れるようにする。映像の送信用の
    // トラックが無いと、最初のofferに映像の枠が無く、こちらが映像をオンにして再ネゴシエーション
    // するまで、相手の映像が届かない。
    if (_localStream!.getVideoTracks().isEmpty) {
      try {
        await peerConnection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      } catch (e) {
        callLog('group: $otherUserId recvonly video transceiver failed: $e');
      }
    }

    peerConnection.onTrack = (event) {
      callLog(
        'group: $otherUserId onTrack kind=${event.track.kind} '
        'streams=${event.streams.length} muted=${event.track.muted}',
      );
      // 最初に届いたストリームがカメラ・マイク。違うストリームは相手の画面共有。
      final streamId = event.streams.firstOrNull?.id;
      if (streamId != null) {
        final cameraId = _cameraStreamIds[otherUserId] ??= streamId;
        if (streamId != cameraId) {
          unawaited(_attachRemoteScreen(otherUserId, event.streams.first));
          return;
        }
      }
      if (event.track.kind == 'video') {
        final track = event.track;
        _setRemoteVideoReady(otherUserId, track.muted != true);
        track.onUnMute = () => _setRemoteVideoReady(otherUserId, true);
        track.onMute = () => _setRemoteVideoReady(otherUserId, false);
        track.onEnded = () => _setRemoteVideoReady(otherUserId, false);
      }
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
        final voice = _voiceVolumes[otherUserId];
        if (voice != null && voice < 1) {
          unawaited(renderer.setVolume(voice).catchError((_) {}));
        }
      }
    };
    peerConnection.onSignalingState = (state) =>
        callLog('group: $otherUserId signaling=$state');
    peerConnection.onConnectionState = (state) =>
        callLog('group: $otherUserId connection=$state');
    peerConnection.onIceGatheringState = (state) => callLog(
      'group: $otherUserId iceGathering=$state '
      '(${connectWatch.elapsedMilliseconds}ms)',
    );

    peerConnection.onIceConnectionState = (iceState) {
      callLog(
        'group: $otherUserId ice=$iceState '
        '(${connectWatch.elapsedMilliseconds}ms)',
      );
      if (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (_iceEstablished.add(otherUserId)) notifyListeners();
        _watchRecreates.remove(otherUserId);
        final counts = _candidateCounts[otherUserId];
        if (counts != null) {
          callLog(
            'group: $otherUserId remoteCandidates received=${counts[0]} '
            'applied=${counts[1]} failed=${counts[2]}',
          );
        }
      }
      if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        unawaited(logIceStats(peerConnection, 'group: $otherUserId'));
      }
      final issue =
          iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected;
      if (peerConnectionIssues[otherUserId] != issue) {
        peerConnectionIssues[otherUserId] = issue;
        notifyListeners();
      }
    };

    peerConnection.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      callLog(
        'group: $otherUserId local candidate '
        '${summarizeIceCandidate(candidate.candidate)}',
      );
      _repository.addPeerCandidate(
        groupCallId: groupCallId,
        pairId: pairId,
        isUserA: isUserA,
        candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    // peerLinkを先に作ってから、相手のICE candidateを購読する。candidateの読み取りルールは
    // peerLinkのドキュメントを参照する為、先に購読するとpermission-deniedで購読が終わり
    // （Firestoreは自動で再購読しない）、相手のcandidateが届かないまま、見張りが8秒×2回待って
    // 接続を作り直すまで、通信が確立しなかった（2026-11-16、実機ログのremoteCandidates received=0）。
    await _repository.initiatePeerLink(
      groupCallId: groupCallId,
      userAId: currentUser.userId,
      userBId: otherUserId,
    );
    _subscribePeerCandidates(
      otherUserId: otherUserId,
      pairId: pairId,
      isUserA: isUserA,
      peerConnection: peerConnection,
    );

    // peerLinkのoffer/answerは初回接続時の1回だけでなく、通話中の音声⇔
    // ビデオ切替（setVideoEnabled/_reconcileGroupVideoTo参照）のたびに
    // 上書きされる。「新着かどうか」はSDP文字列の差分で判定し、自分が
    // 直前に送った値でも既に適用済みの値でも無い場合だけ相手からの新規
    // オファー/アンサーとして扱う。初回接続時のオファー役（userA/userB）は
    // 同時オファーによる衝突を避ける為の決め事に過ぎず、通話中の再
    // ネゴシエーションはどちらの役割からでも開始出来る。
    _peerLinkSubs[otherUserId] = _repository
        .watchPeerLink(groupCallId: groupCallId, pairId: pairId)
        .listen((link) async {
          if (link == null) return;

          final offerSdp = link.offer?['sdp'] as String?;
          // 相手の前回の参加（別のsessionId）が残したofferは、適用しない。
          final offerSid = link.offer?['sid'] as String?;
          final peerSid = _peerSessionIds[otherUserId];
          final staleOffer =
              offerSid != null && peerSid != null && offerSid != peerSid;
          if (staleOffer && offerSdp != _lastAppliedOfferSdp[otherUserId]) {
            _lastAppliedOfferSdp[otherUserId] = offerSdp;
            callLog('group: $otherUserId stale offer ignored');
          } else if (offerSdp != null &&
              offerSdp != _pendingLocalOfferSdp[otherUserId] &&
              offerSdp != _lastAppliedOfferSdp[otherUserId]) {
            _lastAppliedOfferSdp[otherUserId] = offerSdp;
            callLog(
              'group: $otherUserId offer received sdp=${offerSdp.length} '
              'signaling=${peerConnection.signalingState}',
            );
            try {
              await _applyRemotePeerOffer(
                otherUserId,
                peerConnection,
                link.offer!,
              );
            } catch (e) {
              callLog('group: $otherUserId offer apply failed: $e');
            }
          }

          final answerSdp = link.answer?['sdp'] as String?;
          if (answerSdp != null &&
              answerSdp != _pendingLocalAnswerSdp[otherUserId] &&
              answerSdp != _lastAppliedAnswerSdp[otherUserId]) {
            _lastAppliedAnswerSdp[otherUserId] = answerSdp;
            // 前回の参加の古いanswerは、自分の最新のofferへの返事ではないので適用しない。
            final answerFor = link.answer?['forOffer'] as String?;
            if (!shouldApplyAnswer(
              answerFor: answerFor,
              pendingOfferId: _pendingLocalOfferId[otherUserId],
            )) {
              callLog('group: $otherUserId stale answer ignored');
              return;
            }
            callLog(
              'group: $otherUserId answer applying sdp=${answerSdp.length} '
              'signaling=${peerConnection.signalingState}',
            );
            try {
              await peerConnection.setRemoteDescription(
                RTCSessionDescription(
                  answerSdp,
                  link.answer!['type'] as String,
                ),
              );
            } catch (e) {
              callLog('group: $otherUserId answer apply failed: $e');
              return;
            }
            _flushPendingCandidates(otherUserId, peerConnection);
          }
        });

    if (isUserA) {
      await _createAndSendPeerOffer(otherUserId, peerConnection);
    }
  }

  /// 相手のICE candidateを購読する。購読が失敗しても終わりにせず、少し待って張り直す
  /// （Firestoreの購読はエラーで終了する）。接続を作り直した後の古い購読には何もしない。
  void _subscribePeerCandidates({
    required String otherUserId,
    required String pairId,
    required bool isUserA,
    required RTCPeerConnection peerConnection,
    int attempt = 0,
  }) {
    _peerCandidateSubs[otherUserId]?.cancel();
    _peerCandidateSubs[otherUserId] = _repository
        .watchPeerCandidates(
          groupCallId: groupCallId,
          pairId: pairId,
          isUserA: isUserA,
        )
        .listen(
          (candidates) {
            for (final data in candidates) {
              _applyOrBufferCandidate(otherUserId, peerConnection, data);
            }
          },
          onError: (Object e) {
            callLog('group: $otherUserId candidates watch failed: $e');
            if (attempt >= 5) return;
            Future.delayed(const Duration(seconds: 1), () {
              if (!identical(_peerConnections[otherUserId], peerConnection))
                return;
              _subscribePeerCandidates(
                otherUserId: otherUserId,
                pairId: pairId,
                isUserA: isUserA,
                peerConnection: peerConnection,
                attempt: attempt + 1,
              );
            });
          },
        );
  }

  Future<void> _applyRemotePeerOffer(
    String otherUserId,
    RTCPeerConnection peerConnection,
    Map<String, dynamic> offerMap,
  ) async {
    await peerConnection.setRemoteDescription(
      RTCSessionDescription(
        offerMap['sdp'] as String,
        offerMap['type'] as String,
      ),
    );
    _flushPendingCandidates(otherUserId, peerConnection);
    final answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);
    _pendingLocalAnswerSdp[otherUserId] = answer.sdp;
    await _repository.setPeerAnswer(
      groupCallId: groupCallId,
      pairId: CallPeerLink.idFor(currentUser.userId, otherUserId),
      answer: {
        'sdp': answer.sdp,
        'type': answer.type,
        // どのofferへの返事か（相手が、自分の最新のofferへの返事だけを適用するため）。
        if (offerMap['id'] is String) 'forOffer': offerMap['id'],
      },
    );
  }

  Future<void> _createAndSendPeerOffer(
    String otherUserId,
    RTCPeerConnection peerConnection, {
    bool iceRestart = false,
  }) async {
    // Webは`iceRestart`、ネイティブは`mandatory.IceRestart`を見る（互いに他方は無視する）。
    final offer = await peerConnection.createOffer(
      iceRestart
          ? {
              'iceRestart': true,
              'mandatory': {'IceRestart': true},
            }
          : <String, dynamic>{},
    );
    await peerConnection.setLocalDescription(offer);
    callLog(
      'group: $otherUserId offer sent sdp=${offer.sdp?.length} '
      'signaling=${peerConnection.signalingState}',
    );
    _pendingLocalOfferSdp[otherUserId] = offer.sdp;
    final offerId = newOfferId();
    _pendingLocalOfferId[otherUserId] = offerId;
    await _repository.setPeerOffer(
      groupCallId: groupCallId,
      pairId: CallPeerLink.idFor(currentUser.userId, otherUserId),
      offer: {
        'sdp': offer.sdp,
        'type': offer.type,
        'id': offerId,
        'sid': _sessionId,
      },
    );
  }

  void _applyOrBufferCandidate(
    String otherUserId,
    RTCPeerConnection peerConnection,
    Map<String, dynamic> data,
  ) {
    final key =
        '${data['candidate']}|${data['sdpMid']}|${data['sdpMLineIndex']}';
    final appliedKeys = _appliedCandidateKeys[otherUserId] ??= {};
    if (appliedKeys.contains(key)) return;
    if (_remoteDescriptionSet[otherUserId] != true) {
      (_pendingRemoteCandidates[otherUserId] ??= []).add(data);
      return;
    }
    // 適用に成功してから「適用済み」に入れる（失敗した候補は、次に届いた時に再試行する）。
    final counts = _candidateCounts[otherUserId] ??= [0, 0, 0];
    counts[0]++;
    peerConnection
        .addCandidate(
          RTCIceCandidate(
            data['candidate'] as String,
            data['sdpMid'] as String?,
            data['sdpMLineIndex'] as int?,
          ),
        )
        .then((_) {
          appliedKeys.add(key);
          counts[1]++;
        })
        .catchError((Object e) {
          // 相手のPeerConnectionが既に閉じている等。通話自体は継続させる。
          counts[2]++;
          callLog('group: $otherUserId addCandidate failed: $e');
        });
  }

  void _flushPendingCandidates(
    String otherUserId,
    RTCPeerConnection peerConnection,
  ) {
    _remoteDescriptionSet[otherUserId] = true;
    final pending = [...?_pendingRemoteCandidates[otherUserId]];
    _pendingRemoteCandidates[otherUserId]?.clear();
    for (final data in pending) {
      _applyOrBufferCandidate(otherUserId, peerConnection, data);
    }
  }

  void _stopWatchdog(String otherUserId) {
    _watchdogs.remove(otherUserId)?.cancel();
    _watchStageStart.remove(otherUserId);
    _watchIceRestarted.remove(otherUserId);
    _iceEstablished.remove(otherUserId);
    _candidateCounts.remove(otherUserId);
  }

  /// 接続を作った時から、確立するまで見張る。固まっていれば、ICE再起動→作り直しで復旧する。
  void _startWatchdog(String otherUserId, RTCPeerConnection peerConnection) {
    _stopWatchdog(otherUserId);
    _watchStageStart[otherUserId] = DateTime.now();
    _watchIceRestarted[otherUserId] = false;
    _watchdogs[otherUserId] = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_state == GroupCallConnectionState.ended ||
          _peerConnections[otherUserId] != peerConnection) {
        _stopWatchdog(otherUserId);
        return;
      }
      final action = peerWatchdogAction(
        established: _iceEstablished.contains(otherUserId),
        sinceStageStart: DateTime.now().difference(
          _watchStageStart[otherUserId] ?? DateTime.now(),
        ),
        iceRestarted: _watchIceRestarted[otherUserId] ?? false,
        recreates: _watchRecreates[otherUserId] ?? 0,
      );
      if (action == PeerWatchdogAction.none) return;
      final counts = _candidateCounts[otherUserId] ?? const [0, 0, 0];
      callLog(
        'group: $otherUserId ice stuck state=${peerConnection.iceConnectionState} '
        'remoteCandidates received=${counts[0]} applied=${counts[1]} '
        'failed=${counts[2]} action=${action.name}',
      );
      switch (action) {
        case PeerWatchdogAction.restartIce:
          _watchIceRestarted[otherUserId] = true;
          _watchStageStart[otherUserId] = DateTime.now();
          // オファー役（userA）が、新しいufragのofferを送る。相手は通常の再ネゴシエーションとして受ける。
          if (currentUser.userId.compareTo(otherUserId) < 0) {
            unawaited(
              _createAndSendPeerOffer(
                otherUserId,
                peerConnection,
                iceRestart: true,
              ).catchError((Object e) {
                callLog('group: $otherUserId ice restart failed: $e');
              }),
            );
          }
        case PeerWatchdogAction.recreate:
          _watchRecreates[otherUserId] =
              (_watchRecreates[otherUserId] ?? 0) + 1;
          callLog('group: $otherUserId recreate peer');
          _disconnectFromPeer(otherUserId);
          _connectToPeer(otherUserId);
        case PeerWatchdogAction.giveUp:
          callLog('group: $otherUserId giving up');
          _watchdogs.remove(otherUserId)?.cancel();
          peerConnectionIssues[otherUserId] = true;
          notifyListeners();
        case PeerWatchdogAction.none:
          break;
      }
    });
  }

  void _disconnectFromPeer(String otherUserId) {
    _stopWatchdog(otherUserId);
    _cameraStreamIds.remove(otherUserId);
    _screenVideoSenders.remove(otherUserId);
    _screenAudioSenders.remove(otherUserId);
    _screenRendererInit.remove(otherUserId);
    _remoteScreenStreams.remove(otherUserId);
    _screenVolumes.remove(otherUserId);
    _voiceVolumes.remove(otherUserId);
    _screenTimeouts.remove(otherUserId)?.cancel();
    _screenTimedOut.remove(otherUserId);
    _screenOnWatch.remove(otherUserId);
    final screen = screenRenderers.remove(otherUserId);
    if (screen != null) unawaited(screen.dispose());
    _connectGuard.cancel(otherUserId);
    _peerLinkSubs.remove(otherUserId)?.cancel();
    _peerCandidateSubs.remove(otherUserId)?.cancel();
    _peerConnections.remove(otherUserId)?.close();
    remoteRenderers.remove(otherUserId)?.dispose();
    _remoteDescriptionSet.remove(otherUserId);
    _pendingRemoteCandidates.remove(otherUserId);
    _appliedCandidateKeys.remove(otherUserId);
    _pendingLocalOfferSdp.remove(otherUserId);
    _pendingLocalOfferId.remove(otherUserId);
    _pendingLocalAnswerSdp.remove(otherUserId);
    _lastAppliedOfferSdp.remove(otherUserId);
    _lastAppliedAnswerSdp.remove(otherUserId);
    peerConnectionIssues.remove(otherUserId);
    _remoteVideoReady.remove(otherUserId);
  }

  Future<void> leave() async {
    if (_state == GroupCallConnectionState.ended) return;
    // 1対1の`hangUp`と同じく、先に自分の画面を閉じる。Firestoreの退出処理
    // （直列に3〜4往復、回線が悪いと長い）を待たせない（2026-11-13）。
    final id = groupCallId;
    final userId = currentUser.userId;
    final sessionId = _sessionId;
    _state = GroupCallConnectionState.ended;
    notifyListeners();
    await _repository.leaveGroupCall(
      groupCallId: id,
      userId: userId,
      sessionId: sessionId,
    );
  }

  void toggleMute() {
    _muted = !_muted;
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    _repository.updateParticipantState(
      groupCallId: groupCallId,
      userId: currentUser.userId,
      micMuted: _muted,
    );
    notifyListeners();
  }

  // ---- 画面共有（配信、2026-11-15） ----

  /// 相手ごとの、画面の描画の部品の用意（映像と音声のトラックが別々に届いても、1つにまとめる）。
  final Map<String, Future<RTCVideoRenderer>> _screenRendererInit = {};

  Future<RTCVideoRenderer> _createScreenRenderer(String userId) async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    screenRenderers[userId] = renderer;
    return renderer;
  }

  Future<void> _attachRemoteScreen(String userId, MediaStream stream) async {
    final renderer = await (_screenRendererInit[userId] ??=
        _createScreenRenderer(userId));
    // 届くたびに入れ直す（Webの描画の部品は、入れた時点のトラックを控える為、後から届いた
    // 音声のトラックを取り込むのに必要）。
    renderer.srcObject = stream;
    renderer.muted = false;
    _remoteScreenStreams[userId] = stream;
    _screenTimeouts.remove(userId)?.cancel();
    _screenTimedOut.remove(userId);
    unawaited(renderer.setVolume(screenVolumeOf(userId)).catchError((_) {}));
    callLog(
      'group: $userId screen stream attached video='
      '${stream.getVideoTracks().length} audio=${stream.getAudioTracks().length} '
      'after=${_screenOnWatch[userId]?.elapsedMilliseconds}ms since screen on',
    );
    notifyListeners();
  }

  /// [pc]へ画面のトラックを送る。初めてなら追加（`true`＝再ネゴシエーションが要る）、既に送信の
  /// 枠があれば差し替えだけ（`false`）。
  Future<bool> _attachScreenTracks(String userId, RTCPeerConnection pc) async {
    final display = _screenDisplay;
    final container = _screenContainer;
    if (display == null || container == null) return false;
    var renegotiate = false;
    final video = display.getVideoTracks().firstOrNull;
    if (video != null) {
      final sender = _screenVideoSenders[userId];
      if (sender == null) {
        final added = await pc.addTrack(video, container);
        _screenVideoSenders[userId] = added;
        await ScreenShareCapture.applySenderLimits(added, _screenQuality);
        renegotiate = true;
      } else {
        await sender.replaceTrack(video);
        await ScreenShareCapture.applySenderLimits(sender, _screenQuality);
      }
    }
    final audio = display.getAudioTracks().firstOrNull;
    if (audio != null) {
      final sender = _screenAudioSenders[userId];
      final outgoing = _screenGain?.track ?? audio;
      if (sender == null) {
        _screenAudioSenders[userId] = await pc.addTrack(outgoing, container);
        renegotiate = true;
      } else {
        await sender.replaceTrack(outgoing);
      }
    }
    return renegotiate;
  }

  Future<void> _renegotiateAll(Iterable<String> userIds) async {
    for (final userId in userIds) {
      final pc = _peerConnections[userId];
      if (pc == null) continue;
      try {
        await _createAndSendPeerOffer(userId, pc);
      } catch (e) {
        callLog('group: $userId screen re-offer failed: $e');
      }
    }
  }

  void _setScreenLabelOnServer(String? label) {
    _repository
        .updateParticipantState(
          groupCallId: groupCallId,
          userId: currentUser.userId,
          screenLabel: label,
          clearScreen: label == null,
        )
        .catchError((_) {});
  }

  /// 相手の画面共有の音声の音量を変える（0〜1、全員分に掛かる。個別の値は上書きする）。
  Future<void> setRemoteScreenVolume(double volume) async {
    _remoteScreenVolume = volume.clamp(0.0, 1.0);
    _screenVolumes.clear();
    for (final renderer in screenRenderers.values) {
      try {
        await renderer.setVolume(_remoteScreenVolume);
      } catch (_) {}
    }
    notifyListeners();
  }

  // ---- 音量（2026-11-16）。聞こえる側は全プラットフォーム、送る側（マイク・共有する音）はWebのみ ----

  /// 相手ごとの共有音声の音量（未設定は[remoteScreenVolume]）。
  final Map<String, double> _screenVolumes = {};
  double screenVolumeOf(String userId) =>
      _screenVolumes[userId] ?? _remoteScreenVolume;

  Future<void> setScreenVolumeOf(String userId, double volume) async {
    final v = volume.clamp(0.0, 1.0);
    _screenVolumes[userId] = v;
    try {
      await screenRenderers[userId]?.setVolume(v);
    } catch (_) {}
    notifyListeners();
  }

  /// 相手ごとの声の音量（未設定は1）。
  final Map<String, double> _voiceVolumes = {};
  double voiceVolumeOf(String userId) => _voiceVolumes[userId] ?? 1;

  Future<void> setVoiceVolumeOf(String userId, double volume) async {
    final v = volume.clamp(0.0, 1.0);
    _voiceVolumes[userId] = v;
    try {
      await remoteRenderers[userId]?.setVolume(v);
    } catch (_) {}
    notifyListeners();
  }

  double _micVolume = 1;
  double get micVolume => _micVolume;
  SendGain? _micGain;
  Future<void>? _micGainInit;

  /// 相手へ送る自分のマイクの音量（0〜1、Webのみ。[SendGain.isSupported]）。動かすまでは、
  /// マイクの音の経路は変えない（初めて1未満にした時にだけ、ゲインを通す）。
  Future<void> setMicVolume(double volume) async {
    _micVolume = volume.clamp(0.0, 1.0);
    notifyListeners();
    if (!SendGain.isSupported) return;
    if (_micGain == null && _micVolume < 1) {
      _micGainInit ??= _attachMicGain();
      await _micGainInit;
    }
    _micGain?.setGain(_micVolume);
  }

  Future<void> _attachMicGain() async {
    final stream = _localStream;
    final old = stream?.getAudioTracks().firstOrNull;
    if (stream == null || old == null) return;
    final gain = await SendGain.attach(old);
    if (gain == null) return;
    _micGain = gain;
    // ミュートは、ストリームの音声トラックの`enabled`で行っている為、処理後のトラックへ引き継ぐ。
    gain.track.enabled = !_muted;
    await stream.removeTrack(old);
    await stream.addTrack(gain.track);
    for (final pc in [..._peerConnections.values]) {
      for (final sender in await pc.getSenders()) {
        if (sender.track?.id == old.id) {
          try {
            await sender.replaceTrack(gain.track);
          } catch (e) {
            callLog('group: mic gain replaceTrack failed: $e');
          }
        }
      }
    }
    callLog('group: mic gain on');
  }

  double _screenSendVolume = 1;
  double get screenSendVolume => _screenSendVolume;
  SendGain? _screenGain;

  /// 相手へ送る共有音声の音量（0〜1、Webのみ）。
  Future<void> setScreenSendVolume(double volume) async {
    _screenSendVolume = volume.clamp(0.0, 1.0);
    notifyListeners();
    await _applyScreenGain();
  }

  Future<void> _applyScreenGain() async {
    if (!SendGain.isSupported) return;
    final audio = _screenDisplay?.getAudioTracks().firstOrNull;
    if (audio == null) return;
    if (_screenGain == null && _screenSendVolume < 1) {
      final gain = await SendGain.attach(audio);
      if (gain == null) return;
      _screenGain = gain;
      for (final sender in [..._screenAudioSenders.values]) {
        try {
          await sender.replaceTrack(gain.track);
        } catch (e) {
          callLog('group: screen gain replaceTrack failed: $e');
        }
      }
    }
    _screenGain?.setGain(_screenSendVolume);
  }

  /// 誰かの画面共有が見えているか（音量の調整を出す条件）。
  bool get anyRemoteScreenShown => remoteParticipants.any(remoteScreenShown);

  /// 画面の共有を始める。配信元の選択はブラウザが出す。やめた（キャンセル）時は`false`。
  Future<bool> startScreenShare({
    required ScreenShareQuality quality,
    required bool shareAudio,
    bool muteMic = false,
  }) async {
    if (_screenDisplay != null) return true;
    final display = await ScreenShareCapture.start(
      quality,
      shareAudio: shareAudio,
    );
    if (display == null) return false;
    _screenDisplay = display;
    // 共有元が閉じられたら、共有も終える（`await`の前に付けて、取りこぼさない）。
    ScreenShareCapture.watchEnded(display, () => stopScreenShare());
    unawaited(_applyScreenGain());
    _screenQuality = quality;
    _screenAudio = shareAudio;
    // 音楽だけを届けたい時は、共有している間だけ自分のマイクをミュートにする。
    if (muteMic && !_muted) {
      toggleMute();
      _mutedByScreenShare = true;
    }
    _screenContainer ??= await createLocalMediaStream('screen');
    screenAudioMissing = shareAudio && display.getAudioTracks().isEmpty;
    if (screenAudioMissing) {
      callLog('group: screen audio was not available');
    }
    if (!_localScreenRendererInitialized) {
      await localScreenRenderer.initialize();
      _localScreenRendererInitialized = true;
    }
    localScreenRenderer.srcObject = display;
    final changed = <String>[];
    for (final entry in [..._peerConnections.entries]) {
      try {
        if (await _attachScreenTracks(entry.key, entry.value)) {
          changed.add(entry.key);
        }
      } catch (e) {
        callLog('group: ${entry.key} attach screen failed: $e');
      }
    }
    _setScreenLabelOnServer(quality.label);
    callLog(
      'group: screen share started ${quality.label} '
      'video=${display.getVideoTracks().length} '
      'audio=${display.getAudioTracks().length} '
      'surface=${ScreenShareCapture.surfaceOf(display)}',
    );
    notifyListeners();
    await _renegotiateAll(changed);
    return true;
  }

  /// 画面の共有をやめる（送信の枠は残し、中身だけ外す。次に始める時は差し替えで済む）。
  Future<void> stopScreenShare() async {
    final display = _screenDisplay;
    if (display == null) return;
    _screenDisplay = null;
    unawaited(ScreenShareCapture.notifyNativeStopped());
    if (_mutedByScreenShare) {
      _mutedByScreenShare = false;
      if (_muted) toggleMute();
    }
    for (final sender in [
      ..._screenVideoSenders.values,
      ..._screenAudioSenders.values,
    ]) {
      try {
        await sender.replaceTrack(null);
      } catch (_) {}
    }
    for (final track in display.getTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    localScreenRenderer.srcObject = null;
    final gain = _screenGain;
    _screenGain = null;
    if (gain != null) unawaited(gain.dispose());
    _setScreenLabelOnServer(null);
    callLog('group: screen share stopped');
    notifyListeners();
  }

  /// 配信元を選び直す（送信は止めず、トラックを差し替える）。
  Future<void> changeScreenSource() async {
    final old = _screenDisplay;
    if (old == null) return;
    final next = await ScreenShareCapture.start(
      _screenQuality,
      shareAudio: _screenAudio,
    );
    if (next == null) return;
    _screenDisplay = next;
    ScreenShareCapture.watchEnded(next, () => stopScreenShare());
    localScreenRenderer.srcObject = next;
    // 共有する音の音量は、新しいトラックに掛け直す。
    final oldGain = _screenGain;
    _screenGain = null;
    if (oldGain != null) unawaited(oldGain.dispose());
    unawaited(_applyScreenGain());
    final changed = <String>[];
    for (final entry in [..._peerConnections.entries]) {
      try {
        if (await _attachScreenTracks(entry.key, entry.value)) {
          changed.add(entry.key);
        }
      } catch (e) {
        callLog('group: ${entry.key} change screen failed: $e');
      }
    }
    for (final track in old.getTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    notifyListeners();
    await _renegotiateAll(changed);
  }

  /// 画面共有の音声を、共有中に切り替える。切る時は音のトラックを外す。入れる時は、音声を含めて
  /// 配信元を選び直す（取得し直さないと、音声のトラックが得られない）。
  Future<void> setScreenAudio(bool shareAudio) async {
    _screenAudio = shareAudio;
    final display = _screenDisplay;
    if (display == null) return;
    if (shareAudio) {
      await changeScreenSource();
      return;
    }
    for (final sender in _screenAudioSenders.values) {
      try {
        await sender.replaceTrack(null);
      } catch (_) {}
    }
    for (final track in display.getAudioTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// 配信の画質を変える（配信中なら、取得の制約と送信の上限にも反映する）。
  Future<void> setScreenQuality(ScreenShareQuality quality) async {
    _screenQuality = quality;
    final track = _screenDisplay?.getVideoTracks().firstOrNull;
    if (track != null) {
      track.enabled = !quality.audioOnly;
      try {
        await track.applyConstraints(
          ScreenShareCapture.constraints(quality, shareAudio: false)['video']
              as Map<String, dynamic>,
        );
      } catch (_) {}
      for (final sender in _screenVideoSenders.values) {
        await ScreenShareCapture.applySenderLimits(sender, quality);
      }
      _setScreenLabelOnServer(quality.label);
    }
    notifyListeners();
  }

  /// 通話中に音声通話⇔ビデオ通話を切り替える（1対1の
  /// `WebrtcCallController.setVideoEnabled`と同じ考え方）。メッシュ型P2Pの
  /// ため、現在つながっている全てのピアに対して個別に映像トラックの追加/
  /// 削除と再ネゴシエーション（新しいオファー送信）を行う。切り替えは
  /// 自分側にのみ適用され、他の参加者の映像トラックには一切触れない
  /// （相手はCallParticipant.isVideoの変化をUI表示にのみ使う）。
  Future<void> setVideoEnabled(bool enabled) async {
    if (enabled == _isVideo || _switchingCallType) return;
    _switchingCallType = true;
    _setVideoFailed(false);
    notifyListeners();
    callLog('group: setVideoEnabled($enabled) start');
    try {
      // カメラの取得・トラックの追加に成功してから、他の参加者へ`isVideo`を知らせる
      // （以前は先に書いていた為、取得に失敗しても他の人には「映像オン」に見えた）。
      await _reconcileGroupVideoTo(enabled);
      await _repository.updateParticipantState(
        groupCallId: groupCallId,
        userId: currentUser.userId,
        isVideo: enabled,
      );
      callLog('group: setVideoEnabled($enabled) done');
    } catch (e) {
      callLog('group: setVideoEnabled($enabled) failed: $e');
      if (enabled) {
        await _rollbackLocalVideo();
        _setVideoFailed(true);
      }
    } finally {
      _switchingCallType = false;
      notifyListeners();
    }
  }

  /// 映像のオンに失敗した時、途中まで進んだ状態（取得済みのカメラ・追加済みのトラック）を
  /// 片付け、映像オフの状態へ戻す。
  Future<void> _rollbackLocalVideo() async {
    try {
      await _disableLocalVideoTrackForAllPeers();
    } catch (e) {
      callLog('group: video rollback failed: $e');
    }
    _isVideo = false;
  }

  /// 自分の映像トラックの有無を[target]に合わせ、現在つながっている
  /// 全ピアに対して新しいオファーを送って再ネゴシエーションする
  /// （[setVideoEnabled]からのみ呼ばれる）。
  Future<void> _reconcileGroupVideoTo(bool target) async {
    if (target == _isVideo) return;
    if (target) {
      await _enableLocalVideoTrackForAllPeers();
    } else {
      await _disableLocalVideoTrackForAllPeers();
    }
    _isVideo = target;
    notifyListeners();
    // 1人との再ネゴシエーションに失敗しても、他の相手へは送り続ける。
    for (final entry in [..._peerConnections.entries]) {
      try {
        await _createAndSendPeerOffer(entry.key, entry.value);
      } catch (e) {
        callLog('group: ${entry.key} re-offer failed: $e');
      }
    }
  }

  Future<void> _enableLocalVideoTrackForAllPeers() async {
    if (_localStream?.getVideoTracks().isEmpty ?? true) {
      final videoStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': buildVideoConstraints(
          frontCamera: _isFrontCamera,
          deviceId: _cameraDeviceId,
        ),
      });
      final firstTrack = videoStream.getVideoTracks().first;
      logVideoTrackSettings(firstTrack, 'group');
      _localStream?.addTrack(firstTrack);
    }
    if (!_localRendererInitialized) {
      await localRenderer.initialize();
      _localRendererInitialized = true;
    }
    localRenderer.srcObject = _localStream;
    muteLocalPlayback(localRenderer);
    final track = _localStream!.getVideoTracks().first;
    for (final entry in [..._peerConnections.entries]) {
      try {
        // 前回の途中失敗で既に追加済みの相手へは、二重に追加しない（例外になり、
        // 以後の再試行も毎回失敗していた）。
        final senders = await entry.value.getSenders();
        if (senders.any((s) => s.track?.id == track.id)) continue;
        await entry.value.addTrack(track, _localStream!);
      } catch (e) {
        callLog('group: ${entry.key} addTrack(video) failed: $e');
      }
    }
    _syncCameraFromStream();
    unawaited(_refreshCameraCount());
  }

  Future<void> _disableLocalVideoTrackForAllPeers() async {
    final videoTracks = [...?_localStream?.getVideoTracks()];
    for (final pc in _peerConnections.values) {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await pc.removeTrack(sender);
        }
      }
    }
    for (final track in videoTracks) {
      _localStream?.removeTrack(track);
      await track.stop();
    }
    localRenderer.srcObject = null;
  }

  Future<void> _applySpeakerphone(bool enable) async {
    if (kIsWeb) return; // Webはブラウザの既定オーディオ出力に依存し対象外。
    try {
      // 外部のオーディオに接続中は、スピーカーを強制せずOSの選択に任せる。
      await Helper.setSpeakerphoneOn(enable && !_externalAudio);
    } catch (_) {
      // 一部プラットフォームで未対応/失敗する既知の問題（iOS: flutter-webrtc
      // issue #1290, #1098, #1032, #1427）。失敗しても通話自体は継続させる。
    }
  }

  /// iOSでは接続直後にsetSpeakerphoneOnを呼んでも、数秒後に音声ルートが
  /// 勝手に戻ることがある既知の競合状態がある為、接続完了直後に一度適用し、
  /// 少し間を空けてもう一度適用する。
  Future<void> _applySpeakerphoneWithRetry() async {
    _watchAudioDevices();
    await _applySpeakerphone(_speakerOn);
    await Future.delayed(const Duration(seconds: 2));
    if (_state == GroupCallConnectionState.active) {
      await _applySpeakerphone(_speakerOn);
    }
  }

  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    _applySpeakerphone(_speakerOn);
    notifyListeners();
  }

  /// 取得した映像トラックの実際のカメラ（前面か、`deviceId`）を状態へ反映する
  /// （2026-10-31追加）。以前は前面カメラ固定で仮定しており、端末が別のカメラを
  /// 返すと自分のプレビューの左右反転が送信映像と食い違い、切替の順序もずれた。
  void _syncCameraFromStream() {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    _isFrontCamera = trackIsFrontFacing(track) ?? _isFrontCamera;
    _mirrorFront = _isFrontCamera;
    _cameraDeviceId = trackDeviceId(track) ?? _cameraDeviceId;
  }

  Future<void> switchCamera() async {
    // 連打による多重実行を防ぐ（実機で「重くなる」報告の一因だった）。
    if (_switchingCamera) return;
    final videoTracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (videoTracks.isEmpty) return;
    _switchingCamera = true;
    notifyListeners();
    try {
      final track = videoTracks.first;
      bool? nativeIsFront;
      if (kIsWeb) {
        final cameras = await Helper.cameras;
        if (cameras.length < 2) return;
        // 現在のカメラを実際の`deviceId`から特定して次へ進める（以前は先頭を
        // 現在地と仮定していた為、初回の切替で同じカメラのままになった）。
        final currentId = trackDeviceId(track) ?? _cameraDeviceId;
        final currentIndex = cameras.indexWhere((c) => c.deviceId == currentId);
        final next = cameras[(currentIndex + 1) % cameras.length];
        await Helper.switchCamera(track, next.deviceId, _localStream);
      } else {
        // ネイティブの戻り値は、成功したかではなく「切替後が前面カメラか」。
        nativeIsFront = await Helper.switchCamera(track);
      }
      final switched = _localStream?.getVideoTracks().firstOrNull;
      // ネイティブは同じトラックのままカメラだけが切り替わり、`getSettings()`は作成時の値の
      // まま（外カメラでも'user'）なので、設定は使わず切替の戻り値で決める（2026-11-15）。
      _isFrontCamera = nextIsFrontFacing(
        isWeb: kIsWeb,
        settingsFront: switched == null ? null : trackIsFrontFacing(switched),
        previousFront: _isFrontCamera,
        nativeIsFront: nativeIsFront,
      );
      // 反転は、新しいカメラの映像が出るころに切り替える。
      _mirrorTimer?.cancel();
      _mirrorTimer = Timer(const Duration(milliseconds: 450), () {
        _mirrorFront = _isFrontCamera;
        notifyListeners();
      });
      if (switched != null) {
        _cameraDeviceId = trackDeviceId(switched) ?? _cameraDeviceId;
      }
      // Web版のHelper.switchCameraは古いトラックをstop()して_localStreamから
      // 取り除き、新しいトラックを同じ_localStreamに追加する副作用を持つが、
      // それだけではRTCVideoRenderer（Web実装、代入時点でトラックを
      // スナップショットする）が古い（停止済みの）トラックを表示し続け
      // 「切替後に画面が真っ黒になる」不具合になる。加えて、各相手との
      // RTCPeerConnectionのRTCRtpSenderにも明示的にreplaceTrackしないと
      // 新しい映像が送信されない（グループ通話は相手の人数分Peer
      // Connectionがある為、全員分に反映する必要がある）。
      final newTrack = _localStream?.getVideoTracks().firstOrNull;
      if (newTrack != null) {
        localRenderer.srcObject = _localStream;
        muteLocalPlayback(localRenderer);
        for (final pc in _peerConnections.values) {
          final sender = (await pc.getSenders())
              .where((s) => s.track?.kind == 'video')
              .firstOrNull;
          await sender?.replaceTrack(newTrack);
        }
      }
    } catch (_) {
      // 切替可能なカメラが1つしかない環境など。現状維持。
    } finally {
      _switchingCamera = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _mirrorTimer?.cancel();
    for (final timer in _screenTimeouts.values) {
      timer.cancel();
    }
    unawaited(_micGain?.dispose());
    unawaited(_screenGain?.dispose());
    if (_watchingAudioDevices) navigator.mediaDevices.ondevicechange = null;
    _removePageExitListener?.call();
    _connectGuard.cancelAll();
    _presenceTimer?.cancel();
    _speakingTimer?.cancel();
    _participantsSub?.cancel();
    _videoFailedTimer?.cancel();
    _soundPlayer.dispose();
    bgm.dispose();
    for (final userId in [..._peerConnections.keys]) {
      _disconnectFromPeer(userId);
    }
    for (final timer in _watchdogs.values) {
      timer.cancel();
    }
    for (final track in _screenDisplay?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    localScreenRenderer.dispose();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream?.dispose();
    _micBusyAtJoinTimer?.cancel();
    unawaited(_micDenoiser?.dispose());
    localRenderer.dispose();
    super.dispose();
  }
}
