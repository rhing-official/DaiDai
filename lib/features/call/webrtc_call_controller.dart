import 'dart:async';
import 'dart:math' show Random;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call.dart';
import '../../repositories/call_repository.dart';
import 'call_log.dart';
import 'camera_mirror_sync.dart';
import 'ice_diagnostics.dart';
import 'call_ring_timeout.dart';
import 'call_sound_player.dart';
import 'disconnect_grace.dart';
import 'rtc_config.dart';
import 'audio_route.dart';
import 'bgm/bgm_storage.dart';
import 'bgm/bgm_now_playing.dart';
import 'mic_busy.dart';
import 'mic_denoiser.dart';
import 'send_gain.dart';
import 'screen_share.dart';
import '../../providers/bgm_preferences_provider.dart';
import 'bgm/bgm_queue.dart';
import 'bgm/call_bgm.dart';
import 'webrtc_media_constraints.dart';

enum CallConnectionState { connecting, active, ended }

/// 1件の音声通話のWebRTCシグナリング・PeerConnectionのライフサイクルを管理する。
/// 通話毎にインスタンス化し、画面を離れる際にdispose()すること。
class WebrtcCallController extends ChangeNotifier {
  WebrtcCallController({
    required this.call,
    required this.isCaller,
    required CallRepository callRepository,
    IceServersLoader? iceServersLoader,
    this.joinWithCamera = true,
    this.bgmPreferences = const BgmPreferences(),
    this.onBgmPreferencesChanged,
    this.onBgmLastPlayedChanged,
  }) : _callRepository = callRepository,
       _iceServersLoader = iceServersLoader;

  final Call call;
  final bool isCaller;

  /// 応答時にカメラをオンで入るか（設定「ビデオ通話に参加する時カメラをオンにする」、
  /// 2026-11-01）。着信側の応答にだけ効き、発信側には影響しない。
  final bool joinWithCamera;

  /// BGMの前回の状態（音量・再生順）と、変えた時の保存（2026-11-16）。
  final BgmPreferences bgmPreferences;
  final void Function(double volume, BgmPlayOrder order)?
  onBgmPreferencesChanged;
  final void Function(BgmLastPlayed last)? onBgmLastPlayedChanged;
  final CallRepository _callRepository;

  /// 中継（TURN）の認証情報の取得（nullならSTUNのみ、2026-10-21）。
  final IceServersLoader? _iceServersLoader;

  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  /// ビデオ通話時の自分のカメラプレビュー用。音声のみの通話では使わない。
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  /// 破棄済みか（2026-11-23、画面共有関連のみ）。`startScreenShare`・
  /// `changeScreenSource`はOSの共有選択ダイアログを待つ長い非同期の間に通話が
  /// 別の理由（相手の切断等）で終わりdispose()され得る為、その後に続く
  /// `notifyListeners()`・レンダラーへの書き込みを防ぐガードに使う。
  bool _disposed = false;

  /// マイクのノイズ除去（RNNoise、Webで設定がオンの時だけ）。
  MicDenoiser? _micDenoiser;
  StreamSubscription<Call?>? _callSub;
  StreamSubscription<List<Map<String, dynamic>>>? _candidatesSub;

  // offer/answerは通話開始時の1回きりではなく、通話中の音声⇔ビデオ切替
  // （setVideoEnabled参照）のたびに同じフィールドへ上書きされる。
  // 「新着かどうか」は一意な採番ではなくSDP文字列そのものの差分で判定し、
  // 自分が直前に書き込んだ値（_pendingLocalXxx）と既に適用済みの値
  // （_lastAppliedXxx）のどちらとも一致しない場合だけ「相手からの新着」
  // として扱う。これにより発信/着信・初回接続/再ネゴシエーションを
  // 問わず同じロジックで扱える。
  String? _pendingLocalOfferSdp;
  String? _pendingLocalAnswerSdp;
  String? _lastAppliedOfferSdp;
  String? _lastAppliedAnswerSdp;

  // setRemoteDescriptionが完了するより先にICE candidateが届くと、
  // addCandidateが例外を投げて無言で失われてしまう競合状態があった為、
  // 完了するまで候補をバッファし、完了後にまとめて適用する。
  // watchCandidatesは毎回累積リスト全体を再送してくる為、適用済みの
  // 候補をキーで重複排除する。
  bool _remoteDescriptionSet = false;
  final List<Map<String, dynamic>> _pendingRemoteCandidates = [];
  final Set<String> _appliedCandidateKeys = {};

  /// 「終了」を相手へWebRTC経由で即時に伝えるデータチャネル（2026-10-13）。
  /// Firestoreの購読は回線切替等で配信が数十秒遅れることがあり、それとは別の
  /// 経路で切断を確実に伝える（Firestoreの`ended`書き込みも従来どおり行う）。
  RTCDataChannel? _controlChannel;
  static const _byeMessage = 'bye';
  static const _muteOnMessage = 'mute:1';
  static const _muteOffMessage = 'mute:0';
  static const _micBusyOnMessage = 'micbusy:1';
  static const _micBusyOffMessage = 'micbusy:0';
  late final DisconnectGrace _disconnectGrace = DisconnectGrace(
    onExpired: _endFromConnectionLoss,
  );

  bool _connectionIssue = false;
  bool get connectionIssue => _connectionIssue;

  /// 音声・映像の通り道（ICE）が確立したか。`active`（応答済み）になっても、確立するまでの
  /// 5〜10秒は音声も映像も届かない為、画面は「通信を確立中」を出す（2026-11-16）。
  /// 一度確立したら、以降の切断・不安定は[connectionIssue]で扱う。
  bool _mediaConnected = false;
  bool get mediaConnected => _mediaConnected;

  /// 確立まで時間がかかっている（応答から15秒を超えた）。
  bool _establishingTooLong = false;
  bool get establishingTooLong => _establishingTooLong;
  Timer? _establishingTimer;
  Timer? _giveUpTimer;

  void _startEstablishingTimer() {
    if (_mediaConnected || _establishingTimer != null) return;
    _establishingTimer = Timer(const Duration(seconds: 15), () {
      _establishingTimer = null;
      if (_mediaConnected || _state == CallConnectionState.ended) return;
      _establishingTooLong = true;
      notifyListeners();
      // さらに15秒（計30秒）つながらなければ、自分から終える。相手が先に居なくなって、誰もいない
      // 通話に居続けるのを防ぐ保険（2026-11-18）。
      _giveUpTimer?.cancel();
      _giveUpTimer = Timer(const Duration(seconds: 15), () {
        _giveUpTimer = null;
        if (_mediaConnected || _state == CallConnectionState.ended) return;
        callLog('1:1 establishing timed out; hanging up');
        unawaited(hangUp());
      });
    });
  }

  void _markMediaConnected() {
    _establishingTimer?.cancel();
    _establishingTimer = null;
    _giveUpTimer?.cancel();
    _giveUpTimer = null;
    if (_mediaConnected) return;
    _mediaConnected = true;
    _establishingTooLong = false;
    notifyListeners();
  }

  /// 通話の効果音（着信音）再生。画面側が着信中にループ再生を開始/停止する。
  final soundPlayer = CallSoundPlayer();

  CallConnectionState _state = CallConnectionState.connecting;
  CallConnectionState get state => _state;

  bool _muted = false;
  bool get muted => _muted;

  /// いま発声しているか（自分・相手、2026-11-23追加）。通話タイルをアクセントカラーの
  /// 枠（`SpeakingFrame`）で囲むのに使う。広場（[WebrtcGroupCallController]）に
  /// あった仕組みの移植で、flutter_webrtcに音声レベルのイベントは無い為、
  /// [_speakingPollInterval]毎に`getStats()`の`audioLevel`を見て判定する。1対1は
  /// 相手が1人だけなので、広場の`Set<String> speakingUserIds`ではなく
  /// 自分・相手それぞれのboolで持つ。
  bool _localSpeaking = false;
  bool get localSpeaking => _localSpeaking;
  bool _remoteSpeaking = false;
  bool get remoteSpeaking => _remoteSpeaking;
  Timer? _speakingTimer;
  bool _pollingSpeaking = false;

  static const _speakingPollInterval = Duration(milliseconds: 500);

  /// 0〜1の音声レベルがこれを超えたら発声中とみなす。
  static const _speakingThreshold = 0.02;

  void _startSpeakingPoll() {
    if (_speakingTimer != null) return;
    _speakingTimer = Timer.periodic(
      _speakingPollInterval,
      (_) => unawaited(_pollSpeaking()),
    );
  }

  void _stopSpeakingPoll() {
    _speakingTimer?.cancel();
    _speakingTimer = null;
    _localSpeaking = false;
    _remoteSpeaking = false;
  }

