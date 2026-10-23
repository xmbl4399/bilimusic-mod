import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_bar_widget.dart';
import 'package:bilimusic/features/search/ui/search_overlay_panel.dart';
import 'package:bilimusic/features/search/ui/search_rank_page.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 「搜索」Tab 页：默认展示热歌榜，搜索这件事交给悬浮层。
///
/// 设计要点：本页的搜索框只是**外观**（点击即打开 [SearchOverlayPanel]），
/// 真正的输入框活在悬浮层里。这样：
///   - 点底部导航「搜索」不会弹输入法（本页没有可聚焦的输入框）；
///   - 悬浮层是独立路由，系统返回键一下就能关掉，回到热歌榜；
///   - 也不会再出现「输入框被搬来搬去 → 输入法闪退」的老问题。
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  /// 只用于把外部带进来的关键词显示在搜索框里（不参与输入）。
  final TextEditingController _searchController = TextEditingController();

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
    if (query.isEmpty) return;
    // 记一条搜索历史（重复的会被提到最前）
    unawaited(ref.read(searchHistoryProvider.notifier).add(query));
    FocusScope.of(context).unfocus();
    ShellPageManager.instance.push(
      ShellPage.searchResults,
      args: {'query': query},
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

    // 搜索栏做成「可滚动内容的头部」，由 SearchRankPage 塞进它自己的 sliver 里，
    // 这样往下浏览榜单时搜索框会跟着一起滑出屏幕（不是固定在顶部）。
    // 它只是一个长得像输入框的按钮：IgnorePointer 保证它永远拿不到焦点，
    // 点击交给外层 GestureDetector 去开悬浮搜索层。
    final searchHeader = Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 0 : 16,
        16,
        isDesktop ? 0 : 16,
        0,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showSearchOverlayPanel(context),
        child: IgnorePointer(
          child: SearchBarWidget(
            controller: _searchController,
            onSearch: (_) {},
            autoFocus: false,
            hintText: '搜索音乐、视频、用户...',
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(child: SearchRankPage(header: searchHeader)),
    );
  }
}
