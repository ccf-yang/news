import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'import_page.dart';
import 'library_page.dart';
import 'source_picker_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AppState app = AppState.instance;
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/pulse-export-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(app.buildExportJson());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Pulse 数据导出',
      );
    } catch (e) {
      _snack('导出失败：$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    final p = context.palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: p.surface3,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message, style: const TextStyle(fontSize: 13, height: 1.5)),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showRefreshInfo() {
    final p = context.palette;
    final content = [
      '上次自动刷新：${app.lastRefreshAt == null ? '尚未执行' : savedTimeLabel(app.lastRefreshAt!)}',
      '成功来源：${app.lastRefreshSuccess} / ${app.lastRefreshTotal}',
      '自动刷新：${app.autoRefresh ? '已开启' : '已关闭'}（固定 30 分钟）',
      '参与来源：已启用且已配置接口的来源',
    ].join('\n');
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('刷新记录'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            content,
            style: TextStyle(color: p.text2, fontSize: 13, height: 1.6),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  void _showVersion() {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Pulse ${AppState.appVersion} (${AppState.appBuild})'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '当前为内部分发版本，已是最新版本。\n更新方式：在资源页重新安装最新的 news 安装包。',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache() async {
    final bytes = app.cacheBytes;
    final ok = await _confirm(
      title: '清理缓存？',
      message: '将删除 ${formatBytes(bytes)} 的离线热榜快照与正文缓存。'
          '收藏、已读记录和数据源配置会保留。',
      confirmLabel: '清理',
      destructive: true,
    );
    if (!ok) return;
    await app.clearCache();
    _snack('缓存已清理');
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
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 2),
                  child: Text(
                    '设置',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                _Profile(
                  sourceCount: app.sources.length,
                  enabledCount: app.enabledCount,
                ),
                const SectionLabel('刷新', padding: EdgeInsets.fromLTRB(22, 8, 22, 10)),
                SettingsCard(
                  children: [
                    SettingsRow(
                      icon: CupertinoIcons.arrow_clockwise,
                      iconColor: p.accent2,
                      title: '自动刷新',
                      badge: '30 分钟',
                      subtitle: '开启后每 30 分钟自动更新已启用的来源',
                      trailing: PulseSwitch(
                        value: app.autoRefresh,
                        onChanged: app.setAutoRefresh,
                      ),
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.time,
                      iconColor: p.blue,
                      title: '上次刷新',
                      subtitle: refreshLine(
                        app.lastRefreshAt,
                        app.lastRefreshSuccess,
                        app.lastRefreshTotal,
                      ),
                      onTap: _showRefreshInfo,
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.trash,
                      iconColor: p.green,
                      title: '清理缓存',
                      subtitle: '已占用 ${formatBytes(app.cacheBytes)}',
                      onTap: _clearCache,
                    ),
                  ],
                ),
                const _HintText(
                  '仅在前台运行时刷新，进入后台会自动暂停，回到前台立即补一次。',
                ),
                const SectionLabel('内容'),
                SettingsCard(
                  children: [
                    SettingsRow(
                      icon: CupertinoIcons.globe,
                      iconColor: p.blue,
                      title: '所有新闻用网页模式',
                      subtitle: '默认开启：跳过文字抓取，直接加载原网页',
                      trailing: PulseSwitch(
                        value: app.forceWebMode,
                        onChanged: app.setForceWebMode,
                      ),
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.bookmark,
                      iconColor: p.accent,
                      title: '我的收藏',
                      subtitle:
                          '${app.saved.length} 篇文章 · ${app.savedSourceCount} 个来源',
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const LibraryPage(),
                        ),
                      ),
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.square_grid_2x2,
                      iconColor: p.blue,
                      title: '数据源',
                      subtitle:
                          '${app.sources.length} 个可用 · ${app.enabledCount} 个已启用',
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const SourcePickerPage(),
                        ),
                      ),
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.arrow_up_doc,
                      iconColor: p.green,
                      title: '导入 JSON',
                      subtitle: '载入源配置或离线文章快照',
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const ImportPage(),
                        ),
                      ),
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.arrow_down_doc,
                      iconColor: p.text2,
                      title: '导出数据',
                      subtitle: '收藏、已读与源配置打包导出',
                      trailing: _exporting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                              ),
                            )
                          : null,
                      onTap: _exporting ? null : _export,
                    ),
                  ],
                ),
                const SectionLabel('外观'),
                SettingsCard(
                  children: [
                    SettingsRow(
                      icon: CupertinoIcons.moon,
                      iconColor: p.text2,
                      title: '主题',
                      subtitle: '${app.themeLabel} · 点按切换',
                      trailing: Text(
                        app.themeLabel,
                        style: TextStyle(color: p.text3, fontSize: 12.5),
                      ),
                      onTap: app.cycleTheme,
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.text_alignleft,
                      iconColor: p.text2,
                      title: '字号',
                      subtitle:
                          '正文 ${(14.5 * app.textScale).toStringAsFixed(1)}pt · ${app.textScaleLabel}',
                      trailing: Text(
                        'A',
                        style: TextStyle(
                          color: p.text3,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: app.cycleTextScale,
                    ),
                  ],
                ),
                const SectionLabel('关于'),
                SettingsCard(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    SettingsRow(
                      icon: CupertinoIcons.info,
                      iconColor: p.text2,
                      title: '版本',
                      subtitle:
                          '${AppState.appVersion} (${AppState.appBuild}) · 检查更新',
                      onTap: _showVersion,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.sourceCount, required this.enabledCount});

  final int sourceCount;
  final int enabledCount;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: SweepGradient(
                colors: [p.accent, p.accent2, p.blue, p.accent],
                stops: const [0, 0.38, 0.7, 1],
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: p.brightness == Brightness.dark
                    ? const Color(0xFF141419)
                    : p.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                'Pu',
                style: TextStyle(
                  color: p.text2,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pulse',
                  style: TextStyle(
                    color: p.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$sourceCount 个来源 · 已启用 $enabledCount 个 · '
                  '版本 ${AppState.appVersion}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text3, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 9, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info_circle, size: 13, color: p.text3),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: p.text3, fontSize: 11, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
