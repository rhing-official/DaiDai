import 'package:flutter/material.dart';

import '../models/profile_card.dart';
import 'focal_circle_avatar.dart';
import 'generated_avatar.dart';

/// アカウントの切り替え一覧に出す、そのアカウントの標準のアイコン（2026-11-11）。
/// アイコンが無ければ、uidから決まる生成アバター。
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    required this.uid,
    required this.rhingSeed,
    this.iconUrl,
    this.iconFocal,
    this.size = 36,
    super.key,
  });

  final String uid;
  final String rhingSeed;
  final String? iconUrl;
  final ImageFocal? iconFocal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final generated = GeneratedAvatar(seed: uid, label: rhingSeed, size: size);
    final url = iconUrl;
    if (url == null || url.isEmpty) return generated;
    return FocalCircleAvatar(
      url: url,
      focal: iconFocal,
      radius: size / 2,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      fallback: generated,
    );
  }
}
