import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class SourcePickerPage extends StatefulWidget {
  const SourcePickerPage({super.key});

  @override
  State<SourcePickerPage> createState() => _SourcePickerPageState();
}

class _SourcePickerPageState extends State<SourcePickerPage> {
  final AppState app = AppState.instance;
  final TextEditingController _search = TextEditingController();
  int _segment = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<NewsSource> _filtered() {
    List<NewsSource> base;
    switch (_segment) {
      case 1:
        base = app.enabledSources;
        break;
      case 2:
        base = app.recentSources();
        break;
      default:
        base = List<NewsSource>.from(app.sources);
    }
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return base;
    return base
        .where((s) =>
            s.name.toLowerCase().contains(query) ||
            s.type.toLowerCase().contains(query) ||
            s.category.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) {
              final recentCount = app.recentSources().length;
              final list = _filtered();
              final grouped = <String, List<NewsSource>>{};
              for (final source in list) {
                grouped.putIfAbsent(source.category, () => []).add(source);
              }
              final categories = <String>[
                ...app.categories.where(grouped.containsKey),
                ...grouped.keys.where((c) => !app.categories.contains(c)),
              ];
              final rows = <Widget>[];
              for (final category in categories) {
                final items = grouped[category] ?? const [];
                if (items.isEmpty) continue;
                rows.add(_GroupLabel(name: category, count: items.length));
                for (final source in items) {
                  rows.add(
                    _SourceRow(
                      source: source,
                      selected: source.id == app.currentSourceId,
                      articleCount: app.feedFor(source.id)?.items.length,
                      onTap: () => _select(source),
                      onToggle: (value) => app.setSourceEnabled(source.id, value),
                    ),
                  );
                }
              }

              return Column(
                children: [
                  PulseNavBar(
                    title: '选择来源',
                    onBack: () => Navigator.of(context).pop(),
                    trailing: IconCircleButton(
                      icon: CupertinoIcons.xmark,
                      onTap: () => Navigator.of(context).pop(),
                      background: Colors.transparent,
                      border: false,
                    ),
                  ),
                  _SearchField(
                    controller: _search,
                    hint: '搜索 ${app.sources.length} 个来源',
                    onChanged: (_) => setState(() {}),
                  ),
                  _SegmentBar(
                    values: [
                      '全部 ${app.sources.length}',
                      '已启用 ${app.enabledCount}',
                      '最近 $recentCount',
                    ],
                    index: _segment,
                    onChanged: (index) => setState(() => _segment = index),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? EmptyState(
                            icon: CupertinoIcons.search,
                            title: '没有匹配的来源',
                            subtitle: _segment == 2
                                ? '最近使用的来源会出现在这里，先去热榜切换几个吧。'
                                : '换个关键词，或在「全部」里找找。',
                          )
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(top: 4, bottom: 26),
                            itemCount: rows.length + 1,
                            itemBuilder: (context, index) {
                              if (index == rows.length) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(22, 14, 22, 0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        CupertinoIcons.info_circle,
                                        size: 13,
                                        color: p.text3,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '启用状态决定是否参与 30 分钟自动刷新；点整行会切换并启用该来源。',
                                          style: TextStyle(
                                            color: p.text3,
                                            fontSize: 11,
                                            height: 1.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return rows[index];
                            },
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

  void _select(NewsSource source) {
    if (!source.enabled) app.setSourceEnabled(source.id, true);
    app.selectSource(source.id);
    Navigator.of(context).pop();
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.search, size: 15, color: p.text3),
            const SizedBox(width: 8),
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
                  hintText: hint,
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
                child: Icon(CupertinoIcons.clear_circled_solid, size: 16, color: p.text3),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.values,
    required this.index,
    required this.onChanged,
  });

  final List<String> values;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: TapScale(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? p.surface3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == index
                        ? const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    values[i],
                    style: TextStyle(
                      color: i == index ? p.text : p.text3,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
      child: Text(
        '$name · $count',
        style: TextStyle(
          color: p.text3,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
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
    required this.onToggle,
  });

  final NewsSource source;
  final bool selected;
  final int? articleCount;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final subtitle = <String>[
      if (source.type.isNotEmpty) source.type,
      if (articleCount != null) '$articleCount 条' else '未加载',
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [
                  p.accent.withValues(alpha: 0.09),
                  p.accent.withValues(alpha: 0),
                ],
                stops: const [0, 0.72],
              )
            : null,
        border: Border(bottom: BorderSide(color: p.line, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TapScale(
              onTap: onTap,
              scale: 0.995,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SourceLogo(name: source.name, size: 34, radius: 10),
                        if (selected)
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: p.accent,
                                shape: BoxShape.circle,
                                border: Border.all(color: p.bg, width: 2),
                              ),
                              child: const Icon(
                                CupertinoIcons.checkmark_alt,
                                size: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? p.accent2 : p.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.text3, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: PulseSwitch(
              value: source.enabled,
              width: 40,
              height: 24,
              onChanged: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}
