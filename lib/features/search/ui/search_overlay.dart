import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/features/search/ui/search_bar_widget.dart';
import 'package:bilimusic/features/search/ui/search_overlay_panel.dart';
import 'package:bilimusic/features/search/ui/search_rank_page.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';

/// 搜索Overlay - 默认展示音乐热歌榜，顶部是一条「可点不可编辑」的搜索栏。
///
/// 点搜索栏会弹出悬浮搜索层（真输入框 + 搜索历史），搜索在那里发起；
/// 结果写进应用级 Provider，[SearchResultsOverlay] 只订阅状态。
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  bool _hasInitialQuery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialQuery();
    });
  }

  void _checkInitialQuery() {
    final searchState = ref.read(searchStateProvider);
    if (searchState.shouldSearch && searchState.query.isNotEmpty) {
      _searchController.text = searchState.query;
      _hasInitialQuery = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _submitSearch(searchState.query);
        ref.read(searchStateProvider.notifier).markSearched();
      });
    }
  }

  void _onSearchStateChanged(SearchState searchState) {
    if (searchState.shouldSearch && searchState.query.isNotEmpty) {
      if (_searchController.text != searchState.query) {
        _searchController.text = searchState.query;
      }
      _hasInitialQuery = true;
      _submitSearch(searchState.query).then((_) {
        ref.read(searchStateProvider.notifier).markSearched();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _submitSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    FocusScope.of(context).unfocus();
    // 搜索在这里发起，结果存进应用级 Provider；搜索结果页只订阅状态。
    // 这样从分P歌单 / UP 主页返回时页面重建不会重新搜索。
    ref.read(searchResultsProvider.notifier).search(trimmed);
    ShellPageManager.instance.push(
      ShellPage.searchResults,
      args: {'query': trimmed},
    );
  }

  /// 展示用的搜索栏：包一层 IgnorePointer 让它不自己聚焦，
  /// 点击交给外层 GestureDetector 去开悬浮搜索层。
  Widget _buildSearchBar(bool isDesktop) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showSearchOverlayPanel(context),
        child: IgnorePointer(
          child: SearchBarWidget(
            controller: _searchController,
            onSearch: (_) {},
            // 不自动聚焦：进搜索 Tab 不应该直接弹输入法
            autoFocus: false,
            hintText: '搜索音乐、视频、用户...',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SearchState>(searchStateProvider, (prev, next) {
      // 初次跳过
      if (prev == null) return;
      _onSearchStateChanged(next);
    });

    final screenSize = ResponsiveHelper.getScreenSize(context);
    final isDesktop = screenSize == ScreenSize.desktop;
    final searchBar = _buildSearchBar(isDesktop);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _hasInitialQuery
            // 由应用内其它入口带入关键词时，交给结果页接管这一屏
            ? Column(
                children: [
                  const SizedBox(height: 16),
                  searchBar,
                  const Expanded(child: SizedBox()),
                ],
              )
            // 默认内容：热歌榜。搜索栏挂在滚动内容头部，往下浏览时会一起滑走
            : SearchRankPage(
                header: Column(
                  children: [const SizedBox(height: 16), searchBar],
                ),
              ),
      ),
    );
  }
}
