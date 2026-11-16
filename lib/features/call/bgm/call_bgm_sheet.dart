import '../../../utils/auto_dismiss_banner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../widgets/transitioned_overlay.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../l10n/strings.dart';
import '../../../models/app_ui_style.dart';
import '../../../providers/app_ui_style_provider.dart';
import '../../../providers/bgm_preferences_provider.dart';
import '../../../router/back_stack.dart';
import '../../../theme/block/block_theme.dart';
import '../../../widgets/glass/glass_surface.dart';
import '../../../widgets/media_preview_frame.dart';
import '../../../widgets/style_choice_chip.dart';
import '../../../widgets/toggles/app_checkbox.dart';
import 'bgm_import_source.dart';
import 'bgm_queue.dart' show kBgmUnclassifiedScope;
import 'bgm_track.dart';
import 'bgm_player_widgets.dart';
import 'call_bgm.dart';

/// 通話のBGMの操作に必要なものをまとめた束（2026-11-03）。通話画面のボタン列
/// （`CallControlBar`）へ、1対1・広場のコントローラーの違いを隠して渡す。
class CallBgmBinding {
  const CallBgmBinding({
    required this.bgm,
    required this.controller,
    required this.otherPlayingTitle,
  });

  final CallBgm bgm;

  /// 通話コントローラー（相手のBGMの状態が変わったらシートを描き直す）。
  final Listenable controller;

  /// 他の人が流している曲名（いなければnull）。
  final String? Function() otherPlayingTitle;
}

/// 拡張子から音声のMIMEタイプを決める（`<audio>`が形式を判別出来るように）。
String bgmMimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'm4a' || 'mp4' || 'aac' => 'audio/mp4',
    'wav' => 'audio/wav',
    'ogg' || 'oga' || 'opus' => 'audio/ogg',
    'flac' => 'audio/flac',
    'webm' => 'audio/webm',
    _ => 'audio/mpeg',
  };
}

/// 拡張子を除いた表示名。
String bgmDisplayName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

