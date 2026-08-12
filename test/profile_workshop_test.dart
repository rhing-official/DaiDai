import 'dart:async';

import 'package:daidai/features/profile/profile_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/terminology_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/providers/terminology_style_provider.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:daidai/widgets/swipe_gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// arrayUnion/arrayRemoveの実際のFirestore側の一致判定（値そのものの深い比較。
/// Listは順序も含めて内容で比較する）を模す。Dartの既定の`==`（≒
/// `mapEquals`）はListを参照同一性で比較してしまい、同じ内容でも別インスタンス
/// なら不一致になる（本物のFirestoreにはこの問題はない）ため、テスト用の
/// フェイクをより忠実にするために使う。
bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

class _FakeUserRepository implements UserRepository {
  AppUser? saved;

  // 特定のフィールドへの書き込みだけを意図的に遅延させ、複数の追加操作が
  // 重なった状況（例: 遅いアイコンアップロード中に速いニックネーム追加が
  // 先に完了する）を再現するためのフック。
  String? delayedField;
  Completer<void>? _delayGate;

  void blockField(String field) {
    delayedField = field;
    _delayGate = Completer<void>();
  }

  void releaseField() => _delayGate?.complete();

  @override
  Future<AppUser?> getUser(String userId) async => saved;

  @override
  Future<List<AppUser>> getUsersByIds(List<String> userIds) async =>
      saved != null && userIds.contains(saved!.userId) ? [saved!] : [];

  @override
  Stream<AppUser?> watchUser(String userId) => Stream.value(saved);

  @override
  Future<void> createUser(AppUser user) async => saved = user;

  @override
  Future<AppUser?> findByRhingId(String rhingId) async => null;

  @override
  Future<bool> isRhingIdAvailable(String rhingId) async => true;

  @override
  Future<void> updateUser(AppUser user) async => saved = user;

