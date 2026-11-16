package com.cloudwebrtc.webrtc;

import android.media.AudioFormat;
import android.media.AudioPlaybackCaptureConfiguration;
import android.media.AudioRecord;
import android.media.projection.MediaProjection;
import android.os.Build;
import android.util.Log;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * DaiDai独自のパッチ（2026-11-17）: Androidの画面共有で、端末の再生音（動画・ゲームなど）を
 * 相手へ送る。画面キャプチャの{@link MediaProjection}から{@link AudioPlaybackCaptureConfiguration}で
 * 再生音を取り、マイクの録音バッファ（{@link ScreenAudioMixerCallback}）へ送信前に
 * 混ぜる。別の音声トラックは増やさず、送信者の声のトラックに混ざって届く。
 *
 * 取るのは再生の用途がMEDIA・GAME・UNKNOWNの音だけで、通話の声（VOICE_COMMUNICATION）は取らない
 * （エコーを避ける）。UIDの除外は併用しない（一致の規則と併せると、全部が無音になる場合がある）。Android 10（API 29）以降。
 */
public final class ScreenAudioMixer {
  private static final String TAG = "ScreenAudioMixer";

  public static final ScreenAudioMixer INSTANCE = new ScreenAudioMixer();

  private static final int SAMPLE_RATE = 48000;

  private final Object lock = new Object();
  private MediaProjection projection;
  private volatile boolean wanted = false;
  private volatile boolean micMuted = false;
  private AudioRecord record;
  private Thread reader;

  /** 取った再生音をためるリング（16bit・モノラル、約1秒）。 */
  private final short[] ring = new short[SAMPLE_RATE];
  private int ringRead = 0;
  private int ringWrite = 0;
  private int ringCount = 0;

  private ScreenAudioMixer() {}

  /** 画面キャプチャが始まった時（projectionを作った直後）。 */
  public static void onProjectionReady(MediaProjection projection) {
    INSTANCE.setProjection(projection);
  }

  /** 画面キャプチャが終わった時（配信元の選び直しでは、古い方の終了が新しい方の開始の後に来る）。 */
  public static void onProjectionStopped(MediaProjection projection) {
    INSTANCE.projectionStopped(projection);
  }

  /** 端末の音を送るか。取り始められたら（または止めたら）trueを返す。 */
  public static boolean setWanted(boolean wanted) {
    return INSTANCE.setWantedInternal(wanted);
  }

  /** 端末の音を送っている間、マイクの声だけを無音にする（ミュート）。 */
  public static void setMicMuted(boolean muted) {
    INSTANCE.micMuted = muted;
  }

  public static boolean isCapturing() {
    return INSTANCE.record != null;
  }

  private void setProjection(MediaProjection p) {
    synchronized (lock) {
      if (projection == p) return;
      projection = p;
      stopLocked();
      // 配信元を選び直した時は、新しいprojectionで取り直す。
      if (wanted && p != null) startLocked();
    }
  }

  private void projectionStopped(MediaProjection p) {
    synchronized (lock) {
      if (projection != p) return;
      projection = null;
      stopLocked();
    }
  }

  private boolean setWantedInternal(boolean want) {
    synchronized (lock) {
      wanted = want;
      if (!want) {
        stopLocked();
        micMuted = false;
        return true;
      }
      if (record != null) return true;
      return startLocked();
    }
  }

