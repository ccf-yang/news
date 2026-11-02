import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../state/app_state.dart';
import 'common.dart';
import '../pages/source_picker_page.dart';

/// 设计稿 07：底部弹出的来源切换浮层。
Future<void> showSourceSheet(BuildContext context) async {
  final app = AppState.instance;
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      return _SourceSheet(
        app: app,
        onAllSources: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => const SourcePickerPage(),
            ),
          );
        },
      );
    },
  );
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.app, required this.onAllSources});

  final AppState app;
  final VoidCallback onAllSources;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.66),
      decoration: BoxDecoration(
        color: p.brightness == Brightness.dark
            ? const Color(0xFF101015)
            : p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: p.line)),
        boxShadow: const [
          BoxShadow(color: Color(0xB3000000), blurRadius: 60, offset: Offset(0, -20)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final enabled = app.enabledSources;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.text3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        '切换来源',
                        style: TextStyle(
                          color: p.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${enabled.length} 个已启用',
                        style: TextStyle(color: p.text3, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '点选立即切换，左右滑动查看更多',
                      style: TextStyle(color: p.text3, fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: enabled.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 26),
                            child: Text(
                              '还没有启用的来源，先去「全部来源」里打开几个。',
                              style: TextStyle(color: p.text2, fontSize: 13),
                            ),
                          )
                        : SizedBox(
                            height: 190,
                            child: GridView.builder(
                              scrollDirection: Axis.horizontal,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: enabled.length,
                              itemBuilder: (context, index) {
                                final source = enabled[index];
                                final selected = app.currentSourceId == source.id;
                                return _SheetSourceItem(
                                  name: source.name,
                                  selected: selected,
                                  onTap: () {
                                    app.selectSource(source.id);
                                    Navigator.of(context).pop();
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: GhostButton(
                          label: '全部来源',
                          icon: CupertinoIcons.square_grid_2x2,
                          onTap: onAllSources,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryGradientButton(
                          label: '完成',
                          icon: CupertinoIcons.checkmark_alt,
                          height: 44,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
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

class _SheetSourceItem extends StatelessWidget {
  const _SheetSourceItem({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TapScale(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? p.accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: SourceLogo(name: name, size: 46, radius: 15),
          ),
          const SizedBox(height: 7),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? p.accent2 : p.text2,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 从来源里挑一个品牌色点，给详情页来源条用。
Color sourceDotColor(String name) => sourceColor(name);