  Future<void> _pollSpeaking() async {
    if (_pollingSpeaking || _state != CallConnectionState.active) return;
    final pc = _peerConnection;
    if (pc == null) return;
    _pollingSpeaking = true;
    try {
      List<StatsReport> reports;
      try {
        reports = await pc.getStats();
      } catch (_) {
        return;
      }
      var local = false;
      var remote = false;
      for (final report in reports) {
        final level = double.tryParse('${report.values['audioLevel']}');
        if (level == null || level <= _speakingThreshold) continue;
        final kind = report.values['kind'] ?? report.values['mediaType'];
        if (kind != null && kind != 'audio') continue;
        if (report.type == 'inbound-rtp') {
          remote = true;
        } else if ((report.type == 'media-source' ||
                report.type == 'outbound-rtp') &&
            !_muted) {
          local = true;
        }
      }
      if (_state != CallConnectionState.active) return;
      if (local != _localSpeaking || remote != _remoteSpeaking) {
        _localSpeaking = local;
        _remoteSpeaking = remote;
        notifyListeners();
      }
    } finally {
      _pollingSpeaking = false;
    }
  }

  /// 相手がミュートしているか（2026-10-31追加）。一対にはミュート状態を運ぶ
  /// 経路が無かった為、コントロールのデータチャネルで送り合う（Firestoreへの
  /// 書き込みを増やさない）。
  bool _remoteMuted = false;
  bool get remoteMuted => _remoteMuted;

  /// 他のアプリ（別の通話など）にマイクを奪われ、声が相手に届かない状態か（2026-11-16）。
  /// ミュートとは別。OSが自分のマイクを無音にした（Android）／ブラウザがマイクを止めた（Web）時。
  bool _micUnavailable = false;
  bool get micUnavailable => _micUnavailable;

  /// 相手のマイクが、他のアプリに奪われているか。
  bool _remoteMicUnavailable = false;
  bool get remoteMicUnavailable => _remoteMicUnavailable;

  /// 通話に入る時に、他のアプリがマイクを使っていた（注意を出す。数秒で消える）。
  bool _micBusyAtJoin = false;
  bool get micBusyAtJoin => _micBusyAtJoin;
  Timer? _micBusyAtJoinTimer;

  void setMicUnavailable(bool value) {
    if (_micUnavailable == value) return;
    _micUnavailable = value;
    callLog('1:1 mic unavailable: $value');
    _sendMicState();
    notifyListeners();
  }

