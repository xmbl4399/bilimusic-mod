import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_bar_widget.dart';
import 'package:bilimusic/features/search/ui/search_history_panel.dart';

/// 打开「悬浮搜索层」：半透明遮罩 + 顶部一张悬浮卡片（真输入框 + 搜索历史）。
///
/// 回退方式（两种，都是直接关掉、回到下面的热歌榜）：
///   - 系统返回键 / 返回手势（Android 的输入法会先吃掉一次返回用于收键盘，
///     再按一次才关这一层，这是系统行为）；
///   - 点卡片外的遮罩空白处（一下即关，不等键盘）。
Future<void> showSearchOverlayPanel(
  BuildContext context, {
  String initialQuery = '',
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          SearchOverlayPanel(initialQuery: initialQuery),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// 悬浮搜索层本体。
class SearchOverlayPanel extends ConsumerStatefulWidget {
  const SearchOverlayPanel({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchOverlayPanel> createState() => _SearchOverlayPanelState();
}

class _SearchOverlayPanelState extends ConsumerState<SearchOverlayPanel> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  /// 提交搜索：关掉悬浮层 → 底层热歌榜立刻换成搜索结果页。
  Future<void> _submit(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    unawaited(ref.read(searchHistoryProvider.notifier).add(query));
    FocusScope.of(context).unfocus();
    ShellPageManager.instance.push(
      ShellPage.searchResults,
      args: {'query': query},
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    // 卡片最高到键盘上沿，历史多的时候内部自己滚
    final maxCardHeight =
        (MediaQuery.sizeOf(context).height - viewInsets.bottom - safeTop - 24)
            .clamp(200.0, 640.0);
    final history = ref.watch(searchHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // 键盘高度自己算：卡片整体留在键盘上方，遮罩铺满全屏
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 遮罩层：点空白处 = 关闭
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
              child: Container(color: Colors.black54),
            ),
          ),
          Positioned(
            top: safeTop + 10,
            left: 12,
            right: 12,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxCardHeight),
              child: Material(
                color: theme.scaffoldBackgroundColor,
                elevation: 12,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SearchBarWidget(
                        controller: _controller,
                        focusNode: _focusNode,
                        onSearch: _submit,
                        // 悬浮层一出来就是「在输入」的状态
                        autoFocus: true,
                        hintText: '搜索音乐、视频、用户...',
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: history.isEmpty
                            ? _buildEmptyHint(theme)
                            : SearchHistoryPanel(onPick: _submit),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHint(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '输入关键词开始搜索',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
