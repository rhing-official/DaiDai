/// 通話まわりで再生する効果音の論理名。
/// アセットパスをここに集約し、音源ファイルを差し替える際に
/// コントローラ/UI側のコードを変更せずに済むようにする。
enum CallSound { ringtone, participantJoined, participantLeft }

extension CallSoundAsset on CallSound {
  /// `AssetSource`は`assets/`以下の相対パスを取る。
  String get assetPath => switch (this) {
    CallSound.ringtone => 'sounds/call_ringtone.mp3',
    CallSound.participantJoined => 'sounds/participant_joined.mp3',
    CallSound.participantLeft => 'sounds/participant_left.mp3',
  };
}
