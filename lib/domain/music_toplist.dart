import 'package:bilimusic/domain/music.dart';

/// 「热歌榜」的一期索引项（下拉切换期数用）。
///
/// 来自 `/x/copyright-music-publicity/toplist/all_period`，那份数据按年份分桶：
/// `data.list = {'2026': [{ID, priod, publish_time}, ...], '2025': [...]}`，
/// 其中 `priod` 是接口自己的拼写（不是 period）。
class MusicToplistPeriod {
  /// `list_id`，拉该期曲目时用。
  final int listId;

  /// 期号，如 227。
  final int period;

  /// 该期发布时间。
  final DateTime? publishedAt;

  const MusicToplistPeriod({
    required this.listId,
    required this.period,
    this.publishedAt,
  });

  /// `2026.10.16`
  String get dateLabel {
    final d = publishedAt;
    if (d == null) return '';
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}.$mm.$dd';
  }

  /// `第227期`
  String get periodLabel => period > 0 ? '第$period期' : '第$listId期';

  /// 切换器上显示的紧凑文案：`10月16日 第227期`。
  String get chipLabel {
    final d = publishedAt;
    if (d == null) return periodLabel;
    return '${d.month}月${d.day}日 $periodLabel';
  }
}

/// 音乐「热歌榜」一期（B 站版权音乐推广榜
/// `/x/copyright-music-publicity/toplist/*`）。
///
/// 榜单条目本身没有能播的音源：`can_listen` 基本都是 false，官方也没有音频流
/// 接口，网页上听的是每首歌挂的那支「二创投稿视频」。所以一条记录里存在两套
/// 语义：
///   - **歌**：歌名 / 歌手 / 专辑 / 热度 / 上期名次（榜单要显示的东西）；
///   - **[music]**：可播放的二创视频（bvid + first_cid），播放链路与搜索/首页
///     完全一致。
///
/// 列表默认只展示二创视频这一行（标题 - UP 主），歌名只在需要区分时用。
class MusicToplistSong {
  /// 名次（1 起，接口原值）。
  final int rank;

  /// 版权音乐 id（`MA...`），同一首歌跨期稳定，可做去重键。
  final String musicId;

  final String songTitle;
  final String singer;
  final String album;

  /// 热度值（接口原值，非播放量）。
  final int heat;

  /// 上期名次，0 表示新上榜。
  final int lastRank;

  /// 榜单角标，如 `['重回榜单', '最高排名1']`。
  final List<String> achievements;

  /// 可播放的二创视频。
  final Music music;

  const MusicToplistSong({
    required this.rank,
    required this.musicId,
    required this.songTitle,
    required this.singer,
    required this.album,
    required this.heat,
    required this.lastRank,
    required this.achievements,
    required this.music,
  });

  /// 名次相对上期的变化：>0 上升，<0 下降，null 表示新上榜/持平。
  int? get rankDelta {
    if (lastRank <= 0 || lastRank == rank) return null;
    return lastRank - rank;
  }

  /// 列表主行文案：`二创标题 - UP 主`。
  String get videoLine {
    final up = music.artist.displayName;
    final title = music.title.isEmpty ? songTitle : music.title;
    return up.isEmpty ? title : '$title - $up';
  }
}

/// 一期榜单：id + 期号 + 更新时间 + 曲目。
class MusicToplist {
  /// `list_id`（热歌榜为奇数编号，与 `all_period` 里的 `ID` 一致）。
  final int listId;

  /// 期号，如 227。
  final int period;

  /// 该期发布时间（接口给的是秒级时间戳）。
  final DateTime? publishedAt;

  final List<MusicToplistSong> songs;

  const MusicToplist({
    required this.listId,
    required this.period,
    this.publishedAt,
    required this.songs,
  });

  bool get isEmpty => songs.isEmpty;

  /// 头部副标题：`第227期 · 每周五 18:00 更新`。
  String get periodLabel {
    final date = publishedAt;
    final parts = <String>[
      if (period > 0) '第$period期',
      if (date != null) '${date.month}月${date.day}日',
      '每周五 18:00 更新',
    ];
    return parts.join(' · ');
  }

  /// 切换器上的紧凑文案：`10月16日 第227期`。
  String get chipLabel {
    final d = publishedAt;
    final label = period > 0 ? '第$period期' : '第$listId期';
    if (d == null) return label;
    return '${d.month}月${d.day}日 $label';
  }

  MusicToplistPeriod get periodInfo =>
      MusicToplistPeriod(listId: listId, period: period, publishedAt: publishedAt);
}