  private boolean startLocked() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || projection == null) {
      Log.w(TAG, "cannot start: api=" + Build.VERSION.SDK_INT + " projection=" + (projection != null));
      return false;
    }
    try {
      AudioPlaybackCaptureConfiguration config =
          new AudioPlaybackCaptureConfiguration.Builder(projection)
              .addMatchingUsage(android.media.AudioAttributes.USAGE_MEDIA)
              .addMatchingUsage(android.media.AudioAttributes.USAGE_GAME)
              .addMatchingUsage(android.media.AudioAttributes.USAGE_UNKNOWN)
              .build();
      AudioFormat format =
          new AudioFormat.Builder()
              .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
              .setSampleRate(SAMPLE_RATE)
              .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
              .build();
      AudioRecord r =
          new AudioRecord.Builder()
              .setAudioPlaybackCaptureConfig(config)
              .setAudioFormat(format)
              .setBufferSizeInBytes(SAMPLE_RATE / 5 * 2)
              .build();
      if (r.getState() != AudioRecord.STATE_INITIALIZED) {
        Log.w(TAG, "AudioRecord not initialized");
        r.release();
        return false;
      }
      r.startRecording();
      record = r;
      ringRead = ringWrite = ringCount = 0;
      final AudioRecord rec = r;
      reader =
          new Thread(
              () -> {
                short[] chunk = new short[SAMPLE_RATE / 100]; // 10ms
                while (true) {
                  int n = rec.read(chunk, 0, chunk.length);
                  if (n <= 0) break;
                  synchronized (ring) {
                    for (int i = 0; i < n; i++) {
                      if (ringCount == ring.length) {
                        ringRead = (ringRead + 1) % ring.length;
                        ringCount--;
                      }
                      ring[ringWrite] = chunk[i];
                      ringWrite = (ringWrite + 1) % ring.length;
                      ringCount++;
                    }
                  }
                }
              },
              "ScreenAudioMixerReader");
      reader.start();
      Log.i(TAG, "started playback capture");
      return true;
    } catch (Throwable e) {
      Log.w(TAG, "start failed: " + e);
      stopLocked();
      return false;
    }
  }

  private void stopLocked() {
    AudioRecord r = record;
    record = null;
    if (r != null) {
      try {
        r.stop();
      } catch (Throwable ignored) {
      }
      try {
        r.release();
      } catch (Throwable ignored) {
      }
    }
    Thread t = reader;
    reader = null;
    if (t != null) t.interrupt();
    synchronized (ring) {
      ringRead = ringWrite = ringCount = 0;
    }
  }

  private double phase = 0;
  private int lastPlay = 0;

  /** マイクの録音バッファへ再生音を混ぜる（{@link ScreenAudioMixerCallback}から呼ぶ）。 */
  long onBuffer(
      ByteBuffer buffer,
      int audioFormat,
      int channelCount,
      int sampleRate,
      int bytesRead,
      long captureTimeNs) {
    if (!wanted || record == null) return captureTimeNs;
    if (audioFormat != AudioFormat.ENCODING_PCM_16BIT || sampleRate <= 0) {
      return captureTimeNs;
    }
    int channels = Math.max(1, channelCount);
    int frames = bytesRead / 2 / channels;
    // 取った再生音は48kHz。録音側が違う時は、最も近いサンプルで間引き・繰り返して合わせる。
    double step = (double) SAMPLE_RATE / sampleRate;
    ByteOrder order = buffer.order();
    buffer.order(ByteOrder.LITTLE_ENDIAN);
    try {
      boolean mute = micMuted;
      synchronized (ring) {
        for (int f = 0; f < frames; f++) {
          int pull = (int) (phase + step) - (int) phase;
          phase += step;
          if (phase > 1e9) phase = 0;
          for (int i = 0; i < pull; i++) {
            if (ringCount > 0) {
              lastPlay = ring[ringRead];
              ringRead = (ringRead + 1) % ring.length;
              ringCount--;
            } else {
              lastPlay = 0;
            }
          }
          int play = lastPlay;
          for (int c = 0; c < channels; c++) {
            int idx = (f * channels + c) * 2;
            int mic = mute ? 0 : buffer.getShort(idx);
            int mixed = mic + play;
            if (mixed > Short.MAX_VALUE) mixed = Short.MAX_VALUE;
            if (mixed < Short.MIN_VALUE) mixed = Short.MIN_VALUE;
            buffer.putShort(idx, (short) mixed);
          }
        }
      }
    } finally {
      buffer.order(order);
    }
    return captureTimeNs;
  }
}
