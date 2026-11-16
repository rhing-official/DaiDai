package com.cloudwebrtc.webrtc;

import org.webrtc.audio.JavaAudioDeviceModule;

import java.nio.ByteBuffer;

/**
 * DaiDai独自のパッチ: {@link ScreenAudioMixer}をオーディオデバイスの録音バッファへつなぐ。
 * WebRTCのクラスを継承する部分だけをここに分け、アプリ側（Kotlin）からは{@link ScreenAudioMixer}の
 * 静的な窓口だけを使う（アプリ側のクラスパスにWebRTC本体は無い為）。
 */
public final class ScreenAudioMixerCallback implements JavaAudioDeviceModule.AudioBufferCallback {
  @Override
  public long onBuffer(
      ByteBuffer buffer,
      int audioFormat,
      int channelCount,
      int sampleRate,
      int bytesRead,
      long captureTimeNs) {
    return ScreenAudioMixer.INSTANCE.onBuffer(
        buffer, audioFormat, channelCount, sampleRate, bytesRead, captureTimeNs);
  }
}
