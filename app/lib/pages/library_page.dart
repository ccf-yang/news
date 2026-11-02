import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'reader_page.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final p = context.palette;
    return PulseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) {
              final entries = app.savedEntries;
              return Column(
                children: [
                  PulseNavBar(
                    title: '我的收藏',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 30),
                      children: [
                        _Stats(
                          saved: entries.length,
                          read: app.readIds.length,
                          sources: app.savedSourceCount,
                        ),
                        SectionLabel(
                          '收藏夹',
                          trailing: Text(
                            '按收藏时间排序',
                            style: TextStyle(color: p.text3, fontSize: 11.5),
                          ),
                          padding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
                        ),
                        if (entries.isEmpty)
                          EmptyState(
                            icon: CupertinoIcons.bookmark,
                            title: '还没有收藏',
                            subtitle: '在文章详情页点「收藏」，文章会按时间出现在这里，并实时同步计数。',
                            action: GhostButton(
                              label: '返回继续阅读',
                              icon: CupertinoIcons.chevron_back,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          )
                        else
                          for (final entry in entries)
                            _SavedRow(
                              entry: entry,
                              onTap: () => Navigator.of(context).push(
                                CupertinoPageRoute<void>(
                                  builder: (_) => ReaderPage(article: entry.article),
                                ),
                              ),
                              onRemove: () => _confirmRemove(context, app, entry),
                            ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    AppState app,
    SavedEntry entry,
  ) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('取消收藏？'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            entry.article.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('保留'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('取消收藏'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await app.removeSaved(entry.article.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已取消收藏'),
            backgroundColor: context.palette.surface3,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.saved, required this.read, required this.sources});

  final int saved;
  final int read;
  final int sources;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        children: [
          Expanded(child: _StatTile(value: '$saved', label: '已收藏')),
          const SizedBox(width: 10),
          Expanded(child: _StatTile(value: '$read', label: '已读文章')),
          const SizedBox(width: 10),
          Expanded(child: _StatTile(value: '$sources', label: '收藏来源')),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: p.text,
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: p.text3, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });

  final SavedEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final article = entry.article;
    return Dismissible(
      key: ValueKey(article.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onRemove();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 26),
        color: const Color(0xFFE5484D).withValues(alpha: 0.16),
        child: const Icon(CupertinoIcons.trash, color: Color(0xFFE5484D), size: 20),
      ),
      child: TapScale(
        onTap: onTap,
        scale: 0.995,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.line, width: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SourceLogo(name: article.sourceName, size: 44, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 15,
                          height: 15,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sourceColor(article.sourceName),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            sourceBadge(article.sourceName),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${article.sourceName} · 收藏于 ${savedTimeLabel(entry.savedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.text3, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.bookmark_fill, size: 13, color: p.accent),
            ],
          ),
        ),
      ),
    );
  }
}
