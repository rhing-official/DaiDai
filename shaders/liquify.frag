#version 460 core

precision mediump float;

#include <flutter/runtime_effect.glsl>

// 「吸い込み」遷移用の液状化（2026-11-04、初版・調整前提）。
// 子の描画結果を、波打たせながら右下の角へ渦状にすぼめる。逆写像: 出力の各ピクセル
// が、元画像のどこを引いて表示するかを決める。
uniform vec2 uSize;
uniform float uProgress; // 0=通常, 1=吸い込み切る
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float p = clamp(uProgress, 0.0, 1.0);

  // 右下の角を中心に、角に近いほど強く引き込む（漏斗状）＋渦。
  vec2 c = vec2(1.0, 1.0);
  vec2 d = uv - c;
  float r = length(d);
  float near = 1.0 - smoothstep(0.0, 1.42, r); // 角に近いほど1

  // 渦: 角に近いほど大きく回す。
  float angle = p * 2.2 * near;
  float cs = cos(angle);
  float sn = sin(angle);
  d = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y);

  // すぼまり: 出力が角に近い所ほど、遠い元の位置を引く。
  d *= 1.0 + p * 1.6 * near;

  vec2 src = c + d;

  // 波打ち（グニャグニャ）。
  float wave = p * 0.05;
  src.x += wave * sin(uv.y * 12.0 + p * 9.0);
  src.y += wave * sin(uv.x * 10.0 + p * 11.0);

  if (src.x < 0.0 || src.x > 1.0 || src.y < 0.0 || src.y > 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  fragColor = texture(uTexture, src);
}
