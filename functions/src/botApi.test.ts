import assert from "node:assert/strict";
import { test } from "node:test";

import {
  BOT_CONTENT_MAX_LENGTH,
  BOT_READ_DEFAULT_LIMIT,
  BOT_READ_MAX_LIMIT,
  BOT_WAIT_MAX_SECONDS,
  botSenderId,
  canAddBotsDirectly,
  canApproveBots,
  canConsentDmBot,
  decodeCursor,
  encodeCursor,
  generateBotToken,
  hashBotToken,
  isReadableByBot,
  normalizeBotName,
  parseBotAuthorization,
  parseBotPostPayload,
  parseBotRoute,
  parseReadParams,
  previewOf,
  verifyBotToken,
} from "./botApi";

test("トークンはbotIdを含み、ハッシュで照合できる", () => {
  const token = generateBotToken("bot1");
  assert.ok(token.startsWith("bot1."));
  const hash = hashBotToken(token);
  assert.ok(verifyBotToken(token, hash));
  assert.ok(!verifyBotToken(`${token}x`, hash));
  assert.ok(!verifyBotToken(token, "short"));
  assert.ok(!verifyBotToken(token, undefined));
});

test("Authorizationヘッダーからトークンとbotidを取り出す", () => {
  assert.deepEqual(parseBotAuthorization("Bot abc.secret"), {
    token: "abc.secret",
    botId: "abc",
  });
  assert.equal(parseBotAuthorization("Bearer abc.secret"), null);
  assert.equal(parseBotAuthorization("Bot nodot"), null);
  assert.equal(parseBotAuthorization("Bot .secret"), null);
  assert.equal(parseBotAuthorization("Bot a/b.secret"), null);
  assert.equal(parseBotAuthorization(undefined), null);
});

test("botの名前を整える", () => {
  assert.equal(normalizeBotName("  Claude  "), "Claude");
  assert.equal(normalizeBotName(""), null);
  assert.equal(normalizeBotName("x".repeat(41)), null);
  assert.equal(normalizeBotName(3), null);
});

test("経路を判定する（関数名の接頭辞も許容）", () => {
  assert.deepEqual(parseBotRoute("GET", "/v1/me"), { kind: "me" });
  assert.deepEqual(parseBotRoute("GET", "/botApi/v1/conversations"), {
    kind: "conversations",
  });
  assert.deepEqual(parseBotRoute("GET", "/v1/groups/g1/rooms/r1/messages"), {
    kind: "readMessages",
    scope: "group",
    conversationId: "g1",
    roomId: "r1",
  });
  assert.deepEqual(parseBotRoute("POST", "/v1/groups/g1/rooms/r1/messages"), {
    kind: "postMessage",
    scope: "group",
    conversationId: "g1",
    roomId: "r1",
  });
  assert.deepEqual(
    parseBotRoute("DELETE", "/v1/groups/g1/rooms/r1/messages/m1"),
    {
      kind: "deleteMessage",
      scope: "group",
      conversationId: "g1",
      roomId: "r1",
      messageId: "m1",
    },
  );
  assert.deepEqual(parseBotRoute("GET", "/v1/dms/d1/rooms/r1/messages"), {
    kind: "readMessages",
    scope: "dm",
    conversationId: "d1",
    roomId: "r1",
  });
  assert.equal(parseBotRoute("GET", "/v1/xs/d1/rooms/r1/messages"), null);
  assert.equal(parseBotRoute("POST", "/v1/me"), null);
  assert.equal(parseBotRoute("GET", "/v2/me"), null);
  assert.equal(parseBotRoute("GET", "/v1/groups/g1/rooms/r1"), null);
  assert.equal(parseBotRoute("GET", "/v1/groups/g/1/rooms/r1/messages"), null);
});

test("カーソルは往復でき、不正な値は拒否する", () => {
  const cursor = { seconds: 1760000000, nanos: 123456000, messageId: "abc_DEF-1" };
  assert.deepEqual(decodeCursor(encodeCursor(cursor)), cursor);
  assert.equal(decodeCursor("%%%"), null);
  assert.equal(decodeCursor(""), null);
  assert.equal(decodeCursor(Buffer.from("x_y").toString("base64url")), null);
});

test("取得のクエリを検証し、上限に収める", () => {
  assert.deepEqual(parseReadParams({}), {
    cursor: null,
    limit: BOT_READ_DEFAULT_LIMIT,
    waitSeconds: 0,
  });
  const p = parseReadParams({ limit: "9999", wait: "999" });
  assert.equal(p?.limit, BOT_READ_MAX_LIMIT);
  assert.equal(p?.waitSeconds, BOT_WAIT_MAX_SECONDS);
  assert.equal(parseReadParams({ limit: "0" })?.limit, 1);
  assert.equal(parseReadParams({ limit: "abc" }), null);
  assert.equal(parseReadParams({ after: "!!" }), null);
});

test("他のbotの投稿・スパムは読ませない", () => {
  assert.ok(isReadableByBot({ senderId: "user1" }));
  assert.ok(isReadableByBot({ senderId: "webhook:w1" }));
  assert.ok(!isReadableByBot({ senderId: botSenderId("b1") }));
  assert.ok(!isReadableByBot({ senderId: "user1", isSpam: true }));
});

test("投稿のボディを検証する", () => {
  assert.deepEqual(parseBotPostPayload({ content: "hi" }), {
    ok: true,
    content: "hi",
    replyToMessageId: null,
    silent: false,
  });
  const reply = parseBotPostPayload({
    content: "hi",
    replyToMessageId: "m1",
    silent: true,
  });
  assert.ok(reply.ok && reply.replyToMessageId === "m1" && reply.silent);
  assert.ok(!parseBotPostPayload({ content: "  " }).ok);
  assert.ok(!parseBotPostPayload({ content: "x".repeat(BOT_CONTENT_MAX_LENGTH + 1) }).ok);
  assert.ok(!parseBotPostPayload({ content: "a", replyToMessageId: "a/b" }).ok);
  assert.ok(!parseBotPostPayload("x").ok);
});

test("プレビューは改行を畳み80字で切る", () => {
  assert.equal(previewOf("a\nb"), "a b");
  assert.equal(previewOf("x".repeat(100)).length, 81);
});

test("追加・承認の権限", () => {
  const group = {
    ownerId: "owner",
    memberPermissions: {
      a: ["manageBots"],
      b: ["addBots"],
      c: ["createInvite"],
    },
  };
  assert.ok(canAddBotsDirectly(group, "owner"));
  assert.ok(canAddBotsDirectly(group, "a"));
  assert.ok(canAddBotsDirectly(group, "b"));
  assert.ok(!canAddBotsDirectly(group, "c"));
  assert.ok(canApproveBots(group, "a"));
  assert.ok(!canApproveBots(group, "b"));
  assert.ok(!canApproveBots(undefined, "a"));
});

test("一対のbotは、所有者以外の参加者だけが同意できる", () => {
  const dm = { participants: ["a", "b"] };
  assert.ok(canConsentDmBot(dm, "b", "a"));
  assert.ok(!canConsentDmBot(dm, "a", "a"));
  assert.ok(!canConsentDmBot(dm, "c", "a"));
  assert.ok(!canConsentDmBot(undefined, "b", "a"));
});
