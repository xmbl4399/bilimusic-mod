import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// 一次关键词搜索的完整结果。
///
/// 放在应用级 Provider 里而不是页面 State：搜索结果页被分P歌单、UP 主页等
/// 压栈时会整个销毁，返回时若重新初始化就会再发一次搜索请求。把结果留在这里，
/// 页面重建只是重新订阅同一份状态——数据、分P 缓存和选中的类型都原样还在。
class SearchResultsState {
  final String query;

  /// `/x/web-interface/search/all/v2` 一次返回的全部类型结果。
  final List<SearchResult> results;

  /// 本次结果里实际出现过的类型（保持接口返回顺序）。
  final List<SearchResultType> availableTypes;

  /// 当前展示的类型。
  final SearchResultType selectedType;

  final bool isLoading;
  final bool hasSearched;
  final String? errorMessage;

  /// bvid -> 分P。随搜索结果一起缓存，返回页面时不会重新拉取。
  final Map<String, List<Page>> pages;

  /// 正在拉取分P的 bvid。
  final Set<String> loadingPages;

  const SearchResultsState({
    this.query = '',
    this.results = const [],
    this.availableTypes = const [],
    this.selectedType = SearchResultType.video,
    this.isLoading = false,
    this.hasSearched = false,
    this.errorMessage,
    this.pages = const {},
    this.loadingPages = const {},
  });

  /// 当前类型下的结果。
  List<SearchResult> get filteredResults =>
      SearchResult.filterByType(results, selectedType);

  SearchResultsState copyWith({
    String? query,
    List<SearchResult>? results,
    List<SearchResultType>? availableTypes,
    SearchResultType? selectedType,
    bool? isLoading,
    bool? hasSearched,
    String? errorMessage,
    bool clearError = false,
    Map<String, List<Page>>? pages,
    Set<String>? loadingPages,
  }) {
    return SearchResultsState(
      query: query ?? this.query,
      results: results ?? this.results,
      availableTypes: availableTypes ?? this.availableTypes,
      selectedType: selectedType ?? this.selectedType,
      isLoading: isLoading ?? this.isLoading,
      hasSearched: hasSearched ?? this.hasSearched,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pages: pages ?? this.pages,
      loadingPages: loadingPages ?? this.loadingPages,
    );
  }
}

class SearchResultsNotifier extends Notifier<SearchResultsState> {
  /// 搜索请求代数：新搜索开始后，旧请求（含分P预取）的返回结果一律丢弃。
  int _generation = 0;

  @override
  SearchResultsState build() => const SearchResultsState();

  /// 用 [rawQuery] 重新搜索。入口只有搜索页（含横屏标题栏），搜索结果页本身
  /// 只消费本状态，因此压栈/返回不会触发网络请求。
  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    final generation = ++_generation;

    if (query.isEmpty) {
      state = const SearchResultsState();
      return;
    }

    state = SearchResultsState(query: query, isLoading: true);

    final SearchResponse response;
    try {
      response = await ref.read(apiServiceProvider).search(query);
    } catch (e) {
      if (!ref.mounted || generation != _generation) return;
      debugPrint('[SearchResults] search($query): $e');
      state = SearchResultsState(
        query: query,
        hasSearched: true,
        errorMessage: '搜索失败，请稍后重试',
      );
      return;
    }
    if (!ref.mounted || generation != _generation) return;

    final types = SearchResult.getAvailableTypes(response.results);
    state = SearchResultsState(
      query: query,
      results: response.results,
      availableTypes: types,
      selectedType: _defaultType(types),
      hasSearched: true,
      errorMessage: response.results.isEmpty ? '没有搜索到任何结果' : null,
    );

    if (response.results.isNotEmpty) {
      unawaited(_prefetchPages(response.results, generation));
    }
  }

  /// 切换当前展示的类型。类型不在本次结果集里时忽略。
  void selectType(SearchResultType type) {
    if (type == state.selectedType || !state.availableTypes.contains(type)) {
      return;
    }
    state = state.copyWith(selectedType: type);
  }

  /// 默认展示视频；本次没有视频时退回接口返回的第一个类型（例如只搜到 UP主）。
  static SearchResultType _defaultType(List<SearchResultType> types) {
    if (types.isEmpty) return SearchResultType.video;
    if (types.contains(SearchResultType.video)) return SearchResultType.video;
    return types.first;
  }

  /// 依次预取视频分P，用于把多P稿件拆成「系列视频」。
  ///
  /// 沿用原来的 50ms 间隔，避免一次打太多详情请求。代数变化时立即停手。
  Future<void> _prefetchPages(
    List<SearchResult> results,
    int generation,
  ) async {
    for (final result in results) {
      if (!ref.mounted || generation != _generation) return;
      if (result.type != SearchResultType.video || result.id.isEmpty) continue;
      if (state.pages.containsKey(result.id)) continue;
      if (state.loadingPages.contains(result.id)) continue;

      state = state.copyWith(loadingPages: {...state.loadingPages, result.id});

      try {
        final pages = await ref
            .read(apiServiceProvider)
            .getVideoPages(result.id);
        if (!ref.mounted || generation != _generation) return;
        state = state.copyWith(
          pages: {...state.pages, result.id: pages},
          loadingPages: {...state.loadingPages}..remove(result.id),
        );
      } catch (_) {
        if (!ref.mounted || generation != _generation) return;
        state = state.copyWith(
          loadingPages: {...state.loadingPages}..remove(result.id),
        );
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
}

final searchResultsProvider =
    NotifierProvider<SearchResultsNotifier, SearchResultsState>(
      SearchResultsNotifier.new,
    );

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
