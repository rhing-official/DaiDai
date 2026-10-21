import assert from "node:assert/strict";
import { test } from "node:test";

import { filterTurnIceServers } from "./turnCredentials";

test("ポート53のURLを外し、必要な項目だけを残す", () => {
  const result = filterTurnIceServers([
    { urls: ["stun:stun.cloudflare.com:3478"] },
    {
      urls: [
        "turn:turn.cloudflare.com:3478?transport=udp",
        "turn:turn.cloudflare.com:53?transport=udp",
        "turns:turn.cloudflare.com:5349?transport=tcp",
      ],
      username: "u",
      credential: "c",
      extra: "x",
    },
  ]);
  assert.deepEqual(result, [
    { urls: ["stun:stun.cloudflare.com:3478"] },
    {
      urls: [
        "turn:turn.cloudflare.com:3478?transport=udp",
        "turns:turn.cloudflare.com:5349?transport=tcp",
      ],
      username: "u",
      credential: "c",
    },
  ]);
});

test("urlsが文字列1つでも扱える。想定外の形は捨てる", () => {
  assert.deepEqual(filterTurnIceServers([{ urls: "stun:a:3478" }, null, 1, {}]), [
    { urls: ["stun:a:3478"] },
  ]);
  assert.deepEqual(filterTurnIceServers(undefined), []);
  assert.deepEqual(filterTurnIceServers("x"), []);
});

test("ポート53だけのエントリは丸ごと捨てる", () => {
  assert.deepEqual(
    filterTurnIceServers([{ urls: ["turn:t:53?transport=udp"], username: "u" }]),
    [],
  );
});