Future<void> showCallBgmSheet(BuildContext context, CallBgmBinding binding) {
  binding.bgm.loadTracks();
  // PC・Webの通話画面（`CallOverlay`）は`MaterialApp.builder`の位置にあり、Navigatorが
  // 無い為、`showModalBottomSheet`は例外になり何も起きない（2026-11-15）。専用の
  // `Overlay`へ直接出す。
  if (Navigator.maybeOf(context) == null) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return Future.value();
    showTransitionedOverlay(
      overlay,
      builder: (context, close) => PointerInterceptor(
        child: BackEntry(
          scope: null,
          active: true,
          layer: true,
          onBack: close,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: CallPanelSurface(
                  child: BgmSpaceKeyToggle(
                    bgm: binding.bgm,
                    child: _CallBgmSheet(binding: binding),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => CallPanelSurface(
      child: BgmSpaceKeyToggle(
        bgm: binding.bgm,
        child: _CallBgmSheet(binding: binding),
      ),
    ),
  );
}

/// BGMのシートの面。UIスタイル（フラット・ガラス・劇画・版画）に合わせる（2026-11-15）。
/// 上端だけ角丸の、下から出る面で、影は使わない（版画だけ、ぼかしの無い硬い影の例外）。
class CallPanelSurface extends ConsumerWidget {
  const CallPanelSurface({
    required this.child,
    this.allRounded = false,
    super.key,
  });

  final Widget child;

  /// 下も角丸にする（ポップアップ用。下から出るシートは上だけ角丸）。
  final bool allRounded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final theme = Theme.of(context);
    final radius = allRounded
        ? BorderRadius.circular(24)
        : const BorderRadius.vertical(top: Radius.circular(24));
    // ガラス・劇画の面は`Material`を作らないため、`ListTile`・`Slider`等が描けるよう透明な
    // `Material`で包む。
    final child = Material(type: MaterialType.transparency, child: this.child);
    return switch (uiStyle) {
      AppUiStyle.gekiga => GekigaStraightMonochromeBox(
        isMe: false,
        child: child,
      ),
      AppUiStyle.glass => GlassSurface(
        variant: GlassVariant.floating,
        borderRadius: radius,
        child: ClipRRect(borderRadius: radius, child: child),
      ),
      AppUiStyle.block => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: BlockTheme.shadow(
            theme.colorScheme.primary,
            theme.brightness,
          ),
        ),
        child: Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: BlockTheme.lineColor(theme.brightness),
              width: BlockTheme.borderWidth,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
      _ => Material(
        color: theme.colorScheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    };
  }
}

/// シートを閉じても残す、開いていた状態。
class _SheetMemory {
  int tab = 0;
  String? albumId;
  double scroll = 0;

  /// アルバムの帯（横）のスクロール位置（2026-11-16）。
  double albumStripScroll = 0;
  final Set<String> openArtists = {};
  final Set<String> openArtistAlbums = {};
}

class _CallBgmSheet extends ConsumerStatefulWidget {
  const _CallBgmSheet({required this.binding});

  final CallBgmBinding binding;

  @override
  ConsumerState<_CallBgmSheet> createState() => _CallBgmSheetState();
}

class _CallBgmSheetState extends ConsumerState<_CallBgmSheet> {
  /// 0: アルバム（ジャケットの帯＋曲の一覧）、1: アーティスト別。
  static const _tabArtists = 0;
  static const _tabAlbums = 1;
  static const _tabFavorites = 2;

  /// 閉じる前に開いていた状態（タブ・アルバム・開いたアーティスト・スクロール位置）。
  /// 開き直した時に、同じ所から続ける（アプリを開いている間は残る）。
  static final _memory = _SheetMemory();

  /// 起動後の最初に開く時だけ、保存された前回のタブ・アルバムを読み込む。
  static bool _memoryLoaded = false;

  int _tab = _memory.tab;

  /// 選んでいるアルバム（nullは、すべての曲）。
  String? _albumId = _memory.albumId;

  /// アルバムのジャケットの帯（横スクロール）のスクロールバー用。
  final ScrollController _albumStripScroll = ScrollController(
    initialScrollOffset: _memory.albumStripScroll,
  );

  /// 曲の検索語（シートを開いている間だけ。空でなければ、タブの一覧の代わりに検索結果を出す）。
  final TextEditingController _searchController = TextEditingController();

  late ScrollController _scroll = ScrollController(
    initialScrollOffset: _memory.scroll,
  );

  void _selectTab(int tab) => setState(() {
    if (_tab == tab) return;
    _tab = tab;
    ref.read(bgmPreferencesProvider.notifier).saveTab(tab);
    _scroll.dispose();
    _scroll = ScrollController();
  });

  /// アルバム名の入力中（作成・名前の変更）。ダイアログはNavigatorの無い通話画面で出せない為、
  /// 一覧の中に入力欄を出す。
  bool _creating = false;
  bool _renaming = false;
  final _nameController = TextEditingController();

  /// チェックで選んでいる曲（複数選択）。
  final Set<String> _selected = {};

  void _toggleSelect(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _clearSelection() => setState(() {
    _selected.clear();
  });

  /// 開いているアーティスト（アーティスト不明は空文字）。
  final Set<String> _openArtists = _memory.openArtists;

  /// アーティストの中で開いているアルバム（`アーティスト\u0000アルバムid`）。
  final Set<String> _openArtistAlbums = _memory.openArtistAlbums;

  CallBgm get _bgm => widget.binding.bgm;

  @override
  void initState() {
    super.initState();
    if (!_memoryLoaded) {
      _memoryLoaded = true;
      final saved = ref.read(bgmPreferencesProvider);
      _memory.tab = saved.tab;
      _memory.albumId = saved.albumId;
      _tab = saved.tab;
      _albumId = saved.albumId;
    }
  }

  /// 選んでいるアルバムを変える。端末にだけ保存する（idは端末固有）。
  void _setAlbum(String? id) {
    _albumId = id;
    ref.read(bgmPreferencesProvider.notifier).saveAlbumId(id);
  }

  @override
  void dispose() {
    _memory.tab = _tab;
    _memory.albumId = _albumId;
    _memory.scroll = _scroll.hasClients ? _scroll.offset : 0;
    _memory.albumStripScroll = _albumStripScroll.hasClients
        ? _albumStripScroll.offset
        : 0;
    _scroll.dispose();
    _albumStripScroll.dispose();
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _banner(String message) {
    final overlay = Overlay.maybeOf(context);
    if (overlay != null) showAutoDismissBannerIn(overlay, message: message);
  }

  Future<void> _addFiles(Strings strings) async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (files.isEmpty) return;
      final failed = await _bgm.importFiles([
        for (final f in files)
          BgmImportFile(name: f.name, readBytes: f.readAsBytes),
      ], intoAlbumId: _tab == _tabAlbums ? _albumId : null);
      if (failed > 0) _banner(strings.callBgmAddFailed);
    } catch (_) {
      _banner(strings.callBgmAddFailed);
    }
  }

  /// ディレクトリごと取り込む。ディレクトリ名のアルバムに入る（サブディレクトリも、それぞれのアルバム）。
  Future<void> _addFolder(Strings strings) async {
    try {
      final files = await pickBgmFolder();
      if (files.isEmpty) {
        _banner(strings.callBgmNoAudioInFolder);
        return;
      }
      final failed = await _bgm.importFiles(files);
      if (failed > 0) _banner(strings.callBgmAddFailed);
    } catch (_) {
      _banner(strings.callBgmAddFailed);
    }
  }

  Future<void> _submitName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_creating) {
      await _bgm.addAlbum(name);
    } else if (_renaming && _albumId != null) {
      await _bgm.renameAlbum(_albumId!, name);
    }
    if (!mounted) return;
    setState(() {
      _creating = false;
      _renaming = false;
      _nameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final bgm = _bgm;
    final size = MediaQuery.sizeOf(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: size.height * 0.88,
          maxWidth: 920,
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([bgm, widget.binding.controller]),
          builder: (context, _) {
            final other = widget.binding.otherPlayingTitle();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 広い画面は、左に曲の一覧、右に大きなプレーヤーの2列にする。
                  final wide = constraints.maxWidth >= 720;
                  // 見出し・注意書きの分を残して、残りの高さに収める。
                  final available = constraints.maxHeight.isFinite
                      ? constraints.maxHeight - 130
                      : 480.0;
                  final bodyHeight = (size.height * 0.62)
                      .clamp(240.0, 620.0)
                      .clamp(0.0, available < 240 ? 240.0 : available);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            strings.callBgmTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      if (other != null) ...[
                        const SizedBox(height: 8),
                        Text(strings.callBgmOtherPlaying(other)),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        strings.callBgmHeadphones,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: bodyHeight,
                        child: wide
                            ? Row(
                                children: [
                                  Expanded(
                                    flex: 11,
                                    child: _library(strings, bgm),
                                  ),
                                  const SizedBox(width: 12),
                                  VerticalDivider(
                                    width: 1,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.15),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 9,
                                    child: _bigPlayer(strings, bgm),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  if (bgm.current != null)
                                    _compactPlayer(strings, bgm),
                                  _volumeRow(strings, bgm),
                                  Expanded(child: _library(strings, bgm)),
                                ],
                              ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _volumeRow(Strings strings, CallBgm bgm) => Row(
    children: [
      Text(strings.callBgmVolume),
      IconButton(
        tooltip: strings.callBgmVolumeDown,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove),
        onPressed: () => bgm.setVolume(bgm.volume - 0.01),
      ),
      Expanded(
        child: Slider(
          value: bgm.volume,
          divisions: 100,
          label: '${(bgm.volume * 100).round()}%',
          onChanged: bgm.setVolume,
        ),
      ),
      IconButton(
        tooltip: strings.callBgmVolumeUp,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add),
        onPressed: () => bgm.setVolume(bgm.volume + 0.01),
      ),
      SizedBox(
        width: 44,
        child: Text(
          '${(bgm.volume * 100).round()}%',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  /// 右の大きなプレーヤー（ジャケット・曲名・アーティスト・シークバー・操作・音量）。
  Widget _bigPlayer(Strings strings, CallBgm bgm) {
    final track = bgm.current;
    final theme = Theme.of(context);
    final albumName = track == null
        ? null
        : bgm.albums.where((a) => a.id == track.albumId).firstOrNull?.name ??
              track.tagAlbum;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, c) {
                final side =
                    (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight).clamp(
                      96.0,
                      320.0,
                    );
                return track == null
                    ? Container(
                        width: side,
                        height: side,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.06,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.music_note,
                              size: side * 0.3,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.callBgmNothingPlaying,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      )
                    : BgmCoverImage(bgm: bgm, track: track, size: side);
              },
            ),
          ),
        ),
        if (track != null) ...[
          const SizedBox(height: 8),
          Text(
            track.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          if (track.artist != null)
            Text(
              track.artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          if (albumName != null)
            Text(
              albumName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          BgmSeekBar(bgm: bgm),
          BgmTransportControls(bgm: bgm, strings: strings, full: true),
        ],
        _volumeRow(strings, bgm),
      ],
    );
  }

  /// 狭い画面の、再生中のプレーヤー（小さなジャケット・曲名・シークバー・操作）。
  Widget _compactPlayer(Strings strings, CallBgm bgm) {
    final track = bgm.current!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            BgmCoverImage(bgm: bgm, track: track, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (track.artist != null)
                    Text(
                      track.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
        BgmSeekBar(bgm: bgm),
        BgmTransportControls(bgm: bgm, strings: strings, full: true),
      ],
    );
  }

  Widget _nameField(Strings strings) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: strings.callBgmAlbumNameHint,
              isDense: true,
            ),
            onSubmitted: (_) => _submitName(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _submitName,
          child: Text(strings.callBgmCreate),
        ),
      ],
    ),
  );

  /// 何も流していない時に出す「前回の続き」（最後に再生していた曲と位置。曲が端末に残っている時だけ）。
  /// 通話の開始時に自動では流さず、ここを押した時だけ流す。曲名は端末の中だけで使い、アカウントへは保存しない。
  Widget _resumeRow(Strings strings, CallBgm bgm) {
    final last = ref.watch(bgmPreferencesProvider).lastPlayed;
    if (last == null || bgm.playing) return const SizedBox.shrink();
    final track = bgm.tracks.where((t) => t.id == last.trackId).firstOrNull;
    if (track == null) return const SizedBox.shrink();
    final seconds = last.positionMs ~/ 1000;
    final position =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: const ValueKey('bgm-resume-last'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.play_circle_outline),
        title: Text(
          strings.callBgmResumeLast(track.name, position),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => bgm.resumeLast(last),
      ),
    );
  }

  /// 左の曲の置き場（タブ・追加ボタン・ジャケットの帯・曲の一覧）。
  Widget _library(Strings strings, CallBgm bgm) {
    final uiStyle = ref.watch(appUiStyleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _resumeRow(strings, bgm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StyleChoiceChip(
              uiStyle: uiStyle,
              selected: _tab == _tabArtists,
              onTap: () => _selectTab(_tabArtists),
              labelBuilder: (fg) =>
                  Text(strings.callBgmTabArtists, style: TextStyle(color: fg)),
            ),
            StyleChoiceChip(
              uiStyle: uiStyle,
              selected: _tab == _tabAlbums,
              onTap: () => _selectTab(_tabAlbums),
              labelBuilder: (fg) =>
                  Text(strings.callBgmTabAlbums, style: TextStyle(color: fg)),
            ),
            StyleChoiceChip(
              uiStyle: uiStyle,
              selected: _tab == _tabFavorites,
              onTap: () => _selectTab(_tabFavorites),
              labelBuilder: (fg) => Text(
                strings.callBgmTabFavorites,
                style: TextStyle(color: fg),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _addFiles(strings),
              icon: const Icon(Icons.add),
              label: Text(strings.callBgmAdd),
            ),
            OutlinedButton.icon(
              onPressed: () => _addFolder(strings),
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(strings.callBgmAddFolder),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _creating = true;
                _renaming = false;
                _nameController.clear();
              }),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(strings.callBgmNewAlbum),
            ),
          ],
        ),
        ValueListenableBuilder<BgmImportProgress?>(
          valueListenable: bgm.importProgress,
          builder: (context, progress, _) {
            if (progress == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.callBgmImporting(progress.done, progress.total),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progress.total == 0
                        ? null
                        : progress.done / progress.total,
                  ),
                ],
              ),
            );
          },
        ),
        if (_creating) _nameField(strings),
        if (_selected.isNotEmpty) _selectionBar(strings, bgm),
        const SizedBox(height: 8),
        _searchField(strings),
        const SizedBox(height: 8),
        Expanded(
          child: _searchController.text.trim().isNotEmpty
              ? _searchResults(strings, bgm)
              : switch (_tab) {
                  _tabAlbums => _albumsTab(strings, bgm),
                  _tabFavorites => _favoritesTab(strings, bgm),
                  _ => _artistsTab(strings, bgm),
                },
        ),
      ],
    );
  }

  /// 曲の検索ボックス（曲名・アーティスト・タグのアルバム名。入力がある間は検索結果を出す）。
  Widget _searchField(Strings strings) => TextField(
    controller: _searchController,
    decoration: InputDecoration(
      hintText: strings.callBgmSearchHint,
      isDense: true,
      prefixIcon: const Icon(Icons.search, size: 20),
      suffixIcon: _searchController.text.isEmpty
          ? null
          : IconButton(
              tooltip: strings.callBgmSearchClear,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(_searchController.clear),
            ),
    ),
    onChanged: (_) => setState(() {}),
  );

  /// 全曲からの検索結果（元の並びのまま。行は他のタブと同じで、再生・選択・お気に入り・移動・削除ができる）。
  Widget _searchResults(Strings strings, CallBgm bgm) {
    final results = searchBgmTracks(bgm.tracks, _searchController.text);
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          bgm.tracks.isEmpty
              ? strings.callBgmEmpty
              : strings.callBgmSearchNoResults,
        ),
      );
    }
    return ListView(
      controller: _scroll,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            strings.callBgmTrackCount(results.length),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final t in results) _trackRow(strings, bgm, t, t.albumId),
      ],
    );
  }

  /// 選んでいる曲の操作（件数・全て選択・お気に入り・削除・選択解除）。
  Widget _selectionBar(Strings strings, CallBgm bgm) {
    // 消えた曲が選択に残らないようにする。
    final existing = {for (final t in bgm.tracks) t.id: t};
    _selected.removeWhere((id) => !existing.containsKey(id));
    final chosen = [for (final id in _selected) existing[id]!];
    if (chosen.isEmpty) return const SizedBox.shrink();
    final visible = switch (_tab) {
      _tabAlbums => bgm.tracksOf(
        bgm.albums.any((a) => a.id == _albumId) ? _albumId : null,
      ),
      _tabFavorites => bgm.favorites,
      _ => bgm.tracks,
    };
    final allFavorite = chosen.every(bgm.isFavorite);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                strings.callBgmSelectedCount(chosen.length),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              TextButton(
                onPressed: () => setState(() {
                  for (final t in visible) {
                    _selected.add(t.id);
                  }
                }),
                child: Text(strings.callBgmSelectAll),
              ),
              IconButton(
                tooltip: allFavorite
                    ? strings.callBgmUnfavoriteSelected
                    : strings.callBgmFavoriteSelected,
                icon: Icon(allFavorite ? Icons.star : Icons.star_border),
                onPressed: () => bgm.setFavorites(chosen, !allFavorite),
              ),
              IconButton(
                tooltip: strings.callBgmDeleteSelected,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await bgm.removeTracks(chosen);
                  if (mounted) _clearSelection();
                },
              ),
              IconButton(
                tooltip: strings.callBgmClearSelection,
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// スクロールバーを出すか。モバイル（スマホ・タブレットのアプリ、モバイルのブラウザ）では出さない。
  bool get _showScrollbars =>
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  /// アルバムの帯にスクロールバーを付ける（モバイルでは付けない）。
  Widget _albumStripScrollbar(Widget list) {
    // 既定のスクロールバーと二重にならないよう、既定は止めて自前で付ける。
    final plain = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: list,
    );
    if (!_showScrollbars) return plain;
    return Scrollbar(
      controller: _albumStripScroll,
      thumbVisibility: true,
      child: Padding(padding: const EdgeInsets.only(bottom: 12), child: plain),
    );
  }

  /// アルバムのジャケットの帯（先頭は「すべての曲」）と、選んだアルバムの曲の一覧。
  Widget _albumsTab(Strings strings, CallBgm bgm) {
    final album = bgm.albums.where((a) => a.id == _albumId).firstOrNull;
    // 消えたアルバムを選んだままにしない。
    if (_albumId != null && album == null) _albumId = null;
    final tracks = bgm.tracksOf(album?.id);
    final knownMs = [
      for (final t in tracks) t.durationMs ?? 0,
    ].fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 124 + (_showScrollbars ? 12 : 0),
          child: _albumStripScrollbar(
            ListView(
              scrollDirection: Axis.horizontal,
              controller: _albumStripScroll,
              children: [
                _AlbumCard(
                  bgm: bgm,
                  label: strings.callBgmAllTracks,
                  count: bgm.tracks.length,
                  coverTrack: bgm.coverTrackOfAlbum(null),
                  fallbackIcon: Icons.library_music_outlined,
                  selected: _albumId == null,
                  strings: strings,
                  onTap: () => setState(() {
                    _setAlbum(null);
                    _renaming = false;
                  }),
                ),
                for (final a in bgm.albums)
                  _AlbumCard(
                    bgm: bgm,
                    label: a.name,
                    count: bgm.tracksOf(a.id).length,
                    coverTrack: bgm.coverTrackOfAlbum(a.id),
                    fallbackIcon: Icons.album_outlined,
                    selected: _albumId == a.id,
                    strings: strings,
                    onTap: () => setState(() {
                      _setAlbum(a.id);
                      _renaming = false;
                    }),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album?.name ?? strings.callBgmAllTracks,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    [
                      strings.callBgmTrackCount(tracks.length),
                      if (knownMs > 0)
                        strings.callBgmTotalDuration(
                          formatBgmDuration(Duration(milliseconds: knownMs)),
                        ),
                    ].join(' ・ '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (tracks.isNotEmpty)
              IconButton(
                tooltip: strings.callBgmPlayAll,
                icon: const Icon(Icons.play_circle_outline),
                onPressed: () =>
                    bgm.play(tracks.first, albumId: album?.id, inAlbum: true),
              ),
            if (album != null) ...[
              IconButton(
                tooltip: strings.callBgmRename,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => setState(() {
                  _renaming = true;
                  _creating = false;
                  _nameController.text = album.name;
                }),
              ),
              IconButton(
                tooltip: strings.callBgmDeleteAlbum,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await bgm.removeAlbum(album.id);
                  if (mounted) setState(() => _setAlbum(null));
                },
              ),
            ],
          ],
        ),
        if (_renaming) _nameField(strings),
        const Divider(height: 8),
        Expanded(
          child: tracks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    album != null
                        ? strings.callBgmAlbumEmpty
                        : strings.callBgmEmpty,
                  ),
                )
              : album != null && bgm.albumHasMultipleDiscs(album.id)
              // 複数ディスクのアルバム: 「Disc 1」「Disc 2」の見出しで区切る（並べ替えは出来ない）。
              ? ListView(
                  controller: _scroll,
                  children: _discSections(strings, bgm, tracks, album.id),
                )
              : album != null
              ? ReorderableListView(
                  scrollController: _scroll,
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) {
                    final list = [...tracks];
                    final moved = list.removeAt(from);
                    list.insert(to, moved);
                    bgm.reorderTracks(list);
                  },
                  children: [
                    for (var i = 0; i < tracks.length; i++)
                      Row(
                        key: ValueKey(tracks[i].id),
                        children: [
                          Expanded(
                            child: _trackRow(
                              strings,
                              bgm,
                              tracks[i],
                              album.id,
                              number: i + 1,
                            ),
                          ),
                          // チェックボックスを左端に置く為、つかむ部分は右端。
                          ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle, size: 20),
                          ),
                        ],
                      ),
                  ],
                )
              : ListView(
                  controller: _scroll,
                  children: [
                    for (final t in tracks) _trackRow(strings, bgm, t, null),
                  ],
                ),
        ),
      ],
    );
  }

  /// 複数ディスクのアルバムの曲を、ディスクごとの見出し付きで並べる（トラック番号はディスクごとに1から）。
  List<Widget> _discSections(
    Strings strings,
    CallBgm bgm,
    List<BgmTrack> tracks,
    String albumId,
  ) {
    final widgets = <Widget>[];
    int? currentDisc;
    var number = 0;
    for (final t in tracks) {
      final disc = t.discNo ?? 1;
      if (disc != currentDisc) {
        currentDisc = disc;
        number = 0;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              strings.callBgmDisc(disc),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
      }
      number++;
      widgets.add(_trackRow(strings, bgm, t, albumId, number: number));
    }
    return widgets;
  }

  /// お気に入りの曲だけを、平らに並べる（ここから流すと、次の曲もお気に入りの中）。
  Widget _favoritesTab(Strings strings, CallBgm bgm) {
    final list = bgm.favorites;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(strings.callBgmFavoritesEmpty),
      );
    }
    return ListView(
      controller: _scroll,
      children: [
        for (final t in list) _trackRow(strings, bgm, t, null, favorites: true),
      ],
    );
  }

  /// アーティスト別の一覧（タグのアーティスト。見出しを押すと、曲が開く）。
  Widget _artistsTab(Strings strings, CallBgm bgm) {
    final groups = bgm.tracksByArtist();
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(strings.callBgmEmpty),
      );
    }
    return ListView(
      controller: _scroll,
      children: [
        for (final g in groups) ...[
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: _artistAvatar(bgm, g.artist),
            title: Text(
              g.artist ?? strings.callBgmUnknownArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(strings.callBgmTrackCount(g.tracks.length)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (g.artist != null) _artistPhotoMenu(strings, bgm, g.artist!),
                Icon(
                  _openArtists.contains(g.artist ?? '')
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
              ],
            ),
            onTap: () => setState(() {
              final key = g.artist ?? '';
              if (!_openArtists.remove(key)) _openArtists.add(key);
            }),
          ),
          if (_openArtists.contains(g.artist ?? ''))
            ..._artistAlbumRows(strings, bgm, g.artist, g.tracks),
        ],
      ],
    );
  }

  /// アーティストの左端。登録した写真があれば丸い写真、無ければ人型のアイコン。
  Widget _artistAvatar(CallBgm bgm, String? artist) {
    final photo = bgm.artistPhotoOf(artist);
    if (photo == null) return const Icon(Icons.person_outline);
    return CircleAvatar(radius: 18, backgroundImage: MemoryImage(photo));
  }

  /// アーティスト写真の登録・変更・削除のメニュー（写真が無ければ、押すとすぐ選べる）。
  Widget _artistPhotoMenu(Strings strings, CallBgm bgm, String artist) {
    final hasPhoto = bgm.artistPhotoOf(artist) != null;
    if (!hasPhoto) {
      return IconButton(
        key: ValueKey('artist-photo-$artist'),
        tooltip: strings.callBgmArtistPhotoSet,
        icon: const Icon(Icons.add_a_photo_outlined),
        onPressed: () => bgm.pickArtistPhoto(artist),
      );
    }
    return PopupMenuButton<bool>(
      key: ValueKey('artist-photo-$artist'),
      tooltip: strings.callBgmArtistPhotoSet,
      icon: const Icon(Icons.add_a_photo_outlined),
      onSelected: (change) {
        if (change) {
          bgm.pickArtistPhoto(artist);
        } else {
          bgm.setArtistPhoto(artist, null);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: true,
          child: Text(strings.callBgmArtistPhotoChange),
        ),
        PopupMenuItem(
          value: false,
          child: Text(strings.callBgmArtistPhotoRemove),
        ),
      ],
    );
  }

  /// アーティストを開いた中身。曲ではなく、そのアーティストの曲が入っているアルバムを並べ、
  /// アルバムを押すとその曲が開く。
  List<Widget> _artistAlbumRows(
    Strings strings,
    CallBgm bgm,
    String? artist,
    List<BgmTrack> tracks,
  ) {
    final byAlbum = <String?, List<BgmTrack>>{};
    for (final t in tracks) {
      (byAlbum[t.albumId] ??= []).add(t);
    }
    final ids = [
      for (final a in bgm.albums)
        if (byAlbum.containsKey(a.id)) a.id,
      if (byAlbum.containsKey(null)) null,
    ];
    final widgets = <Widget>[];
    for (final id in ids) {
      final list = byAlbum[id]!;
      final key = '${artist ?? ''}\u0000${id ?? ''}';
      final open = _openArtistAlbums.contains(key);
      final name = id == null
          ? strings.callBgmNoAlbum
          : bgm.albums.firstWhere((a) => a.id == id).name;
      final cover = list.where((t) => t.hasCover).firstOrNull ?? list.first;
      widgets.add(
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 16),
          leading: BgmCoverImage(bgm: bgm, track: cover, size: 40),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(strings.callBgmTrackCount(list.length)),
          trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() {
            if (!_openArtistAlbums.remove(key)) _openArtistAlbums.add(key);
          }),
        ),
      );
      if (open) {
        for (final t in list) {
          // そのアルバムの全曲が再生の範囲（アルバムなしの行は、アルバムに入っていない曲）。
          widgets.add(_trackRow(strings, bgm, t, id ?? kBgmUnclassifiedScope));
        }
      }
    }
    return widgets;
  }

  Widget _trackRow(
    Strings strings,
    CallBgm bgm,
    BgmTrack track,
    String? albumId, {
    int? number,
    bool favorites = false,
  }) {
    final playing = bgm.current?.id == track.id;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TrackTile(
          bgm: bgm,
          track: track,
          playing: playing,
          strings: strings,
          number: number,
          selected: _selected.contains(track.id),
          onSelect: () => _toggleSelect(track.id),
          onPlay: () => bgm.play(
            track,
            albumId: albumId,
            inAlbum: true,
            favorites: favorites,
          ),
          onStop: bgm.stop,
          onRemove: () => bgm.removeTrack(track),
        ),
      ],
    );
  }
}

