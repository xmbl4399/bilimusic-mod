import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/music_toplist.dart';
import 'package:bilimusic/domain/search_result.dart';

class SearchState {
  final String query;
  final bool shouldSearch;

  const SearchState({this.query = '', this.shouldSearch = false});

  SearchState copyWith({String? query, bool? shouldSearch}) {
    return SearchState(
      query: query ?? this.query,
      shouldSearch: shouldSearch ?? this.shouldSearch,
    );
  }
}

class SearchStateNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  void setQuery(String query) {
    // Always re-arm shouldSearch: even when the query is unchanged (e.g. the
    // user resubmits the same text after markSearched() flipped it to false),
    // this call must signal "run a search now" so the listener fires.
    state = SearchState(query: query, shouldSearch: query.isNotEmpty);
  }

  void clear() {
    if (state.query.isNotEmpty || state.shouldSearch) {
      state = const SearchState();
    }
  }

  void markSearched() {
    if (state.shouldSearch) {
      state = state.copyWith(shouldSearch: false);
    }
  }
}

final searchStateProvider = NotifierProvider<SearchStateNotifier, SearchState>(
  SearchStateNotifier.new,
);

/// 搜索页默认内容：B 站音乐「热歌榜」最新一期（`v/popular/music` 那个榜）。
///
/// 故意不加 autoDispose：切标签页会重建搜索页（AnimatedSwitcher），
/// 缓存一份榜单避免每次进页面都重新拉一遍。下拉刷新 / 头部刷新按钮
/// 用 `ref.invalidate(musicHotToplistProvider)` 触发重拉。
/// 热歌榜的全部期数（切换期数用）。同样缓存一份，切期不重复拉索引。
final musicToplistPeriodsProvider = FutureProvider<List<MusicToplistPeriod>>((
  ref,
) async {
  final api = ref.watch(apiServiceProvider);
  return api.fetchMusicToplistPeriods();
});

/// 搜索历史（最近在前，最多 [SearchHistoryNotifier.maxEntries] 条）。
///
/// 只存关键词，不存结果。写入走 SharedPreferences，重启后仍在。
class SearchHistoryNotifier extends Notifier<List<String>> {
  static const String prefsKey = 'search_history_v1';
  static const int maxEntries = 20;

  @override
  List<String> build() {
    // 先给空列表（同步返回），读到磁盘后再通知一次；搜索页首帧不会因为等 IO 卡住
    _loadFromDisk();
    return const [];
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(prefsKey);
      if (saved != null && saved.isNotEmpty && state.isEmpty) {
        state = saved;
      }
    } catch (_) {
      // 读不到就当作没有历史，不阻塞搜索
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey, state);
    } catch (_) {
      // 写盘失败不影响当前会话
    }
  }

  /// 记录一次搜索：已存在则提到最前，超出上限截断。
  Future<void> add(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    final next = [keyword, ...state.where((item) => item != keyword)];
    state = next.length > maxEntries ? next.sublist(0, maxEntries) : next;
    await _persist();
  }

  /// 长按删掉单条。
  Future<void> remove(String query) async {
    if (!state.contains(query)) return;
    state = state.where((item) => item != query).toList(growable: false);
    await _persist();
  }

  /// 清空全部。
  Future<void> clear() async {
    state = const [];
    await _persist();
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
      SearchHistoryNotifier.new,
    );

/// 当前选中的期数（`list_id`）。null = 最新一期。
///
/// Riverpod 3 没有 StateProvider 了，这里用最小的 Notifier 持有选中态。
class SelectedToplistIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int listId) => state = listId;

  void reset() => state = null;
}

final selectedToplistIdProvider =
    NotifierProvider<SelectedToplistIdNotifier, int?>(
      SelectedToplistIdNotifier.new,
    );

final musicHotToplistProvider = FutureProvider<MusicToplist>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final listId = ref.watch(selectedToplistIdProvider);
  return api.fetchMusicHotToplist(listId: listId);
});

/// 一次搜索的快照：结果列表 + 分P缓存 + 选中类型 + 滚动位置。
///
/// 存在的理由：搜索结果页是 `AnimatedSwitcher` 里的一帧，跳去歌单/详情再
/// 返回时整个 State 会被销毁重建（initState 再次触发 → 重新发请求、白屏
/// 转圈、滚动位置丢失）。把这些数据挂在一个比页面活得久的对象上，
/// 重建时直接命中快照渲染即可。
class SearchSnapshot {
  SearchSnapshot(this.query);

  final String query;

  /// 原始结果（不过滤）。`_pagesCache` 与页面共享同一个 Map 实例，
  /// 页面里的写入天然留在快照里。
  List<SearchResult> results = const [];
  List<SearchResultType> availableTypes = const [];
  final Map<String, List<Page>> pages = {};
  SearchResultType selectedType = SearchResultType.video;
  double scrollOffset = 0;

  bool get hasData => results.isNotEmpty;
}

/// 搜索结果快照仓库（按 query 建条目，LRU 淘汰，最多 [_maxEntries] 条）。
class SearchCache {
  SearchCache();

  static const int _maxEntries = 8;
  final Map<String, SearchSnapshot> _entries = {};

  SearchSnapshot of(String query) {
    final existing = _entries.remove(query);
    final snapshot = existing ?? SearchSnapshot(query);
    _entries[query] = snapshot; // 重新插入 → 最近使用排在最后
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return snapshot;
  }

  void clear(String query) => _entries.remove(query);
}

final searchCacheProvider = Provider<SearchCache>((ref) => SearchCache());
