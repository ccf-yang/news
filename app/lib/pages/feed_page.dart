import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/source_sheet.dart';
import 'reader_page.dart';
import 'source_picker_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final AppState app = AppState.instance;
  final Set<String> _attempted = {};

  @override
  void initState() {
    super.initState();
    app.addListener(_onAppChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFeed());
  }

  @override
  void dispose() {
    app.removeListener(_onAppChanged);
    super.dispose();
  }

  void _onAppChanged() {
    if (!mounted) return;
    _ensureFeed();
  }

  /// 切到一个还没有缓存的来源时自动拉一次（FR-2.2）。
  void _ensureFeed() {
    final source = app.currentSource;
    if (source == null) return;
    if (app.feedFor(source.id) != null) return;
    if (app.isRefreshing(source.id)) return;
    if (!_attempted.add(source.id)) return;
    app.refreshSource(source).then((result) {
      if (!result.ok && mounted) _showError(result.message ?? '刷新失败');
    });
  }

  Future<void> _refreshCurrent() async {
    final result = await app.refreshCurrent();
    if (!result.ok && mounted) _showError(result.message ?? '刷新失败');
  }

  void _showError(String message) {
    final p = context.palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: p.surface3,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulseBackground(
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final source = app.currentSource;
            final feed = source == null ? null : app.feedFor(source.id);
            final refreshing = source != null && app.isRefreshing(source.id);
            final error = source == null ? null : app.errorFor(source.id);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                if (source != null)
                  _SourceHeader(
                    source: source,
                    articleCount: feed?.items.length,
                    updatedAt: feed?.fetchedAt,
                    refreshing: refreshing,
                    onRefresh: _refreshCurrent,
                    onSwitch: () => showSourceSheet(context),
                  ),
                if (refreshing)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: p.line,
                        valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                      ),
                    ),
                  ),
                if (error != null && feed != null)
                  NoticeBar(
                    icon: CupertinoIcons.exclamationmark_circle,
                    text: '离线快照 · ${updatedLabel(feed.fetchedAt)} · $error',
                    actionLabel: '重试',
                    onAction: _refreshCurrent,
                  ),
                Expanded(
                  child: source == null
                      ? EmptyState(
                          icon: CupertinoIcons.square_grid_2x2,
                          title: '还没有来源',
                          subtitle: '先导入热点源配置，或启用一个内置来源。',
                          action: GhostButton(
                            label: '选择来源',
                            icon: CupertinoIcons.square_grid_2x2,
                            onTap: () => Navigator.of(context).push(
                              CupertinoPageRoute<void>(
                                builder: (_) => const SourcePickerPage(),
                              ),
                            ),
                          ),
                        )
                      : feed == null
                          ? (refreshing
                              ? const _FeedSkeleton()
                              : EmptyState(
                                  icon: CupertinoIcons.news,
                                  title: error == null ? '还没有榜单' : '暂时取不到榜单',
                                  subtitle: error ??
                                      '「${source.name}」还没有缓存，点下面的按钮加载 Top 50。',
                                  action: GhostButton(
                                    label: '加载热榜',
                                    icon: CupertinoIcons.arrow_clockwise,
                                    onTap: _refreshCurrent,
                                  ),
                                ))
                          : RefreshIndicator(
                              color: p.accent,
                              backgroundColor: p.surface2,
                              onRefresh: _refreshCurrent,
                              child: _FeedList(
                                feed: feed,
                                app: app,
                                onTap: (article) {
                                  app.markRead(article);
                                  Navigator.of(context).push(
                                    CupertinoPageRoute<void>(
                                      builder: (_) => ReaderPage(article: article),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 只留页面标题；刷新和更新时间都收到来源那一行，避免和来源行的信息重复。
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
      child: Text(
        '热榜',
        style: TextStyle(
          color: p.text,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
          height: 1.1,
        ),
      ),
    );
  }
}

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({
    required this.source,
    required this.articleCount,
    required this.updatedAt,
    required this.refreshing,
    required this.onRefresh,
    required this.onSwitch,
  });

  final NewsSource source;
  final int? articleCount;
  final DateTime? updatedAt;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final parts = <String>[
      if (source.type.isNotEmpty) source.type,
      if (articleCount != null) '$articleCount 条',
      if (updatedAt != null) updatedLabel(updatedAt),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(
        children: [
          TapScale(
            onTap: onSwitch,
            child: SourceLogo(name: source.name, size: 40, radius: 12),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: TapScale(
              onTap: onSwitch,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(CupertinoIcons.chevron_down, size: 12, color: p.text3),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    parts.isEmpty ? '暂无信息' : parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text3, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconCircleButton(
            icon: CupertinoIcons.arrow_clockwise,
            onTap: onRefresh,
            iconColor: refreshing ? p.accent : null,
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  const _FeedList({
    required this.feed,
    required this.app,
    required this.onTap,
  });

  final FeedSnapshot feed;
  final AppState app;
  final ValueChanged<Article> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: feed.items.length,
      itemBuilder: (context, index) {
        final article = feed.items[index];
        final read = app.isRead(article.id);
        final saved = app.isSaved(article.id);
        final titleHeight = feedTitleHeight(context);
        return TapScale(
          onTap: () => onTap(article),
          scale: 0.995,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: p.line, width: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: titleHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: article.rank <= 3
                        ? AccentGradientText(
                            '${article.rank}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          )
                        : Text(
                            '${article.rank}',
                            style: TextStyle(
                              color: p.text3,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: titleHeight,
                        child: Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: read ? p.text2 : p.text,
                            fontSize: 14.5,
                            height: 1.42,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.05,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          HeatPill(article.hotValue),
                          if (article.hotValue.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('·', style: TextStyle(color: p.text3, fontSize: 10)),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            relativeTime(feed.fetchedAt),
                            style: TextStyle(color: p.text3, fontSize: 11),
                          ),
                          if (read) ...[
                            const SizedBox(width: 8),
                            Text('已读', style: TextStyle(color: p.text3, fontSize: 11)),
                          ],
                          const Spacer(),
                          if (saved)
                            Icon(
                              CupertinoIcons.bookmark_fill,
                              size: 12,
                              color: p.accent,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 12,
                decoration: BoxDecoration(
                  color: p.surface3,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: p.surface3,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 180,
                      decoration: BoxDecoration(
                        color: p.surface3.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 9,
                      width: 110,
                      decoration: BoxDecoration(
                        color: p.surface3.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