/// ジャケットの帯の1枚（ジャケット・名前・曲数）。選んでいるものは枠で示す。
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.bgm,
    required this.label,
    required this.count,
    required this.coverTrack,
    required this.fallbackIcon,
    required this.selected,
    required this.strings,
    required this.onTap,
  });

  final CallBgm bgm;
  final String label;
  final int count;
  final BgmTrack? coverTrack;
  final IconData fallbackIcon;
  final bool selected;
  final Strings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = coverTrack;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 80,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: cover != null && cover.hasCover
                    ? BgmCoverImage(bgm: bgm, track: cover, size: 72)
                    : Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          fallbackIcon,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                strings.callBgmTrackCount(count),
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.bgm,
    required this.track,
    this.number,
    required this.selected,
    required this.onSelect,
    required this.playing,
    required this.strings,
    required this.onPlay,
    required this.onStop,
    required this.onRemove,
  });

  final CallBgm bgm;
  final BgmTrack track;

  /// アルバムの中での番号（アルバムを開いている時だけ。ディスクのあるアルバムはディスクごとの番号）。
  final int? number;

  /// 複数選択のチェック。
  final bool selected;
  final VoidCallback onSelect;
  final bool playing;
  final Strings strings;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: track.artist == null
          ? null
          : Text(track.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 左端のチェックボックス（複数選択）。
          AppCheckbox(value: selected, onChanged: (_) => onSelect()),
          const SizedBox(width: 8),
          if (number != null)
            SizedBox(
              width: 24,
              child: Text(
                '$number',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (number != null) const SizedBox(width: 8),
          InkWell(
            onTap: playing ? onStop : onPlay,
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              alignment: Alignment.center,
              children: [
                BgmCoverImage(bgm: bgm, track: track, size: 40),
                Icon(
                  playing ? Icons.stop_circle : Icons.play_circle_fill,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 22,
                ),
              ],
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.durationMs != null)
            Text(
              formatBgmDuration(Duration(milliseconds: track.durationMs!)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          BgmFavoriteButton(bgm: bgm, track: track, strings: strings),
          IconButton(
            tooltip: strings.callBgmRemove,
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