  @override
  Future<void> addToProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  ) async {
    if (field == delayedField) await _delayGate!.future;
    final base = saved ?? AppUser(userId: userId, rhingId: '');
    final json = base.toJson();
    final list = List<Map<String, dynamic>>.from(
      (json[field] as List).cast<Map<String, dynamic>>(),
    )..add(value);
    json[field] = list;
    saved = AppUser.fromJson(json);
  }

  @override
  Future<void> removeFromProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  ) async {
    final base = saved ?? AppUser(userId: userId, rhingId: '');
    final json = base.toJson();
    final list = List<Map<String, dynamic>>.from(
      (json[field] as List).cast<Map<String, dynamic>>(),
    )..removeWhere((v) => _deepEquals(v, value));
    json[field] = list;
    saved = AppUser.fromJson(json);
  }

  @override
  Future<void> setProfileField(
    String userId,
    String field,
    String? value,
  ) async {
    final base = saved ?? AppUser(userId: userId, rhingId: '');
    final json = base.toJson();
    json[field] = value;
    saved = AppUser.fromJson(json);
  }

  @override
  Future<void> updateUserPreference(
    String userId,
    String field,
    Object? value,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> setConversationProfileCard({
    required String userId,
    required String conversationId,
    required String? profileCardId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> saveProfileCard(String userId, ProfileCard card) async {
    final base = saved ?? AppUser(userId: userId, rhingId: '');
    final cards = [...base.profileCards];
    final index = cards.indexWhere((c) => c.id == card.id);
    if (index == -1) {
      cards.add(card);
    } else {
      cards[index] = card;
    }
    saved = base.copyWith(profileCards: cards);
  }

  @override
  Future<void> deleteProfileCard(String userId, String cardId) async {
    final base = saved ?? AppUser(userId: userId, rhingId: '');
    final remaining = base.profileCards.where((c) => c.id != cardId).toList();
    final wasActive = base.activeProfileCardId == cardId;
    saved = base.copyWith(
      profileCards: remaining,
      clearActiveProfileCardId: wasActive,
    );
  }

  @override
  Future<ProfileMaterial> uploadIcon(String userId, Uint8List bytes) {
    throw UnimplementedError();
  }

  @override
  Future<ProfileMaterial> uploadBackgroundImage(
    String userId,
    Uint8List bytes,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteProfileMaterial(ProfileMaterial material) async {}

  @override
  Future<void> syncInvitePreview(String userId) async {}

  @override
  Future<void> requestAccountDeletion(String userId) async {}

  @override
  Future<void> restoreAccount(String userId) async {}

  @override
  Future<void> deleteAccountImmediately() async {}

  @override
  Future<void> touchLastLogin(String userId) async {}

  @override
  Stream<List<AppUser>> watchAllUsersForAdmin() => Stream.value(const []);

  @override
  Future<void> setAccountSuspended(String userId, bool suspended) async {}

  @override
  Future<void> broadcastAnnouncement(String message) async {}

  @override
  Future<bool> bootstrapFirstAdmin() async => false;

  @override
  Future<Map<String, int>> backfillAccountStatusOnce() async => {
    'scanned': 0,
    'backfilled': 0,
  };
}

Future<void> _pumpProfileTab(
  WidgetTester tester,
  AppUser user,
  _FakeUserRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(repo),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.simple),
        initialTerminologyStyleProvider.overrideWithValue(
          TerminologyStyle.worldview,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: ProfileTab(currentUser: user)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// 狭い画面（サイドバー+ドリルダウン方式）でのカテゴリ切り替えスワイプの
// 回帰テスト用。760のブレークポイント未満の幅にする
// （既定のテストサーフェスは800x600で、ブレークポイントを超えてしまうため）。
Future<void> _pumpProfileTabNarrow(
  WidgetTester tester,
  AppUser user,
  _FakeUserRepository repo,
) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(repo),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.simple),
        initialTerminologyStyleProvider.overrideWithValue(
          TerminologyStyle.worldview,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: ProfileTab(currentUser: user)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('工房タブは常に3枠表示し、白紙枠をタップするとカードが作れる', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    // 3枠すべてが「+」の白紙カードとして表示される。
    expect(find.byIcon(Icons.add), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('プロフィールカードを作る'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '仕事用');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('仕事用'), findsOneWidget);
    expect(repo.saved?.profileCards.map((c) => c.name), contains('仕事用'));
    // 残り2枠は依然として白紙のまま。
    expect(find.byIcon(Icons.add), findsNWidgets(2));
  });

  testWidgets('既存カードをタップすると内容が入った選択画面が開く', (tester) async {
    const card = ProfileCard(id: 'c1', name: '既存カード');
    const user = AppUser(userId: 'u1', rhingId: 'taro', profileCards: [card]);
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('既存カード'));
    await tester.pumpAndSettle();

    expect(find.text('プロフィールカードを編集'), findsOneWidget);
    expect(find.text('既存カード'), findsWidgets);
  });

  testWidgets('カード名が未入力のまま保存を押すとエラーが表示され、ダイアログは閉じない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    // カード名を空のまま保存を押す。以前は_save()が無言でreturnするだけで、
    // ボタンを押しても何も起きていないように見えていた（ユーザー報告の再現）。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('プロフィールカードを作る'), findsOneWidget); // ダイアログはまだ開いたまま
    expect(find.text('入力してください'), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('ニックネームが未入力のまま追加を押すとエラーが表示され、ダイアログは閉じない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('呼び名を追加'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();

    expect(find.text('呼び名を追加'), findsWidgets); // ダイアログはまだ開いたまま
    expect(find.text('入力してください'), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('ニックネームは指定字数（20字）を超えて入力できない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('呼び名を追加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'あ' * 30);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, kMaxNicknameLength);
  });

  testWidgets('ステメは指定字数（40字）を超えて入力できない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('一言を追加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'あ' * 60);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, kMaxStatusMessageLength);
  });

  testWidgets('遅いステメ保存の完了中に追加したニックネームが消えない（lost update回帰テスト）', (tester) async {
    // 実際のバグ再現: アイコンアップロード（Storage往復で数秒かかる）の
    // ような遅い保存処理が完了する前に、別の項目（ニックネーム）を
    // 追加すると、以前の実装（AppUser全体をset()で丸ごと上書き）では
    // 後から完了した書き込みが先の書き込みを消してしまっていた。
    // ここではステメの保存をわざと遅延させ、その間にニックネームを
    // 追加した場合に両方とも生き残ることを検証する。
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    repo.blockField('statusMessages');

    // ステメの保存を開始する（サーバー側書き込みは_delayGateでブロックされ、
    // まだ完了しない）。
    await tester.tap(find.text('一言を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'げんき');
    await tester.tap(find.text('追加'));
    await tester.pump();

    // ステメの保存がまだ完了していない間に、ニックネームを追加する。
    await tester.tap(find.text('呼び名を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'たろ');
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();

    // ニックネームは（ステメの保存を待たずに）先に反映されているはず。
    expect(repo.saved?.nicknames.map((n) => n.text), contains('たろ'));

    // 遅延させていたステメの保存を完了させる。
    repo.releaseField();
    await tester.pumpAndSettle();

    // ステメが反映された後も、先に追加したニックネームが消えていないこと
    // （lost updateが起きていないこと）を確認する。
    expect(repo.saved?.statusMessages.map((m) => m.text), contains('げんき'));
    expect(repo.saved?.nicknames.map((n) => n.text), contains('たろ'));
  });

  testWidgets('背景を設定済みのカードでも背景タップで選択メニューが開く（回帰テスト）', (tester) async {
    // 背景を一度設定すると以降タップしても何も起きなくなる不具合の再現テスト。
    // 原因は、背景画像の上に重ねている装飾用グラデーション（子を持たない
    // DecoratedBox）がStack内でヒットテストを奪ってしまい、下にある背景タップの
    // GestureDetectorまでイベントが届かなくなっていたこと。IgnorePointerで
    // 装飾レイヤーをヒットテスト対象から外して解消した。
    const bg1 = ProfileMaterial(
      id: 'bg1',
      url: 'https://example.com/bg1.png',
      storagePath: 'p1',
    );
    const card = ProfileCard(id: 'c1', name: '既存カード', backgroundImageId: 'bg1');
    const user = AppUser(
      userId: 'u1',
      rhingId: 'taro',
      backgroundImages: [bg1],
      profileCards: [card],
    );
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    // 名前ラベル（カード下のText）はタップ不可のため、カード本体（Hero）をタップする。
    await tester.tapAt(tester.getCenter(find.byType(Hero).first));
    await tester.pumpAndSettle();
    // テスト環境ではbackgroundImageのURLへの実際のHTTP取得は失敗する
    // （テストバインディングが常にstatusCode 400を返す仕様）。この
    // NetworkImageLoadException自体は本テストの検証対象ではないため、
    // 後続の失敗として扱われないよう明示的に読み捨てる。
    tester.takeException();

    // 背景タップ用のGestureDetector（HitTestBehavior.opaque指定）を直接タップする。
    // カードのMaterial（borderRadius: circular(24)）配下に絞らないと、画面内の
    // 他のopaqueなGestureDetector（ホーム画面のスワイプ検出等）まで拾ってしまう。
    final cardMaterial = find.byWidgetPredicate(
      (w) => w is Material && w.borderRadius == BorderRadius.circular(24),
    );
    final bgDetector = find.descendant(
      of: cardMaterial,
      matching: find.byWidgetPredicate(
        (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque,
      ),
    );
    expect(bgDetector, findsOneWidget);
    await tester.tap(bgDetector);
    await tester.pumpAndSettle();
    tester.takeException();

    // 背景選択メニューが実際に開くことを確認する。
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
  });

  testWidgets('URLを連続してチェックしても保存の競合でカードが重複しない（回帰テスト）', (tester) async {
    // 過去の実際のバグ: カードの更新保存が「古い値をarrayRemoveで消す→新しい値を
    // arrayUnionで足す」という2手順で、この2手順のセット自体はFirestore側で
    // 原子的にまとまっていなかった。保存の完了を待たずに連続で呼ぶと（URLの
    // チェックボックスを立て続けに2つチェックした場合など）、後発の呼び出しの
    // arrayRemoveが「先発の呼び出しのarrayUnionがまだ反映されていない古い値」を
    // 狙って何もマッチせず空振りし、結果としてprofileCards配列に中間状態と
    // 最終状態の両方が残ってしまっていた（ページをリロードしても消えない、
    // 本物のデータ重複としてユーザー報告された）。
    //
    // 現在は`UserRepository.saveProfileCard`がidをキーに置き換え/追加する
    // 単一の呼び出しになり（`_FakeUserRepository.saveProfileCard`参照）、
    // 「削除→追加」の2手順自体が無くなったためこの競合は構造的に起こり得ない。
    // 連続して保存しても最終的に1件に収束することを確認する。
    const link1 = SnsLink(id: 'l1', url: 'https://www.instagram.com/taro');
    const link2 = SnsLink(id: 'l2', url: 'https://pixiv.net/taro');
    const card = ProfileCard(id: 'c1', name: '既存カード');
    const user = AppUser(
      userId: 'u1',
      rhingId: 'taro',
      snsLinks: [link1, link2],
      profileCards: [card],
    );
    final repo = _FakeUserRepository()..saved = user;
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(Hero).first));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.link));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pumpAndSettle();

    expect(repo.saved?.profileCards.length, 1);
    expect(
      repo.saved?.profileCards.single.snsLinkIds,
      containsAll(['l1', 'l2']),
    );
  });

  testWidgets('空き枠を連続タップしてもカード編集画面は1つしか開かず、重複作成されない（回帰テスト）', (tester) async {
    // 実際のバグ再現: Hero遷移のフェード（300ms）中はInkWellへの反応が一瞬
    // 遅れて見えるため、素早く連打すると_openCardZoomが多重に呼ばれ、同じ枠に
    // 対して別々のidを持つ内容の同じカードが2件作られてしまっていた。
    // ガードにより2回目以降の呼び出しは無視されることを確認する。
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    // pumpAndSettleを挟まず素早く2回タップする（連打相当）。
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    // カード編集画面（名前入力欄）は1つしか開いていない。
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '標準');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repo.saved?.profileCards.length, 1);
  });

  testWidgets('工房の縮小表示（ズームアウト状態）のカードにもSNSのURLが表示される', (tester) async {
    const link1 = SnsLink(id: 'l1', url: 'https://www.instagram.com/taro');
    const link2 = SnsLink(id: 'l2', url: 'https://pixiv.net/taro');
    const card = ProfileCard(id: 'c1', name: '既存カード', snsLinkIds: ['l1', 'l2']);
    const user = AppUser(
      userId: 'u1',
      rhingId: 'taro',
      snsLinks: [link1, link2],
      profileCards: [card],
    );
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    // ダイアログを開かなくても、縮小表示のカードの時点でURL（先頭の
    // https://www.を取り除いた表示）が見えている。
    expect(find.text('instagram.com/taro'), findsOneWidget);
    expect(find.text('pixiv.net/taro'), findsOneWidget);
  });

  testWidgets('狭い画面のドリルダウン中に左スワイプで次のカテゴリへ切り替え、右スワイプで一覧へ戻る（回帰テスト）', (
    tester,
  ) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTabNarrow(tester, user, repo);

    // 工房のカードスロット(Hero: profile-card-slot-*)を目印に、現在
    // どのセクションが表示されているかを判定する。
    Finder cardSlotHeroes() => find.byWidgetPredicate(
      (w) => w is Hero && (w.tag as String).startsWith('profile-card-slot-'),
    );

    // カテゴリ一覧から「工房」（蔵→工房→縁結びの2番目）へドリルダウンする。
    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();
    expect(cardSlotHeroes(), findsWidgets);

    // 左スワイプで次のカテゴリ（縁結び）へ。
    await tester.fling(
      find.byType(SwipeBackDetector),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(cardSlotHeroes(), findsNothing);
    expect(find.text('招待リンク'), findsOneWidget);

    // 右スワイプすると、隣接カテゴリではなく常にカテゴリ一覧へ戻る。
    await tester.fling(
      find.byType(SwipeBackDetector),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.byType(SwipeBackDetector), findsNothing);
    expect(find.text('工房'), findsOneWidget); // 一覧のカテゴリ名として表示される
  });

  testWidgets('過去の重複バグ等でprofileCardsが上限(kMaxProfileCards)を超えていても、'
      '超過分を隠さず全て表示する（回帰テスト）', (tester) async {
    // 過去に「arrayRemove→arrayUnion」の非原子的な2手順のせいで
    // profileCardsに重複が残ってしまった場合、工房タブが先頭3件だけを
    // 位置ベースで表示していると、4件目以降が画面から完全に見えなくなり
    // ユーザーが気付いて削除する手段が無くなってしまっていた。
    // kMaxProfileCards(=3)を超える件数でも、全件がカードスロットとして
    // 表示されることを確認する。
    const cards = [
      ProfileCard(id: 'c1', name: 'カード1'),
      ProfileCard(id: 'c2', name: 'カード2'),
      ProfileCard(id: 'c3', name: 'カード3'),
      ProfileCard(id: 'c4', name: '重複してしまったカード'),
    ];
    const user = AppUser(userId: 'u1', rhingId: 'taro', profileCards: cards);
    final repo = _FakeUserRepository()..saved = user;
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    final cardSlotHeroes = find.byWidgetPredicate(
      (w) => w is Hero && (w.tag as String).startsWith('profile-card-slot-'),
    );
    expect(cardSlotHeroes, findsNWidgets(4));
    // 新規作成用の白紙枠は上限(3枠)以上には増えない。
    expect(find.byIcon(Icons.add), findsNothing);
  });
}
