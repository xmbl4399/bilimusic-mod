import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/search/search_providers.dart';

/// 搜索框获得焦点时，铺在它下方的「搜索历史」胶囊面板。
///
/// 交互：
///   - 点胶囊 → 直接用这个词搜索；
///   - 长按胶囊 → 删掉这一条；
///   - 右上角「清空」→ 清空全部历史。
class SearchHistoryPanel extends ConsumerWidget {
  final Future<void> Function(String query) onPick;

  const SearchHistoryPanel({super.key, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '搜索历史',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 右上角：清空全部历史
              TextButton.icon(
                onPressed: history.isEmpty
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('清空搜索历史？'),
                            content: Text('将删除全部 ${history.length} 条历史记录。'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await ref
                              .read(searchHistoryProvider.notifier)
                              .clear();
                        }
                      },
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final query in history)
                _HistoryChip(
                  label: query,
                  onTap: () => onPick(query),
                  onLongPress: () =>
                      ref.read(searchHistoryProvider.notifier).remove(query),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一颗历史胶囊：点一下搜索，长按删除。
class _HistoryChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _HistoryChip({
    required this.label,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.9,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}
