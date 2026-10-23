import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/music_toplist.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 搜索页的默认内容：B 站音乐「热歌榜」（每期 20 行）。
///
/// 数据是 `v/popular/music` 那个周榜：榜上每首歌本身不可播（没有音频流），
/// 网页上听的是挂在每首歌下的「二创投稿视频」。所以这一屏**只展示关联视频**
/// ——标题 + UP 主。
///
/// 交互对齐网页版：
///   - 右上角「10月16日 第227期 ⌄」→ 弹期数列表切其它期；
///   - 点任意一行 → 整期 20 首进播放列表，并从点的那首开始播；
///   - 下拉刷新保留（RefreshIndicator 重拉当前期）。
class SearchRankPage extends ConsumerWidget {
  /// 页面头部（搜索栏）。作为滚动内容的第一个 item 一起滚动，
  /// 所以往下浏览时它会被滑出屏幕，而不是固定在顶部。
  final Widget? header;

  const SearchRankPage({super.key, this.header});

  /// 点某一行：整期入队 + 从这首开始播。
  ///
  /// 入队是「追加 + 去重」（不清空当前队列、不打断正在播的歌），重复点同一期
  /// 只会补进缺的那几首，所以队列顺序是「原有的 + 这一期」。
  Future<void> _playFromToplist(
    BuildContext context,
    WidgetRef ref,
    List<Music> songs,
    int index,
  ) async {
    if (songs.isEmpty) return;
    final target = songs[index.clamp(0, songs.length - 1)];

    final service = ref.read(playlistServiceProvider);
    final before = service.playlistLength;

    // 两个 notifier 在第一个 await 之前取出，页面中途被 pop 也不会用到已释放的 ref
    final playlist = ref.read(playlistCommandsProvider.notifier);
    final playback = ref.read(playbackCommandsProvider.notifier);

    // 先整期入队，playMusic 再按 (bvid, cid) 命中选择这一首
    await playlist.addAllToPlaylist(songs);
    await playback.playMusic(target);

    if (!context.mounted) return;
    final added = service.playlistLength - before;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            added > 0
                ? '已把这一期 ${songs.length} 首放入播放列表'
                : '这一期 ${songs.length} 首已在播放列表里',
          ),
          duration: const Duration(milliseconds: 1500),
        ),
      );
  }

  /// 右上角期数切换：拉全量期数索引 → 底部弹层选一期。
  Future<void> _showPeriodPicker(BuildContext context, WidgetRef ref) async {
    final periods = await ref.read(musicToplistPeriodsProvider.future);
    if (!context.mounted || periods.isEmpty) return;

    final currentId =
        ref.read(selectedToplistIdProvider) ?? periods.first.listId;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) =>
          _PeriodSheet(periods: periods, currentListId: currentId),
    );

    if (picked == null || picked == currentId) return;
    ref.read(selectedToplistIdProvider.notifier).select(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toplist = ref.watch(musicHotToplistProvider);
    final screenSize = ResponsiveHelper.getScreenSize(context);
    final isWide =
        screenSize == ScreenSize.desktop || screenSize == ScreenSize.tablet;

    // 头部（搜索栏）作为第一个 sliver 一起滚动：不做 pinned、不做 floating，
    // 往下浏览时它就跟着滑走。
    Widget buildScroll({required List<Widget> slivers}) {
      return RefreshIndicator(
        // 下拉刷新：重拉「当前选中期数」，不清空已选期
        onRefresh: () async => ref.refresh(musicHotToplistProvider.future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (header != null) SliverToBoxAdapter(child: header),
            ...slivers,
          ],
        ),
      );
    }

    return toplist.when(
      loading: () => buildScroll(
        slivers: const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        ],
      ),
      error: (error, stack) => buildScroll(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _RankError(
              onRetry: () => ref.invalidate(musicHotToplistProvider),
            ),
          ),
        ],
      ),
      data: (data) {
        if (data.isEmpty) {
          return buildScroll(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: _RankError(
                  onRetry: () => ref.invalidate(musicHotToplistProvider),
                ),
              ),
            ],
          );
        }
        final songs = data.songs
            .map((song) => song.music)
            .toList(growable: false);
        return buildScroll(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                isWide ? 24 : 12,
                0,
                isWide ? 24 : 12,
                120,
              ),
              sliver: SliverList.builder(
                itemCount: data.songs.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _RankHeader(
                      chipLabel: data.chipLabel,
                      onSwitchPeriod: () => _showPeriodPicker(context, ref),
                    );
                  }
                  final song = data.songs[index - 1];
                  return _RankTile(
                    rank: song.rank > 0 ? song.rank : index,
                    rankDelta: song.rankDelta,
                    music: song.music,
                    songTitle: song.songTitle,
                    onTap: () =>
                        _playFromToplist(context, ref, songs, index - 1),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RankHeader extends StatelessWidget {
  /// `10月16日 第227期`（当前选中期数）。
  final String chipLabel;
  final VoidCallback onSwitchPeriod;

  const _RankHeader({required this.chipLabel, required this.onSwitchPeriod});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.leaderboard_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '音乐热歌榜',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // 期数切换器（对齐网页版「10月16日 第227期 ⌄」）
              _PeriodChip(label: chipLabel, onTap: onSwitchPeriod),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              '每周五 18:00 更新 · 点任意一首即整期入队播放',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}

/// 头部右侧的期数切换按钮：`10月16日 第227期 ⌄`
class _PeriodChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PeriodChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 期数选择弹层：`第227期  2026.10.16`，当前期高亮并自动滚到可视区。
class _PeriodSheet extends StatefulWidget {
  final List<MusicToplistPeriod> periods;
  final int currentListId;

  const _PeriodSheet({required this.periods, required this.currentListId});

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  static const double _itemExtent = 52;

  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final index = widget.periods.indexWhere(
      (p) => p.listId == widget.currentListId,
    );
    _controller = ScrollController(
      initialScrollOffset: index <= 0 ? 0 : (index - 1) * _itemExtent,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '切换期数',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.4)),
          Expanded(
            child: ListView.builder(
              controller: _controller,
              itemExtent: _itemExtent,
              itemCount: widget.periods.length,
              itemBuilder: (context, index) {
                final period = widget.periods[index];
                final selected = period.listId == widget.currentListId;
                return InkWell(
                  onTap: () => Navigator.of(context).pop(period.listId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            period.periodLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: selected
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                        Text(
                          period.dateLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? theme.colorScheme.primary
                                : Colors.grey[600],
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  final int rank;

  /// 相对上期的名次变化：>0 上升，<0 下降，null 新上榜/持平。
  final int? rankDelta;
  final Music music;

  /// 歌名：只在这行视频标题为空时兜底，正常不展示。
  final String songTitle;
  final VoidCallback onTap;

  const _RankTile({
    required this.rank,
    required this.rankDelta,
    required this.music,
    required this.songTitle,
    required this.onTap,
  });

  static const double _coverSize = 48;
  static const double _rankWidth = 26;

  Color _rankColor(BuildContext context) {
    if (rank == 1) return const Color(0xFFE53935);
    if (rank == 2) return const Color(0xFFFB8C00);
    if (rank == 3) return const Color(0xFFFDD835);
    final theme = Theme.of(context);
    return theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upName = music.artist.displayName;
    final duration = music.duration;
    final subtitleParts = <String>[
      if (upName.isNotEmpty) upName,
      if (duration != null) _formatDuration(duration),
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            // 名次 + 涨跌
            SizedBox(
              width: _rankWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: rank <= 3 ? 16 : 14,
                      fontWeight: rank <= 3 ? FontWeight.w800 : FontWeight.w600,
                      color: _rankColor(context),
                    ),
                  ),
                  if (rankDelta != null)
                    Text(
                      rankDelta! > 0 ? '↑${rankDelta!}' : '↓${-rankDelta!}',
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: rankDelta! > 0
                            ? const Color(0xFFE53935)
                            : const Color(0xFF43A047),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // 封面（二创视频封面）
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: _coverSize,
                height: _coverSize,
                child: Image.network(
                  music.safeCoverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note,
                      size: 20,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 标题（二创视频标题）+ 副标题（UP 主 · 时长）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    music.title.isNotEmpty
                        ? music.title
                        : (songTitle.isNotEmpty ? songTitle : '未知标题'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitleParts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitleParts.join(' - '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.play_circle_outline,
              size: 22,
              color: theme.colorScheme.primary.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _RankError extends StatelessWidget {
  final VoidCallback onRetry;

  const _RankError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            '榜单加载失败',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
