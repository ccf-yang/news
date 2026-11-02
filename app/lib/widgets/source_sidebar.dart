import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'common.dart';

/// 热榜页左右滑出的来源侧栏。
///
/// 默认列全部来源，方便直接切到任意站点；顶部的范围按钮可切回「已启用」。
class SourceSidebar extends StatefulWidget {
  const SourceSidebar({super.key, required this.onManage});

  final VoidCallback onManage;

  @override
  State<SourceSidebar> createState() => _SourceSidebarState();
}

class _SourceSidebarState extends State<SourceSidebar> {
  final AppState app = AppState.instance;
  final TextEditingController _search = TextEditingController();
  bool _showAll = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<NewsSource> _filtered() {
    final base = _showAll ? app.sources : app.enabledSources;
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return base;
    return base
        .where((s) =>
            s.name.toLowerCase().contains(query) ||
            s.type.toLowerCase().contains(query) ||
            s.category.toLowerCase().contains(query))
        .toList();
  }

  void _select(NewsSource source) {
    // 从「全部」里点一个没启用的站点，顺手启用它，否则热榜刷新不到内容。
    if (!source.enabled) app.setSourceEnabled(source.id, true);
    app.selectSource(source.id);
    if (app.feedFor(source.id) == null) {
      app.refreshSource(source);
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickScope() async {
    final p = context.palette;
    final picked = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(
          '显示范围',
          style: TextStyle(color: p.text, fontSize: 14),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(false),
            child: Text(
              '已启用（${app.enabledCount}）',
              style: TextStyle(
                color: !_showAll ? p.accent : p.text,
                fontWeight: !_showAll ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(true),
            child: Text(
              '全部来源（${app.sources.length}）',
              style: TextStyle(
                color: _showAll ? p.accent : p.text,
                fontWeight: _showAll ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _showAll = picked);
  }

  void _manage() {
    Navigator.of(context).pop();
    widget.onManage();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      // 透明，让 Drawer 自己的圆角与底色透出来。
      color: Colors.transparent,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final list = _filtered();
            final grouped = <String, List<NewsSource>>{};
            for (final source in list) {
              grouped.putIfAbsent(source.category, () => []).add(source);
            }
            final categories = <String>[
              ...app.categories.where(grouped.containsKey),
              ...grouped.keys.where((c) => !app.categories.contains(c)),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '切换网站',
                              style: TextStyle(
                                color: p.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 5),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _pickScope,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _showAll
                                        ? '全部 ${app.sources.length} 个来源'
                                        : '已启用 ${app.enabledCount} 个来源',
                                    style: TextStyle(
                                      color: p.accent2,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    CupertinoIcons.chevron_down,
                                    size: 10,
                                    color: p.accent2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconCircleButton(
                        icon: CupertinoIcons.xmark,
                        onTap: () => Navigator.of(context).pop(),
                        background: Colors.transparent,
                        border: false,
                      ),
                    ],
                  ),
                ),
                _SearchField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                ),
                Expanded(
                  child: list.isEmpty
                      ? EmptyState(
                          icon: CupertinoIcons.search,
                          title: '没有匹配的来源',
                          subtitle: _showAll
                              ? '换个关键词，或检查搜索范围。'
                              : '换个关键词，或把上方范围切到「全部来源」。',
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4, bottom: 12),
                          itemCount: _rowCount(grouped, categories),
                          itemBuilder: (context, index) {
                            return _buildRow(grouped, categories, index);
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: TapScale(
                    onTap: _manage,
                    scale: 0.99,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: p.line),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.square_grid_2x2,
                              size: 16, color: p.text3),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '管理全部 ${app.sources.length} 个来源',
                              style: TextStyle(
                                color: p.text2,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(CupertinoIcons.chevron_forward,
                              size: 14, color: p.text3),
                        ],
                      ),
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

  int _rowCount(
    Map<String, List<NewsSource>> grouped,
    List<String> categories,
  ) {
    var count = 0;
    for (final category in categories) {
      final items = grouped[category] ?? const [];
      if (items.isEmpty) continue;
      count += 1 + items.length;
    }
    return count;
  }

  Widget _buildRow(
    Map<String, List<NewsSource>> grouped,
    List<String> categories,
    int index,
  ) {
    var cursor = 0;
    for (final category in categories) {
      final items = grouped[category] ?? const [];
      if (items.isEmpty) continue;
      if (index == cursor) return _GroupLabel(name: category, count: items.length);
      cursor += 1;
      for (final source in items) {
        if (index == cursor) {
          return _SourceRow(
            source: source,
            selected: source.id == app.currentSourceId,
            articleCount: app.feedFor(source.id)?.items.length,
            onTap: () => _select(source),
          );
        }
        cursor += 1;
      }
    }
    return const SizedBox.shrink();
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.search, size: 14, color: p.text3),
            const SizedBox(width: 7),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                cursorColor: p.accent,
                textInputAction: TextInputAction.search,
                style: TextStyle(color: p.text, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '搜索来源',
                  hintStyle: TextStyle(color: p.text3, fontSize: 13),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              TapScale(
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                child: Icon(CupertinoIcons.clear_circled_solid,
                    size: 15, color: p.text3),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.name, required this.count});

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 5),
      child: Text(
        '$name · $count',
        style: TextStyle(
          color: p.text3,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.selected,
    required this.articleCount,
    required this.onTap,
  });

  final NewsSource source;
  final bool selected;
  final int? articleCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final subtitle = <String>[
      if (!source.enabled) '未启用',
      if (source.type.isNotEmpty) source.type,
      if (articleCount != null) '$articleCount 条' else '未加载',
    ].join(' · ');

    return TapScale(
      onTap: onTap,
      scale: 0.995,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 9, 16, 9),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: 0.08) : null,
          border: Border(bottom: BorderSide(color: p.line, width: 0.5)),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: source.enabled ? 1 : 0.5,
              child: SourceLogo(
                name: source.name,
                size: 34,
                radius: 10,
                showGlow: false,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? p.accent2
                          : (source.enabled ? p.text : p.text3),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text3, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.checkmark_alt, size: 17, color: p.accent),
          ],
        ),
      ),
    );
  }
}