  void _sendMicState() {
    final channel = _controlChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      channel.send(
        RTCDataChannelMessage(
          _micUnavailable ? _micBusyOnMessage : _micBusyOffMessage,
        ),
      );
    } catch (_) {}
  }

  /// 生のマイクのトラックが、ブラウザに止められた（他のアプリがマイクを使っている）か（Web）。
  void _watchMicTrack(MediaStream? stream) {
    if (!kIsWeb) return;
    final track = stream?.getAudioTracks().firstOrNull;
    if (track == null) return;
    track.onMute = () => setMicUnavailable(true);
    track.onUnMute = () => setMicUnavailable(false);
  }

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

  /// 通話のBGM（2026-11-03、Webのみ）。流している間は、マイクと曲を混ぜたトラックを送る。
  late final CallBgm bgm = CallBgm(
    storage: createBgmStorage(),
    micTrack: () => _localStream?.getAudioTracks().firstOrNull,
    replaceOutgoingAudio: _replaceOutgoingAudio,
    onPlayingChanged: _sendBgmState,
    initialVolume: bgmPreferences.volume,
    initialOrder: bgmPreferences.order,
    onPreferencesChanged: onBgmPreferencesChanged,
    onLastPlayedChanged: onBgmLastPlayedChanged,
  )..addListener(notifyListeners);

  // 画面共有（配信、2026-11-15）。広場の通話（`webrtc_group_call_controller.dart`）と同じ作り。
  // 取得した画面は[_screenDisplay]、相手へ送る入れ物は[_screenContainer]（止めて始め直しても同じ）。
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
  RTCRtpSender? _screenVideoSender;
  RTCRtpSender? _screenAudioSender;

  /// 自分の配信のプレビュー用（音は出さない）。
  final RTCVideoRenderer localScreenRenderer = RTCVideoRenderer();
  bool _localScreenRendererInitialized = false;

  /// 共有している画面の映像のトラック（共有していなければnull。自分のプレビューの静止画の取得に使う）。
  MediaStreamTrack? get screenVideoTrack =>
      _screenDisplay?.getVideoTracks().firstOrNull;

  /// 相手の配信（画面）。カメラとは別のストリームで届く。
  final RTCVideoRenderer remoteScreenRenderer = RTCVideoRenderer();
  bool _remoteScreenRendererInitialized = false;
  bool _remoteScreenAttached = false;

  /// 相手が配信中の時の画質の表示（`720P 30FPS`）。配信していなければnull。
  String? _remoteScreenLabel;
  String? get remoteScreenLabel => _remoteScreenLabel;

  /// 相手が画面共有している間（`screen:on`を受けた時点から。映像のストリームが届くのを待たずに
  /// ウィンドウを出す、2026-11-16。ストリームは再ネゴシエーションを経て数秒遅れて届く）。
  bool get remoteScreenShown => _remoteScreenLabel != null;

  /// 相手の画面のストリームが描画の部品に入っているか（映像を出せるか）。
  bool get remoteScreenReady =>
      _remoteScreenLabel != null && _remoteScreenAttached;

  /// `screen:on`から20秒経っても、ストリームが届かなかったか（案内を出す）。
  bool get remoteScreenTimedOut => _remoteScreenTimedOut;
  bool _remoteScreenTimedOut = false;

  /// 自分の画面共有が、相手に届いていないと相手から知らされたか（2026-11-17）。共有を終える・
  /// やり直すと下りる。
  bool get screenDeliveryFailed => _screenDeliveryFailed;
  bool _screenDeliveryFailed = false;
  Timer? _remoteScreenTimeout;
  final Stopwatch _remoteScreenWatch = Stopwatch();

  /// 最後に受け取った相手の画面のストリーム。共有をやめて再開した時、送信側は`replaceTrack`で
  /// 差し替えるだけで`onTrack`が来ない為、これを描画の部品へ入れ直す。
  MediaStream? _remoteScreenStream;

  /// 最初に届いたストリーム＝カメラ・マイク。これと違うストリームが相手の画面。
  String? _cameraStreamId;

  /// 相手がBGMを流している時の表示用の情報（流していなければnull）。
  BgmNowPlaying? _remoteBgm;
  BgmNowPlaying? get remoteBgm => _remoteBgm;
  String? get remoteBgmTitle => _remoteBgm?.title;

  // ---- 音量（2026-11-16）。聞こえる側は全プラットフォーム、送る側（マイク・共有する音）はWebのみ ----

  double _remoteVoiceVolume = 1;
  double get remoteVoiceVolume => _remoteVoiceVolume;

  /// 相手の声の音量（0〜1）。自分の耳に届く音だけが変わる。
  Future<void> setRemoteVoiceVolume(double volume) async {
    _remoteVoiceVolume = volume.clamp(0.0, 1.0);
    try {
      await remoteRenderer.setVolume(_remoteVoiceVolume);
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
    for (final sender in await _peerConnection?.getSenders() ?? []) {
      if (sender.track?.id == old.id) {
        try {
          await sender.replaceTrack(gain.track);
        } catch (e) {
          callLog('1:1 mic gain replaceTrack failed: $e');
        }
      }
    }
    callLog('1:1 mic gain on');
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
      try {
        await _screenAudioSender?.replaceTrack(gain.track);
      } catch (e) {
        callLog('1:1 screen gain replaceTrack failed: $e');
      }
    }
    _screenGain?.setGain(_screenSendVolume);
  }

  Future<void> _replaceOutgoingAudio(MediaStreamTrack track) async {
    for (final sender in await _peerConnection?.getSenders() ?? []) {
      if (sender.track?.kind == 'audio') await sender.replaceTrack(track);
    }
  }

  static const _bgmOnPrefix = 'bgm:state:';
  static const _bgmOffMessage = 'bgm:off';

  void _sendBgmState(BgmNowPlaying? nowPlaying) {
    final channel = _controlChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      channel.send(
        RTCDataChannelMessage(
          nowPlaying == null
              ? _bgmOffMessage
              : '$_bgmOnPrefix${nowPlaying.encode()}',
        ),
      );
    } catch (_) {
      // 送れなくても通話は続ける（相手の表示が古今まになるだけ）。
    }
  }

  /// 自分が現在ビデオ通話として動作しているか（[call.isVideo]は開始時点の
  /// 値のままなので、通話中の切替を反映する可変の状態として別に持つ）。
  /// 音声⇔ビデオの切替は自分側にのみ適用され、相手には影響しない。
  // 着信側は応答するまで自分のカメラ・マイクを開かない（[accept]で取得する）ため、
  // 応答前は音声扱い（`false`）から始める（2026-10-13）。
  late bool _isVideo = isCaller ? call.isVideo : false;

  /// 発信側が、オファー時に確保した映像のトランシーバー（応答後にカメラの
  /// トラックを差し込む）。映像通話の発信側のみ。
  RTCRtpTransceiver? _videoTransceiver;
  bool get isVideo => _isVideo;

  /// 相手が現在ビデオ通話として動作しているか。自分の映像トラックの
  /// 有無には影響せず、UI側が相手の映像表示/プレースホルダーの
  /// 切替に使うだけの表示用フラグ。
  late bool _remoteIsVideo = isCaller ? call.calleeIsVideo : call.callerIsVideo;
  bool get remoteIsVideo => _remoteIsVideo;

  /// 相手の映像トラックが実際に届いて流れているか（2026-11-03）。[remoteIsVideo]は相手が
  /// 申告した「映像オン」のフラグで、トラックが届く前や届かない場合でも真になる。その間に
  /// 映像の枠だけを出すと、中身の無い透明な画面になり、相手が誰かも分からなくなる為、
  /// 画面は両方が真の時だけ映像を出し、それ以外は相手のアイコンを出す。
  bool _remoteVideoReady = false;
  bool get remoteVideoShown => _remoteIsVideo && _remoteVideoReady;

  void _setRemoteVideoReady(bool value) {
    if (value == _remoteVideoReady) return;
    _remoteVideoReady = value;
    notifyListeners();
  }

  bool _localRendererInitialized = false;

  /// 通話が接続状態（active）になった時刻。発信者側のみ、通話終了時に
  /// この時刻から通話履歴メッセージの通話時間を計算する為に使う。
  DateTime? _connectedAt;

  /// 通話中、15秒ごとに「生きている」印を書く（2026-11-17。終了が書かれずに残った通話を
  /// 語らい一覧の標・サーバーの片付けが見分けるため）。
  Timer? _presenceTimer;

  void _startPresence() {
    if (_presenceTimer != null) return;
    void touch() => unawaited(
      _callRepository
          .touchPresence(call.callId, isCaller: isCaller)
          .catchError((_) {}),
    );
    touch();
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => touch(),
    );
  }

  void _stopPresence() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  bool _switchingCallType = false;
  bool get switchingCallType => _switchingCallType;

  bool _accepting = false;
  bool get accepting => _accepting;

  /// スピーカーで鳴らしているか。LINEと同じく、音声通話は受話口、映像通話は
  /// スピーカーから始める（2026-11-01変更、以前はどちらもスピーカー）。
  late bool _speakerOn = call.isVideo;
  bool get speakerOn => _speakerOn;

  /// Bluetooth・有線ヘッドセットなど外部のオーディオに接続中か（2026-11-01追加）。
  /// 接続中は出力先をOSに任せ、スピーカー/受話口の切替ボタンも出さない。
  bool _externalAudio = false;
  bool get showSpeakerToggle =>
      isSpeakerToggleCapablePlatform && !_externalAudio;
  bool _watchingAudioDevices = false;

  Future<void> _refreshExternalAudio() async {
    final external = await hasExternalAudioOutput();
    if (_state == CallConnectionState.ended || external == _externalAudio)
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

  bool _switchingCamera = false;
  bool get switchingCamera => _switchingCamera;

  /// 現在のカメラが前面（インカメラ）かどうか（2026-08-30追加）。
  /// `buildVideoConstraints`の`facingMode: 'user'`により、通話開始直後は
  /// 常に前面カメラのため`true`初期値。前後2台構成を前提に[switchCamera]の
  /// たびにトグルする（3台以上の環境では実際のカメラと食い違いうるが、
  /// 通話UIの前後切替ボタン自体が2択の前提のため許容する）。自分の映像
  /// プレビューは前面カメラの時だけ左右反転させる（鏡のような見え方が
  /// 前面カメラでは自然だが、背面カメラでは実際の景色と左右が逆になり
  /// 不自然なため）。
  bool _isFrontCamera = true;

  /// 自分のプレビューを左右反転する（前面カメラ）かの、画面に出す値。カメラを切り替えた直後は、
  /// 新しいカメラの最初の映像が出るまで少し間があり、その間に反転だけが先に切り替わって
  /// 古い映像が一瞬反転して見えた為、反転の切り替えを遅らせる（2026-11-16）。固定タイマーだけでは
  /// 端末によって早すぎ/遅すぎがあった為、`RTCVideoRenderer`の`onResize`/`onFirstFrameRendered`
  /// （新しいフレームが実際に届いた兆候）との競走に変更した（2026-11-23、[MirrorSyncRace]参照）。
  bool _mirrorFront = true;
  final _mirrorRace = MirrorSyncRace();
  bool get isFrontCamera => _mirrorFront;

  /// 前後（イン/アウト）カメラ切替ボタンの表示可否に使う、映像入力
  /// デバイスの台数（2026-08-19追加）。`getUserMedia`成功後（＝端末の
  /// カメラ利用許可が下りた後）にだけ正確に取得出来る為、映像取得の
  /// 直後（[initialize]・[_enableLocalVideoTrack]）に1回だけ取得し直す
  /// （継続的な監視は行わない）。
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

  /// ICE成立までの経過時間の計測（診断ログ用）。
  final Stopwatch _iceWatch = Stopwatch();

  /// 応答が無今ま[kCallRingTimeout]が経ったら不在着信として終える
  /// （2026-10-23、以前は応答するまで着信音・呼出音が鳴り続けた）。発信側・着信側
  /// どちらも持ち、先に切れた側が`missed`を書く（書き込みは重複してもよい）。
  Timer? _ringTimeout;

  void _startRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = Timer(kCallRingTimeout, _onRingTimeout);
  }

  void _cancelRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = null;
  }

  void _onRingTimeout() {
    _ringTimeout = null;
    if (_state != CallConnectionState.connecting) return;
    unawaited(
      _callRepository
          .updateStatus(call.callId, CallStatus.missed)
          .catchError((_) {}),
    );
    _finish();
  }

  Future<void> initialize() async {
    _startRingTimeout();
    try {
      await remoteRenderer.initialize();
      if (call.isVideo) {
        await localRenderer.initialize();
        _localRendererInitialized = true;
      }

      // 発信側は通話を始める操作の中で自分のカメラ・マイクを取得する。着信側は
      // 応答するまで開かない（応答前のカメラ要求はスマホのブラウザで拒否され、
      // 着信UIごと消えて応答できなくなっていた。[accept]で取得する、2026-10-13）。
      // 発信側も、映像通話のカメラは相手が応答するまで起動しない（呼び出し中に
      // カメラが点くのを避ける、2026-10-13）。ここでは音声だけを取得し、映像は
      // オファーに枠（トランシーバー）だけ確保して、応答後に[_startCallerCamera]で
      // トラックを差し込む（再ネゴシエーション不要）。
      if (isCaller) {
        await _acquireLocalStream(allowVideoFallback: false, videoNow: false);
      }

      final turnWatch = Stopwatch()..start();
      final rtcConfiguration = await loadRtcConfiguration(_iceServersLoader);
      callLog(
        '1:1 TURN fetched ${turnWatch.elapsedMilliseconds}ms '
        '(iceServers=${(rtcConfiguration['iceServers'] as List?)?.length})',
      );
      callLog(
        '1:1 iceServers=${summarizeIceServers(rtcConfiguration['iceServers'])}',
      );
      _peerConnection = await createPeerConnection(rtcConfiguration);
      _iceWatch.start();
      if (isCaller) {
        await _attachLocalStream();
        if (call.isVideo) {
          _videoTransceiver = await _peerConnection!.addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
            // ストリームに紐づけておく（紐づけないと相手の`onTrack`の
            // `streams`が空になり、後からreplaceTrackした映像が相手の画面に
            // 出なかった、2026-10-22）。
            init: RTCRtpTransceiverInit(
              direction: TransceiverDirection.SendRecv,
              streams: [_localStream!],
            ),
          );
        }
      }

      // 発信側がオファー前に作る（オファーに含まれ、再ネゴシエーション不要）。
      if (isCaller) {
        _attachControlChannel(
          await _peerConnection!.createDataChannel(
            'control',
            RTCDataChannelInit()..ordered = true,
          ),
        );
      }
      _peerConnection!.onDataChannel = _attachControlChannel;

      _peerConnection!.onSignalingState = (state) =>
          callLog('1:1 signaling=$state');
      _peerConnection!.onConnectionState = (state) =>
          callLog('1:1 connection=$state');
      _peerConnection!.onIceGatheringState = (state) => callLog(
        '1:1 iceGathering=$state (${_iceWatch.elapsedMilliseconds}ms)',
      );
      _peerConnection!.onTrack = (event) {
        callLog(
          '1:1 onTrack kind=${event.track.kind} '
          'streams=${event.streams.length} muted=${event.track.muted}',
        );
        final streamId = event.streams.firstOrNull?.id;
        if (streamId != null) {
          final cameraId = _cameraStreamId ??= streamId;
          if (streamId != cameraId) {
            unawaited(_attachRemoteScreen(event.streams.first));
            return;
          }
        }
        if (event.track.kind == 'video') {
          final track = event.track;
          _setRemoteVideoReady(track.muted != true);
          track.onUnMute = () => _setRemoteVideoReady(true);
          track.onMute = () => _setRemoteVideoReady(false);
          track.onEnded = () => _setRemoteVideoReady(false);
        }
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
          if (_remoteVoiceVolume < 1) {
            unawaited(
              remoteRenderer.setVolume(_remoteVoiceVolume).catchError((_) {}),
            );
          }
        } else {
          // ストリームに紐づかないトラック（相手が旧版など）は、既存の
          // 受信ストリームへ足して映像・音声を表示出来るようにする。
          final existing = remoteRenderer.srcObject;
          if (existing != null) {
            existing.addTrack(event.track);
            remoteRenderer.srcObject = existing;
          }
        }
      };

      _peerConnection!.onIceConnectionState = (iceState) {
        callLog('1:1 ice=$iceState (${_iceWatch.elapsedMilliseconds}ms)');
        if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          unawaited(logIceStats(_peerConnection, '1:1'));
        } else if (iceState ==
                RTCIceConnectionState.RTCIceConnectionStateConnected ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          unawaited(logIceStats(_peerConnection, '1:1'));
          _markMediaConnected();
          unawaited(
            Future.delayed(
              const Duration(seconds: 3),
            ).then((_) => logOutboundMediaStats(_peerConnection, '1:1')),
          );
        }
        final issue =
            iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected;
        if (issue != _connectionIssue) {
          _connectionIssue = issue;
          notifyListeners();
        }
        // 通話確立後の接続断は、相手が落ちた・回線が切れたとみなして終了する
        // （失敗・クローズは即、切断は猶予後）。呼び出し中は対象外。
        if (_state != CallConnectionState.active) return;
        if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          _endFromConnectionLoss();
        } else {
          _disconnectGrace.update(
            iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected,
          );
        }
      };

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        callLog(
          '1:1 local candidate ${summarizeIceCandidate(candidate.candidate)}',
        );
        _callRepository.addCandidate(
          callId: call.callId,
          isCaller: isCaller,
          candidate: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      };

      _candidatesSub = _callRepository
          .watchCandidates(callId: call.callId, isCaller: isCaller)
          .listen((candidates) {
            for (final data in candidates) {
              _applyOrBufferCandidate(data);
            }
          });

      if (isCaller) {
        await _startAsCaller();
      } else {
        // 着信側はユーザーが応答ボタンを押すまでSDP応答を送らない
        // （accept()参照）。ここでは発信者側キャンセルの監視のみ行う。
        _watchForCancelWhileRinging();
      }
    } catch (e, st) {
      callLog('1:1 initialize failed (isCaller=$isCaller): $e\n$st');
      _error = '通話を開始出来ませんでした（マイクの利用を許可して下さい）: $e';
      _state = CallConnectionState.ended;
      notifyListeners();
    }
  }

  /// 自分のカメラ・マイクを取得して[_localStream]に入れる。音声制約は
  /// プラットフォーム毎の既知の問題を踏まえてwebrtc_media_constraints.dartに
  /// 集約している（本格的なRNNoise統合はフェーズ3の別プロジェクト）。
  /// [allowVideoFallback]がtrueなら、映像（カメラ）の取得に失敗しても音声のみで
  /// 続行する（応答は出来るようにし、映像は後からオンに出来る）。
  ///
  /// [videoNow]がfalseなら映像（カメラ）は取得せず、音声だけにする（発信側が
  /// 応答前にカメラを点けない為）。この場合[_isVideo]（映像通話のUI構成）は
  /// 変えない。
  Future<void> _acquireLocalStream({
    required bool allowVideoFallback,
    bool videoNow = true,
    bool cameraOn = true,
  }) async {
    var video = call.isVideo && videoNow && cameraOn;
    // 他のアプリがマイクを使っていたら、数秒だけ注意を出す（自分の録音を始める前に調べる）。
    if (await isMicBusyNow()) {
      _micBusyAtJoin = true;
      callLog('1:1 mic is busy by another app at join');
      _micBusyAtJoinTimer?.cancel();
      _micBusyAtJoinTimer = Timer(const Duration(seconds: 8), () {
        _micBusyAtJoin = false;
        notifyListeners();
      });
      notifyListeners();
    }
    final denoise = await shouldDenoiseMic();
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': buildAudioConstraints(rnnoise: denoise),
        'video': video
            ? buildVideoConstraints(
                frontCamera: _isFrontCamera,
                deviceId: _cameraDeviceId,
              )
            : false,
      });
    } catch (_) {
      if (!video || !allowVideoFallback) rethrow;
      video = false;
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': buildAudioConstraints(rnnoise: denoise),
        'video': false,
      });
      // 相手には自分が音声のみであることを伝える。
      unawaited(
        _callRepository
            .updateIsVideo(call.callId, isCaller: isCaller, isVideo: false)
            .catchError((_) {}),
      );
    }
    await ensureEchoCancellation(_localStream);
    _watchMicTrack(_localStream);
    _micDenoiser = await applyMicDenoise(_localStream, denoise);
    // 設定（ビデオ通話に参加する時のカメラ）でオフにして入った時は、カメラの失敗時と
    // 同じく、相手には自分が音声のみであることを伝える（通話中にオンに出来る）。
    if (call.isVideo && videoNow && !cameraOn) {
      unawaited(
        _callRepository
            .updateIsVideo(call.callId, isCaller: isCaller, isVideo: false)
            .catchError((_) {}),
      );
    }
    if (videoNow) _isVideo = video;
    if (video) {
      if (!_localRendererInitialized) {
        await localRenderer.initialize();
        _localRendererInitialized = true;
      }
      localRenderer.srcObject = _localStream;
      muteLocalPlayback(localRenderer);
      _syncCameraFromStream();
      unawaited(_refreshCameraCount());
    }
  }

  /// 発信側が、相手の応答後にカメラを取得して、オファー時に確保した映像の
  /// トランシーバーへ差し込む。取得できなければ音声のみで通話を続け、相手へ
  /// 映像が無いことを伝える（着信側の[accept]と同じ扱い）。
  Future<void> _startCallerCamera() async {
    final transceiver = _videoTransceiver;
    if (transceiver == null) return;
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': buildVideoConstraints(
          frontCamera: _isFrontCamera,
          deviceId: _cameraDeviceId,
        ),
      });
      final track = stream.getVideoTracks().first;
      logVideoTrackSettings(track, '1:1');
      _localStream?.addTrack(track);
      if (!_localRendererInitialized) {
        await localRenderer.initialize();
        _localRendererInitialized = true;
      }
      localRenderer.srcObject = _localStream;
      muteLocalPlayback(localRenderer);
      await transceiver.sender.replaceTrack(track);
      _isVideo = true;
      notifyListeners();
      _syncCameraFromStream();
      unawaited(_refreshCameraCount());
    } catch (e) {
      callLog('1:1 caller camera start failed: $e');
      _isVideo = false;
      _setVideoFailed(true);
      notifyListeners();
      unawaited(
        _callRepository
            .updateIsVideo(call.callId, isCaller: isCaller, isVideo: false)
            .catchError((_) {}),
      );
    }
  }

  /// [_localStream]のトラックをPeerConnectionへ追加する。
  Future<void> _attachLocalStream() async {
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  /// setRemoteDescription完了前に届いた候補はバッファに貯め、完了後に
  /// まとめて適用する。watchCandidatesは毎回累積リスト全体を再送してくる
  /// ため、候補毎のキーで重複適用を防ぐ。
  void _applyOrBufferCandidate(Map<String, dynamic> data) {
    final key =
        '${data['candidate']}|${data['sdpMid']}|${data['sdpMLineIndex']}';
    if (_appliedCandidateKeys.contains(key)) return;
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(data);
      return;
    }
    _appliedCandidateKeys.add(key);
    _peerConnection
        ?.addCandidate(
          RTCIceCandidate(
            data['candidate'] as String,
            data['sdpMid'] as String?,
            data['sdpMLineIndex'] as int?,
          ),
        )
        .catchError((_) {
          // 相手のPeerConnectionが既に閉じている等。通話自体は継続させる。
        });
  }

  void _flushPendingCandidates() {
    _remoteDescriptionSet = true;
    final pending = [..._pendingRemoteCandidates];
    _pendingRemoteCandidates.clear();
    for (final data in pending) {
      _applyOrBufferCandidate(data);
    }
  }

  Future<void> _startAsCaller() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _pendingLocalOfferSdp = offer.sdp;
    await _callRepository.setOffer(call.callId, {
      'sdp': offer.sdp,
      'type': offer.type,
    });
    _startPerpetualWatcher();
  }

  /// 初回のオファー/アンサー交換が終わった後も含めて、通話が終わるまで
  /// 継続してcallドキュメントを監視する。offer/answerフィールドは
  /// 通話開始時の1回だけでなく、通話中の音声⇔ビデオ切替（setVideoEnabled）
  /// のたびに上書きされる為、「自分が直前に送った値」でも「既に適用済みの
  /// 値」でも無い新しい値が来たら、相手からの新規オファー/アンサーとして
  /// 都度適用する。発信者・着信者どちらの役割でも同じロジックで扱える。
  void _startPerpetualWatcher() {
    _callSub?.cancel();
    _callSub = _callRepository.watchCall(call.callId).listen((updated) async {
      if (updated == null || _isTerminal(updated.status)) {
        _finish();
        return;
      }

      // 相手が音声⇔ビデオを切り替えた場合も、こちら側の映像トラックは
      // 一切変更しない（切替は本人側にのみ適用される）。UI表示用に相手の
      // 状態だけ反映する。実際の映像の出し分けは、この直後に届く相手からの
      // オファー（映像m-lineの追加/削除）に対してアンサーするだけで済む
      // （自分の映像トラックが無ければ自動的にrecvonlyのアンサーになる）。
      final remoteVideo = isCaller
          ? updated.calleeIsVideo
          : updated.callerIsVideo;
      if (remoteVideo != _remoteIsVideo) {
        _remoteIsVideo = remoteVideo;
        notifyListeners();
        // 相手が映像をオンにしたら、こちらもスピーカーにする（2026-11-25）。
        if (remoteVideo) _autoSwitchToSpeaker();
      }

      final offerSdp = updated.offer?['sdp'] as String?;
      if (offerSdp != null &&
          offerSdp != _pendingLocalOfferSdp &&
          offerSdp != _lastAppliedOfferSdp) {
        _lastAppliedOfferSdp = offerSdp;
        callLog(
          '1:1 offer received sdp=${offerSdp.length} '
          'signaling=${_peerConnection?.signalingState}',
        );
        try {
          await _applyRemoteOfferAndAnswer(updated.offer!);
        } catch (e) {
          // 握りつぶすと映像の切替ボタンが無効のまま戻らなくなる。
          callLog('1:1 offer apply failed: $e');
          _switchingCallType = false;
          notifyListeners();
        }
      }

      final answerSdp = updated.answer?['sdp'] as String?;
      if (answerSdp != null &&
          answerSdp != _pendingLocalAnswerSdp &&
          answerSdp != _lastAppliedAnswerSdp) {
        _lastAppliedAnswerSdp = answerSdp;
        callLog(
          '1:1 answer applying sdp=${answerSdp.length} '
          'signaling=${_peerConnection?.signalingState}',
        );
        // 自分のofferを出していない（安定状態）時のanswerは適用出来ない（offerの
        // 衝突や重複）。例外にせず読み飛ばす。
        if (_peerConnection?.signalingState ==
            RTCSignalingState.RTCSignalingStateStable) {
          callLog('1:1 answer skipped: no local offer pending');
          return;
        }
        try {
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(answerSdp, updated.answer!['type'] as String),
          );
        } catch (e) {
          callLog('1:1 answer apply failed: $e');
          _switchingCallType = false;
          notifyListeners();
          return;
        }
        _flushPendingCandidates();
        if (_state != CallConnectionState.active) {
          _state = CallConnectionState.active;
          _cancelRingTimeout();
          _connectedAt ??= DateTime.now();
          _startPresence();
          _startSpeakingPoll();
          _startEstablishingTimer();
          unawaited(_applySpeakerphoneWithRetry());
          // 相手（着信側）が応答したことで届いたanswer。発信側が聞いていた
          // 呼出音をここで止める（2026-09-12追加、以前は通話終了まで
          // 止める箇所が無かった）。
          soundPlayer.stopRingtone();
          // 映像通話は、応答されてからカメラを起動する。
          if (isCaller && call.isVideo) unawaited(_startCallerCamera());
        }
        _switchingCallType = false;
        notifyListeners();
      }
    });
  }

  /// 相手から届いたオファー（初回接続時、又は相手が音声⇔ビデオを
  /// 切り替えた際の再ネゴシエーション）に対して、アンサーを作って返す。
  Future<void> _applyRemoteOfferAndAnswer(Map<String, dynamic> offerMap) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(
        offerMap['sdp'] as String,
        offerMap['type'] as String,
      ),
    );
    _flushPendingCandidates();
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _pendingLocalAnswerSdp = answer.sdp;
    final written = await _callRepository.setAnswer(call.callId, {
      'sdp': answer.sdp,
      'type': answer.type,
    });
    // 通話が既に終わっていた（発信側がキャンセルした）。終了を上書きせず、こちらも終える。
    if (written == false) {
      callLog('1:1 answer not written: call already ended');
      _finish();
      return;
    }
    if (_state != CallConnectionState.active) {
      _state = CallConnectionState.active;
      _cancelRingTimeout();
      _connectedAt ??= DateTime.now();
      _startPresence();
      _startSpeakingPoll();
      _startEstablishingTimer();
      unawaited(_applySpeakerphoneWithRetry());
      // 着信側が応答したことでこのアンサーを送った瞬間。着信音をここで
      // 止める（2026-09-12追加、以前は通話終了まで止める箇所が無かった）。
      soundPlayer.stopRingtone();
    }
    _switchingCallType = false;
    notifyListeners();
  }

  /// 応答前（着信中）に発信者が通話をキャンセル・終了した場合に
  /// 着信画面を閉じる為の軽量な監視。accept()呼び出しでキャンセルする。
  void _watchForCancelWhileRinging() {
    _callSub = _callRepository.watchCall(call.callId).listen((updated) {
      if (updated == null || _isTerminal(updated.status)) {
        _finish();
        return;
      }
      // 同じアカウントの別端末が先に応答した場合（statusがactiveになる）、
      // この端末の着信音を止めて着信UIを閉じる（2026-10-11追加）。この端末は
      // まだ応答していない（accept()で購読を解除する）ため、ここに届くactiveは
      // 必ず別端末の応答。通話自体は別端末で続くので、Firestoreには何も
      // 書き込先ず、この端末のセッションだけ終える。
      if (updated.status == CallStatus.active && !_accepting) {
        _finish();
        return;
      }
      // 別の端末が応答を始めた時点（`active`になる前）でも閉じる。
      final answeredBy = updated.answeredBy;
      if (answeredBy != null && answeredBy != _deviceSessionId && !_accepting) {
        _finish();
      }
    });
  }

  /// ユーザーが応答ボタンを押した時だけSDP応答を生成・送信する。
  /// （それまでは_startAsCallee()を呼ばないことで、着信＝自動応答という
  /// 挙動を避ける。）
  /// この端末の、着信への応答を区別するためのid（同じアカウントの別端末と競合した時の判定用）。
  final String _deviceSessionId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';

  Future<void> accept() async {
    if (_accepting || _state != CallConnectionState.connecting) return;
    _accepting = true;
    _cancelRingTimeout();
    // 応答した瞬間に着信音を止める（接続が済むのを待たない）。
    soundPlayer.stopRingtone();
    notifyListeners();
    await _callSub?.cancel();
    // 同じアカウントの別端末と同時に応答した時は、先に記録した1台だけが通話を始める。
    final claimed = await _callRepository
        .claimAnswer(call.callId, _deviceSessionId)
        .catchError((_) => true);
    callLog('1:1 accept: claimed=$claimed');
    if (!claimed) {
      _finish();
      return;
    }
    // 応答の準備中（マイク取得・オファー待ち）に発信側が切っても見逃さない。通話の状態の購読は
    // [_startPerpetualWatcher]が始まるまで止まっていたため、終了だけを見る軽い購読を張る。
    _callSub = _callRepository.watchCall(call.callId).listen((updated) {
      if (updated == null || _isTerminal(updated.status)) _finish();
    });
    try {
      // 応答操作（ユーザー操作）の中で自分のカメラ・マイクを取得する。カメラが
      // 使えなければ音声のみで応答する。
      await _acquireLocalStream(
        allowVideoFallback: true,
        cameraOn: joinWithCamera,
      );
      await _attachLocalStream();
    } catch (e) {
      _error = '通話を開始出来ませんでした（マイクの利用を許可して下さい）: $e';
      unawaited(
        _callRepository
            .updateStatus(call.callId, CallStatus.declined)
            .catchError((_) {}),
      );
      _finish();
      return;
    }
    callLog('1:1 accept: local stream ready');
    notifyListeners();
    await _startAsCallee();
  }

  Future<void> _startAsCallee() async {
    if (_state == CallConnectionState.ended) return;
    var offer = call.offer;
    offer ??= await _callRepository
        .watchCall(call.callId)
        .firstWhere((c) => c?.offer != null)
        .then((c) => c!.offer);

    // 以後_startPerpetualWatcher()がこの初回オファーを重複適用しないよう、
    // 適用前にキーを記録しておく。
    _lastAppliedOfferSdp = offer!['sdp'] as String;
    callLog('1:1 accept: offer ready');
    if (_state == CallConnectionState.ended) return;
    await _applyRemoteOfferAndAnswer(offer);
    callLog('1:1 accept: answer sent');
    _startPerpetualWatcher();
  }

  bool _isTerminal(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.declined ||
        status == CallStatus.missed;
  }

  void _finish() {
    _cancelRingTimeout();
    _stopPresence();
    _stopSpeakingPoll();
    if (_state == CallConnectionState.ended) return;
    _state = CallConnectionState.ended;
    // 終了を検知した瞬間、その場で自分の音を止める（2026-09-12追加）。
    // 拒否・切断・キャンセル検知等どの経路で終了しても確実に止まるよう、
    // 外側（active_call_session.dartの_teardown、Riverpodのリスナー経由）に
    // 頼り切らず自分で止める。stopRingtone()は着信音・呼出音の両方を
    // まとめて止める為、発信側/着信側どちらの呼び出し中の音も対応出来る。
    soundPlayer.stopRingtone();
    notifyListeners();
    // 通話の記録（通話履歴・不在着信）は、通話ドキュメントの終了をトリガーに
    // Cloud Functions（`onCallEnded`）が書く（2026-11-17。端末から送ると欠落した）。
  }

  Future<void> decline() async {
    await _callRepository.updateStatus(call.callId, CallStatus.declined);
    _finish();
  }

  Future<void> hangUp() async {
    // 先に相手へWebRTCで終了を伝え、自分も即座に閉じる。Firestoreの書き込み
    // （遅い・失敗することがある）は閉じた後に行い、本人の画面を待たせない。
    _sendBye();
    _finish();
    await _writeEndedWithRetry();
  }

  void _attachControlChannel(RTCDataChannel channel) {
    _controlChannel = channel;
    channel.onMessage = (message) {
      if (message.isBinary) return;
      final text = message.text;
      if (text == _byeMessage) {
        _finish();
      } else if (text == _muteOnMessage || text == _muteOffMessage) {
        _remoteMuted = text == _muteOnMessage;
        notifyListeners();
      } else if (text == _micBusyOnMessage || text == _micBusyOffMessage) {
        _remoteMicUnavailable = text == _micBusyOnMessage;
        notifyListeners();
      } else if (text.startsWith(_bgmOnPrefix)) {
        final state = BgmNowPlaying.decode(text.substring(_bgmOnPrefix.length));
        if (state == null) return;
        // 同時に流せるのは1人。後から始めた相手を優先し、自分のは止める。
        if (_remoteBgm == null && bgm.playing) unawaited(bgm.stop());
        _remoteBgm = state;
        notifyListeners();
      } else if (text.startsWith(_screenOnPrefix)) {
        final wasShown = _remoteScreenLabel != null;
        _remoteScreenLabel = text.substring(_screenOnPrefix.length);
        if (!wasShown) {
          _remoteScreenWatch
            ..reset()
            ..start();
          _remoteScreenTimedOut = false;
          callLog('1:1 screen: on received');
          // 相手が画面共有を始めたら、こちらもスピーカーにする（2026-11-25）。
          _autoSwitchToSpeaker();
        }
        final kept = _remoteScreenStream;
        if (!_remoteScreenAttached &&
            kept != null &&
            _remoteScreenRendererInitialized) {
          // 2回目以降の共有（`onTrack`が来ない）は、前のストリームを入れ直す。
          remoteScreenRenderer.srcObject = kept;
          _remoteScreenAttached = true;
          callLog('1:1 screen: re-attached the kept stream');
        }
        _armRemoteScreenTimeout();
        notifyListeners();
      } else if (text == _screenFailMessage) {
        // 相手に画面が届いていない。共有している間だけ、お知らせを出す。
        if (_screenDisplay != null && !_screenDeliveryFailed) {
          _screenDeliveryFailed = true;
          callLog('1:1 screen: the other side could not receive it');
          notifyListeners();
        }
      } else if (text == _screenOffMessage) {
        _remoteScreenLabel = null;
        _remoteScreenTimeout?.cancel();
        _remoteScreenTimedOut = false;
        _remoteScreenWatch.stop();
        if (_remoteScreenRendererInitialized) {
          remoteScreenRenderer.srcObject = null;
          _remoteScreenAttached = false;
        }
        notifyListeners();
      } else if (text == _bgmOffMessage) {
        _remoteBgm = null;
        notifyListeners();
      }
    };
    // つながった時点で、自分のミュート状態を相手へ伝える（先にミュートして
    // いた場合に備える）。
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        if (_muted) _sendMuteState();
        if (_micUnavailable) _sendMicState();
        final playing = bgm.nowPlaying;
        if (playing != null) _sendBgmState(playing);
        if (_screenDisplay != null) _sendScreenState(_screenQuality.label);
      }
    };
  }

  void _sendMuteState() {
    final channel = _controlChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      channel.send(
        RTCDataChannelMessage(_muted ? _muteOnMessage : _muteOffMessage),
      );
    } catch (_) {
      // 送れなくても通話は続ける（表示が古今まになるだけ）。
    }
  }

  void _sendBye() {
    final channel = _controlChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      channel.send(RTCDataChannelMessage(_byeMessage));
    } catch (_) {
      // 送れなくてもFirestore経由で終了は伝わる。
    }
  }

  Future<void> _writeEndedWithRetry() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _callRepository.updateStatus(call.callId, CallStatus.ended);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  void _endFromConnectionLoss() {
    if (_state == CallConnectionState.ended) return;
    _finish();
    unawaited(_writeEndedWithRetry());
  }

  /// マイクのミュートを送信へ反映する。Androidで端末の再生音を送っている間は、トラックは有効のまま
  /// ネイティブ側で声だけを無音にする（トラックごと無音にすると再生音まで止まる、2026-11-17）。
  void _applyMicMute() {
    final soft = ScreenShareCapture.nativeAudioOn;
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = soft ? true : !_muted;
    }
    if (ScreenShareCapture.isNativeAndroid) {
      unawaited(ScreenShareCapture.setNativeMicMuted(soft && _muted));
    }
  }

  void toggleMute() {
    _muted = !_muted;
    _applyMicMute();
    _sendMuteState();
    notifyListeners();
  }

  /// 通話中に音声通話⇔ビデオ通話を切り替える（映像トラック自体を追加/
  /// 削除して通話の種別そのものを変える）。音声のみで開始した通話には映像用の
  /// track/transceiverが最初から存在しない為、[RTCPeerConnection.addTrack]/
  /// [removeTrack]による再ネゴシエーション（新しいオファー/アンサー交換）が
  /// 必須になる。
  ///
  /// 切り替えは自分側にのみ適用され、相手の映像トラックには一切触れない。
  /// 相手には新しいオファー（映像m-lineの追加/削除）が届くだけで、相手側は
  /// 自分の映像トラックを持っていなければ自動的にrecvonlyでアンサーする
  /// （＝相手のカメラが強制でオン/オフされることは無い）。
  Future<void> setVideoEnabled(bool enabled) async {
    if (enabled == _isVideo ||
        _switchingCallType ||
        _state != CallConnectionState.active) {
      return;
    }
    _switchingCallType = true;
    _setVideoFailed(false);
    notifyListeners();
    callLog('1:1 setVideoEnabled($enabled) start');
    try {
      await _reconcileLocalVideoTo(enabled);
      // 音声通話から映像をオンにしたら、ビデオ通話と同じくスピーカーにする（2026-11-25）。
      if (enabled) _autoSwitchToSpeaker();
      notifyListeners();
      await _callRepository.updateIsVideo(
        call.callId,
        isCaller: isCaller,
        isVideo: enabled,
      );
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      callLog(
        '1:1 offer sent sdp=${offer.sdp?.length} '
        'signaling=${_peerConnection?.signalingState}',
      );
      _pendingLocalOfferSdp = offer.sdp;
      await _callRepository.setOffer(call.callId, {
        'sdp': offer.sdp,
        'type': offer.type,
      });
      if (enabled) {
        unawaited(
          Future.delayed(
            const Duration(seconds: 3),
          ).then((_) => logOutboundMediaStats(_peerConnection, '1:1')),
        );
      }
    } catch (e) {
      // ネットワーク瞬断・カメラが他で使用中・許可が無い等。ボタンを再度有効にし、
      // 失敗したことを画面に出して、ユーザーに再試行させる。
      callLog('1:1 setVideoEnabled($enabled) failed: $e');
      if (enabled) {
        await _rollbackLocalVideo();
        _setVideoFailed(true);
      }
      _switchingCallType = false;
      notifyListeners();
    }
  }

  // ---- 画面共有（配信、2026-11-15） ----

  static const _screenOnPrefix = 'screen:on:';
  static const _screenOffMessage = 'screen:off';

  /// 受信側から送信側へ。画面が20秒届かなかった（2026-11-17）。
  static const _screenFailMessage = 'screen:fail';

  /// 相手へ、配信の画質の表示（配信をやめたらnull）を知らせる。
  void _sendScreenState(String? label) {
    final channel = _controlChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      channel.send(
        RTCDataChannelMessage(
          label == null ? _screenOffMessage : '$_screenOnPrefix$label',
        ),
      );
    } catch (_) {
      // 送れなくても通話は続ける（相手の表示が古いままになるだけ）。
    }
  }

  void _sendControl(String text) {
    final channel = _controlChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      channel.send(RTCDataChannelMessage(text));
    } catch (_) {}
  }

  /// `screen:on`から20秒、映像が届かなければ、案内を出す（[remoteScreenTimedOut]）。
  void _armRemoteScreenTimeout() {
    _remoteScreenTimeout?.cancel();
    if (_remoteScreenAttached || _remoteScreenLabel == null) return;
    // 送信側のやり直し（`screen:on`の再送）では、数え直す。
    _remoteScreenTimedOut = false;
    _remoteScreenTimeout = Timer(const Duration(seconds: 20), () {
      if (_remoteScreenLabel != null && !_remoteScreenAttached) {
        _remoteScreenTimedOut = true;
        callLog('1:1 screen: stream did not arrive within 20s');
        _sendControl(_screenFailMessage);
        notifyListeners();
      }
    });
  }

  Future<void>? _remoteScreenInit;

  Future<void> _attachRemoteScreen(MediaStream stream) async {
    if (!_remoteScreenRendererInitialized) {
      // 映像と音声のトラックは別々に届く為、初期化を1回にまとめる（2回走ると描画の部品が壊れ、
      // 音が出ないことがある）。
      _remoteScreenInit ??= remoteScreenRenderer.initialize().then((_) {
        _remoteScreenRendererInitialized = true;
      });
      await _remoteScreenInit;
    }
    // 届くたびに入れ直す（Webの描画の部品は、入れた時点のトラックを控える為、後から届いた
    // 音声のトラックを取り込むのに必要）。
    remoteScreenRenderer.srcObject = stream;
    remoteScreenRenderer.muted = false;
    unawaited(
      remoteScreenRenderer.setVolume(_remoteScreenVolume).catchError((_) {}),
    );
    _remoteScreenStream = stream;
    _remoteScreenAttached = true;
    _remoteScreenTimeout?.cancel();
    _remoteScreenTimedOut = false;
    callLog(
      '1:1 screen stream attached video=${stream.getVideoTracks().length} '
      'audio=${stream.getAudioTracks().length} '
      'after=${_remoteScreenWatch.elapsedMilliseconds}ms since screen:on',
    );
    notifyListeners();
  }

  /// 画面のトラックを相手へ送る。初めてなら追加（`true`＝再ネゴシエーションが要る）、既に枠が
  /// あれば差し替えだけ（`false`）。
  Future<bool> _attachScreenTracks() async {
    final pc = _peerConnection;
    final display = _screenDisplay;
    final container = _screenContainer;
    if (pc == null || display == null || container == null) return false;
    var renegotiate = false;
    final video = display.getVideoTracks().firstOrNull;
    if (video != null) {
      final sender = _screenVideoSender;
      if (sender == null) {
        final added = await pc.addTrack(video, container);
        _screenVideoSender = added;
        await ScreenShareCapture.applySenderLimits(added, _screenQuality);
        renegotiate = true;
      } else {
        await sender.replaceTrack(video);
        await ScreenShareCapture.applySenderLimits(sender, _screenQuality);
      }
    }
    final audio = display.getAudioTracks().firstOrNull;
    if (audio != null) {
      final sender = _screenAudioSender;
      final outgoing = _screenGain?.track ?? audio;
      if (sender == null) {
        _screenAudioSender = await pc.addTrack(outgoing, container);
        renegotiate = true;
      } else {
        await sender.replaceTrack(outgoing);
      }
    }
    return renegotiate;
  }

  Future<void> _sendRenegotiationOffer() async {
    final pc = _peerConnection;
    if (pc == null) return;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    callLog('1:1 screen offer sent sdp=${offer.sdp?.length}');
    _pendingLocalOfferSdp = offer.sdp;
    await _callRepository.setOffer(call.callId, {
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  /// 相手の画面共有の音声の音量を変える（0〜1）。
  Future<void> setRemoteScreenVolume(double volume) async {
    _remoteScreenVolume = volume.clamp(0.0, 1.0);
    if (_remoteScreenRendererInitialized) {
      try {
        await remoteScreenRenderer.setVolume(_remoteScreenVolume);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// 画面の共有を始める。配信元の選択はブラウザが出す。やめた（キャンセル）時は`false`。
  Future<bool> startScreenShare({
    required ScreenShareQuality quality,
    required bool shareAudio,
    bool muteMic = false,
  }) async {
    if (_screenDisplay != null) return true;
    if (_state != CallConnectionState.active) return false;
    final display = await ScreenShareCapture.start(
      quality,
      shareAudio: shareAudio,
    );
    if (display == null) return false;
    if (_disposed) {
      // OSの共有選択ダイアログを待つ間に、通話が別の理由で終わり破棄された
      // （2026-11-23）。取得したストリームだけ止めて抜ける。
      for (final track in display.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }
      return false;
    }
    _screenDisplay = display;
    // 自分が画面共有を始めたら、スピーカーにする（2026-11-25）。
    _autoSwitchToSpeaker();
    _screenDeliveryFailed = false;
    // 共有元が閉じられたら、共有も終える（`await`の前に付けて、取りこぼさない）。
    ScreenShareCapture.watchEnded(display, () => stopScreenShare());
    _screenQuality = quality;
    _screenAudio = shareAudio;
    // 音楽だけを届けたい時は、共有している間だけ自分のマイクをミュートにする。
    if (muteMic && !_muted) {
      toggleMute();
      _mutedByScreenShare = true;
    }
    _screenContainer ??= await createLocalMediaStream('screen');
    if (ScreenShareCapture.isNativeAndroid) {
      // Androidは、端末の再生音をマイクの音声へ混ぜて送る（映像のトラックに音は付かない）。
      screenAudioMissing =
          shareAudio && !await ScreenShareCapture.setNativeAudio(true);
      _applyMicMute();
    } else {
      screenAudioMissing = shareAudio && display.getAudioTracks().isEmpty;
    }
    if (screenAudioMissing) {
      callLog('1:1 screen audio was not available');
    }
    if (!_localScreenRendererInitialized) {
      await localScreenRenderer.initialize();
      _localScreenRendererInitialized = true;
    }
    localScreenRenderer.srcObject = display;
    notifyListeners();
    unawaited(_applyScreenGain());
    callLog(
      '1:1 screen captured video=${display.getVideoTracks().length} '
      'audio=${display.getAudioTracks().length} '
      'surface=${ScreenShareCapture.surfaceOf(display)}',
    );
    try {
      final renegotiate = await _attachScreenTracks();
      _sendScreenState(quality.label);
      if (renegotiate) await _sendRenegotiationOffer();
    } catch (e) {
      callLog('1:1 screen share failed: $e');
      // 途中まで進んだ状態（送信枠の追加・マイクのミュート等）を`stopScreenShare`と
      // 同じ経路で巻き戻す（2026-11-23）。以前は例外を握りつぶして常にtrueを返して
      // いた為、ローカルの再ネゴシエーション失敗時に「共有中」のまま実体と食い違って
      // 固着していた（相手に`screen:on`を送ってしまった場合も直後に`screen:off`が
      // 届くので表示は固着しない）。
      try {
        await stopScreenShare();
      } catch (_) {}
      return false;
    }
    return true;
  }

  /// 画面の共有をやめる（送信の枠は残し、中身だけ外す）。
  Future<void> stopScreenShare() async {
    final display = _screenDisplay;
    if (display == null) return;
    _screenDisplay = null;
    _screenDeliveryFailed = false;
    unawaited(ScreenShareCapture.notifyNativeStopped());
    if (_mutedByScreenShare) {
      _mutedByScreenShare = false;
      if (_muted) toggleMute();
    }
    if (ScreenShareCapture.isNativeAndroid) {
      await ScreenShareCapture.setNativeAudio(false);
      _applyMicMute();
    }
    // 送信の枠は外す（2026-11-17）。以前は枠を残して中身だけ外し、再開は差し替えだけで済ませていたが、
    // Androidではその再開が相手へ届かなかった（ログ: 再開で再ネゴシエーションが走らない）。
    // 外しておけば、再開は初回と同じ「枠の追加＋再ネゴシエーション」になる。
    final pc = _peerConnection;
    for (final sender in [_screenVideoSender, _screenAudioSender]) {
      if (sender == null) continue;
      try {
        await pc?.removeTrack(sender);
      } catch (_) {}
    }
    _screenVideoSender = null;
    _screenAudioSender = null;
    for (final track in display.getTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    // ここまでの間に通話が別の理由で終わり破棄されていたら、既にレンダラーも
    // 破棄済みの為、これ以上触らず抜ける（2026-11-23）。
    if (_disposed) return;
    localScreenRenderer.srcObject = null;
    final gain = _screenGain;
    _screenGain = null;
    if (gain != null) unawaited(gain.dispose());
    _sendScreenState(null);
    callLog('1:1 screen share stopped');
    notifyListeners();
  }

  /// 相手に届いていない時の「やり直す」（2026-11-17）。画面は選び直さず、今のキャプチャのまま、
  /// 送信の枠を付け直して再ネゴシエーションし、`screen:on`を送り直す。
  Future<void> resendScreenShare() async {
    final display = _screenDisplay;
    final pc = _peerConnection;
    if (display == null || pc == null || _disposed) return;
    _screenDeliveryFailed = false;
    notifyListeners();
    callLog('1:1 screen: resend requested');
    for (final sender in [_screenVideoSender, _screenAudioSender]) {
      if (sender == null) continue;
      try {
        await pc.removeTrack(sender);
      } catch (e) {
        callLog('1:1 screen: removeTrack failed: $e');
      }
    }
    _screenVideoSender = null;
    _screenAudioSender = null;
    try {
      await _attachScreenTracks();
      _sendScreenState(_screenQuality.label);
      await _sendRenegotiationOffer();
    } catch (e) {
      callLog('1:1 screen resend failed: $e');
    }
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
    if (_disposed) {
      // OSの共有選択ダイアログを待つ間に、通話が別の理由で終わり破棄された
      // （2026-11-23）。取得したストリームだけ止めて抜ける。
      for (final track in next.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }
      return;
    }
    _screenDisplay = next;
    ScreenShareCapture.watchEnded(next, () => stopScreenShare());
    if (ScreenShareCapture.isNativeAndroid && _screenAudio) {
      // 新しいキャプチャ（新しいprojection）で、再生音の取得を取り直す。
      await ScreenShareCapture.setNativeAudio(true);
      _applyMicMute();
    }
    localScreenRenderer.srcObject = next;
    // 共有する音の音量は、新しいトラックに掛け直す。
    final oldGain = _screenGain;
    _screenGain = null;
    if (oldGain != null) unawaited(oldGain.dispose());
    unawaited(_applyScreenGain());
    try {
      final renegotiate = await _attachScreenTracks();
      if (renegotiate) await _sendRenegotiationOffer();
    } catch (e) {
      callLog('1:1 change screen failed: $e');
    }
    for (final track in old.getTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    if (_disposed) return;
    notifyListeners();
  }

  /// 画面共有の音声を、共有中に切り替える。切る時は音のトラックを外す。入れる時は、音声を含めて
  /// 配信元を選び直す（取得し直さないと、音声のトラックが得られない）。
  Future<void> setScreenAudio(bool shareAudio) async {
    _screenAudio = shareAudio;
    final display = _screenDisplay;
    if (display == null) return;
    if (ScreenShareCapture.isNativeAndroid) {
      screenAudioMissing =
          shareAudio && !await ScreenShareCapture.setNativeAudio(shareAudio);
      _applyMicMute();
      notifyListeners();
      return;
    }
    if (shareAudio) {
      await changeScreenSource();
      return;
    }
    try {
      await _screenAudioSender?.replaceTrack(null);
    } catch (_) {}
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
      final sender = _screenVideoSender;
      if (sender != null) {
        await ScreenShareCapture.applySenderLimits(sender, quality);
      }
      _sendScreenState(quality.label);
    }
    notifyListeners();
  }

  /// 映像のオンに失敗した時、途中まで進んだ状態（取得済みのカメラ等）を片付けて映像オフへ
  /// 戻し、相手へも映像オフを知らせ直す。
  Future<void> _rollbackLocalVideo() async {
    try {
      await _disableLocalVideoTrack();
    } catch (e) {
      callLog('1:1 video rollback failed: $e');
    }
    _isVideo = false;
    unawaited(
      _callRepository
          .updateIsVideo(call.callId, isCaller: isCaller, isVideo: false)
          .catchError((_) {}),
    );
  }

  /// 自分の映像トラックの有無を[targetIsVideo]に合わせる。[setVideoEnabled]
  /// からのみ呼ばれる（自分の操作でのみ自分の映像トラックが変化する）。
  Future<void> _reconcileLocalVideoTo(bool targetIsVideo) async {
    if (targetIsVideo == _isVideo) return;
    if (targetIsVideo) {
      await _enableLocalVideoTrack();
    } else {
      await _disableLocalVideoTrack();
    }
    _isVideo = targetIsVideo;
  }

  Future<void> _enableLocalVideoTrack() async {
    final videoStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': buildVideoConstraints(
        frontCamera: _isFrontCamera,
        deviceId: _cameraDeviceId,
      ),
    });
    final videoTrack = videoStream.getVideoTracks().first;
    logVideoTrackSettings(videoTrack, '1:1');
    _localStream?.addTrack(videoTrack);
    if (!_localRendererInitialized) {
      await localRenderer.initialize();
      _localRendererInitialized = true;
    }
    localRenderer.srcObject = _localStream;
    muteLocalPlayback(localRenderer);
    await _peerConnection?.addTrack(videoTrack, _localStream!);
    _syncCameraFromStream();
    unawaited(_refreshCameraCount());
  }

  Future<void> _disableLocalVideoTrack() async {
    final videoTracks = [...?_localStream?.getVideoTracks()];
    final senders = await _peerConnection?.getSenders() ?? [];
    for (final track in videoTracks) {
      final sender = senders.firstWhereOrNull((s) => s.track?.id == track.id);
      if (sender != null) {
        await _peerConnection?.removeTrack(sender);
      }
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
    if (_state == CallConnectionState.active) {
      await _applySpeakerphone(_speakerOn);
    }
  }

  /// 通話中に手動でスピーカー/受話口を切り替えたか。切り替えた後は、自動でスピーカーへ
  /// 切り替えない（2026-11-25）。
  bool _speakerManuallySet = false;

  /// 映像のオン・画面共有の開始（自分・相手）で、受話口ならスピーカーへ切り替える
  /// （モバイルのみ。外部のオーディオ接続中は`_applySpeakerphone`が強制しない）。
  void _autoSwitchToSpeaker() {
    if (!isSpeakerToggleCapablePlatform) return;
    if (!shouldAutoSpeaker(
      speakerOn: _speakerOn,
      manuallySet: _speakerManuallySet,
    )) {
      return;
    }
    _speakerOn = true;
    unawaited(_applySpeakerphone(true));
    notifyListeners();
  }

  void toggleSpeaker() {
    _speakerManuallySet = true;
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
    // 連打による多重実行を防ぐ（実機で「重くなる」報告の一因だった。
    // 前のgetUserMedia/switchCameraが終わらないうちに次を呼ぶと処理が
    // 積み重なる）。
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
      // 反転は、新しいカメラの映像が実際に届いたと分かるまで遅らせる。
      // onResize/onFirstFrameRendered（兆候）と固定タイマー（保険）を競走させ、
      // どちらが先に来ても1回だけ確定させる（2026-11-23）。前回分の競走が残って
      // いれば、start()が確定させずに止めてから新しく始める（連打対策）。
      final targetFront = _isFrontCamera;
      _mirrorRace.start(() {
        _mirrorFront = targetFront;
        localRenderer.onResize = null;
        localRenderer.onFirstFrameRendered = null;
        notifyListeners();
      });
      localRenderer.onResize = _mirrorRace.signalResize;
      localRenderer.onFirstFrameRendered = _mirrorRace.signalFirstFrame;
      if (switched != null) {
        _cameraDeviceId = trackDeviceId(switched) ?? _cameraDeviceId;
      }
      // Web版のHelper.switchCameraは古いトラックをstop()して_localStreamから
      // 取り除き、新しいトラックを同じ_localStreamに追加するという副作用を
      // 持つが、それだけでは以下の2つが反映されず「切替後に画面が真っ黒に
      // なる」「相手にも古い映像が送られ続ける」不具合になっていた:
      // 1. RTCVideoRenderer（Web実装）は代入された時点のトラックを
      //    スナップショットとして保持する為、再代入しないと古い
      //    （停止済みの）トラックを表示し続ける。
      // 2. RTCPeerConnectionのRTCRtpSenderは明示的にreplaceTrackしない限り
      //    新しいトラックを送信しない。
      // ネイティブ版はHelper.switchCameraがトラックの実体を差し替えず
      // カメラキャプチャセッションだけを切り替えるため本来不要だが、
      // 同じコードで両対応させても無害（同一トラックへの再代入・
      // replaceTrackは実質no-op）。
      final newTrack = _localStream?.getVideoTracks().firstOrNull;
      if (newTrack != null) {
        localRenderer.srcObject = _localStream;
        muteLocalPlayback(localRenderer);
        final sender = (await _peerConnection?.getSenders() ?? [])
            .where((s) => s.track?.kind == 'video')
            .firstOrNull;
        await sender?.replaceTrack(newTrack);
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
    _disposed = true;
    _stopPresence();
    _stopSpeakingPoll();
    // 保留中のカメラ切替レース（タイマー・onResize/onFirstFrameRenderedの
    // リスナー）を、確定させずに止める。確定後にnotifyListeners()すると
    // 「dispose後のChangeNotifier」で落ちる為、他の後片付けより先に行う（2026-11-23）。
    _mirrorRace.cancel();
    localRenderer.onResize = null;
    localRenderer.onFirstFrameRendered = null;
    if (_watchingAudioDevices) navigator.mediaDevices.ondevicechange = null;
    _cancelRingTimeout();
    _disconnectGrace.cancel();
    _establishingTimer?.cancel();
    _giveUpTimer?.cancel();
    _callSub?.cancel();
    _candidatesSub?.cancel();
    _videoFailedTimer?.cancel();
    _remoteScreenTimeout?.cancel();
    _micBusyAtJoinTimer?.cancel();
    unawaited(_micGain?.dispose());
    unawaited(_screenGain?.dispose());
    soundPlayer.dispose();
    bgm.dispose();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream?.dispose();
    unawaited(_micDenoiser?.dispose());
    for (final track in _screenDisplay?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    localScreenRenderer.dispose();
    remoteScreenRenderer.dispose();
    _peerConnection?.close();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
