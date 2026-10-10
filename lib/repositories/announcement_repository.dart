import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/announcement.dart';
import '../models/message.dart';
import '../models/official_profile.dart';
import '../utils/image_format.dart';

/// お便り（運営から全住人への配信、2026-10-10追加）。お便りは住人（`users`）
/// ではなく、`announcements`（配信1件ごと）と`system/official`（発信元の
/// 名前・アイコン）という「そこにある物」として持つ。配信はCloud Functions
/// （`broadcastAnnouncement`）経由。名前・アイコンの更新は管理者のみ
/// （firestore.rules・storage.rules）。
abstract class AnnouncementRepository {
  /// 配信を古い順に流す。
  Stream<List<Announcement>> watchAnnouncements();

  /// 発信元の名前・アイコン（`system/official`が未作成なら既定値）。
  Stream<OfficialProfile> watchOfficialProfile();

  /// お便りの配信を、`ChatScreen`にそのまま渡せる[Message]の列にして流す
  /// （`senderId`は[OfficialProfile.senderId]、表示名とアイコンは発信元の値）。
  Stream<List<Message>> watchAnnouncementMessages();

  /// 全住人へお便りを配信する（管理者のみ）。
  Future<void> broadcast(String message);

  /// 発信元の名前を更新する（管理者のみ）。
  Future<void> updateOfficialName(String name);

  /// 発信元のアイコンをアップロードして差し替える（管理者のみ）。
  Future<void> updateOfficialIcon(Uint8List bytes);
}

/// [Announcement]を、`ChatScreen`で表示できる[Message]へ写す。
Message announcementToMessage(
  Announcement announcement,
  OfficialProfile profile,
) {
  return Message(
    messageId: announcement.id,
    conversationId: 'announcements',
    conversationType: 'dm',
    senderId: OfficialProfile.senderId,
    botName: profile.name,
    botIconUrl: profile.iconUrl,
    content: announcement.content,
    contentType: 'text',
    sentAt: announcement.createdAt,
  );
}

class FirestoreAnnouncementRepository implements AnnouncementRepository {
  FirestoreAnnouncementRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1'),
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  DocumentReference<Map<String, dynamic>> get _officialDoc =>
      _firestore.collection('system').doc('official');

  @override
  Stream<List<Announcement>> watchAnnouncements() {
    return _firestore
        .collection('announcements')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              Announcement.fromJson(doc.id, doc.data()),
          ],
        );
  }

  @override
  Stream<OfficialProfile> watchOfficialProfile() {
    return _officialDoc.snapshots().map(
      (snapshot) => OfficialProfile.fromJson(snapshot.data()),
    );
  }

  @override
  Stream<List<Message>> watchAnnouncementMessages() {
    late final StreamController<List<Message>> controller;
    StreamSubscription<List<Announcement>>? announcementsSub;
    StreamSubscription<OfficialProfile>? profileSub;
    List<Announcement>? announcements;
    OfficialProfile? profile;

    void emit() {
      final a = announcements;
      final p = profile;
      if (a == null || p == null || controller.isClosed) return;
      controller.add([for (final item in a) announcementToMessage(item, p)]);
    }

    controller = StreamController<List<Message>>(
      onListen: () {
        announcementsSub = watchAnnouncements().listen((value) {
          announcements = value;
          emit();
        }, onError: controller.addError);
        profileSub = watchOfficialProfile().listen((value) {
          profile = value;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await announcementsSub?.cancel();
        await profileSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> broadcast(String message) async {
    await _functions.httpsCallable('broadcastAnnouncement').call({
      'message': message,
    });
  }

  @override
  Future<void> updateOfficialName(String name) {
    return _officialDoc.set({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateOfficialIcon(Uint8List bytes) async {
    // 住人のアイコンと同じ方針（WebPへ圧縮、GIFはそのまま、圧縮できない
    // 環境では元のバイトのまま、`UserRepository._uploadMaterial`参照）。
    final isGif = isGifBytes(bytes);
    Uint8List? compressed;
    if (!isGif && (kIsWeb || !(Platform.isWindows || Platform.isLinux))) {
      try {
        compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 512,
          minHeight: 512,
          quality: 85,
          format: CompressFormat.webp,
        );
      } catch (_) {
        compressed = null;
      }
    }
    final String extension;
    final String contentType;
    if (isGif) {
      extension = 'gif';
      contentType = 'image/gif';
    } else if (compressed != null) {
      extension = 'webp';
      contentType = 'image/webp';
    } else {
      final format = rawUploadFormatFor(bytes);
      extension = format.extension;
      contentType = format.contentType;
    }
    final id = _firestore.collection('system').doc().id;
    final ref = _storage.ref('officialAssets/icons/$id.$extension');
    await ref.putData(
      compressed ?? bytes,
      SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();
    await _officialDoc.set({
      'iconUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
