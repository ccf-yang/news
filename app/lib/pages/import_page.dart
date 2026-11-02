import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/importer.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class _PickedFile {
  _PickedFile({
    required this.fileName,
    required this.report,
    this.size = 0,
    this.builtin = false,
  });

  final String fileName;
  final ImportReport report;
  final int size;
  final bool builtin;
}

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final AppState app = AppState.instance;
  final List<_PickedFile> _files = [];
  bool _importing = false;
  bool _written = false;

  bool get _hasUsable => _files.any((f) => f.report.usable);

  int get _usableCount => _files.where((f) => f.report.usable).length;

  Future<void> _pickFiles() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
    } catch (e) {
      _snack('无法打开文件选择器：$e');
      return;
    }
    if (result == null) return;

    final added = <_PickedFile>[];
    for (final file in result.files) {
      if (file.size > PulseImporter.maxBytes) {
        added.add(
          _PickedFile(
            fileName: file.name,
            size: file.size,
            report: ImportReport(
              fileName: file.name,
              fatalError:
                  '文件 ${formatBytes(file.size)}，超过 20 MB 上限（FR-1.4）',
            ),
          ),
        );
        continue;
      }
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (_) {
          bytes = null;
        }
      }
      if (bytes == null) {
        added.add(
          _PickedFile(
            fileName: file.name,
            size: file.size,
            report: ImportReport(
              fileName: file.name,
              fatalError: '无法读取文件内容，请重新选择',
            ),
          ),
        );
        continue;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      added.add(
        _PickedFile(
          fileName: file.name,
          size: file.size,
          report: PulseImporter.parse(text, fileName: file.name),
        ),
      );
    }

    if (!mounted) return;
    setState(() => _files.addAll(added));
  }

  Future<void> _addBuiltIn(String assetName) async {
    if (_files.any((f) => f.builtin && f.fileName == assetName)) {
      _snack('$assetName 已经在待导入列表里');
      return;
    }
    try {
      final text = await rootBundle.loadString('assets/data/$assetName');
      final report = PulseImporter.parse(text, fileName: assetName);
      if (!mounted) return;
      setState(() {
        _files.add(
          _PickedFile(
            fileName: assetName,
            report: report,
            size: text.length,
            builtin: true,
          ),
        );
      });
    } catch (e) {
      _snack('读取内置示例失败：$e');
    }
  }

  Future<void> _doImport() async {
    if (_importing) return;
    final usable = _files.where((f) => f.report.usable).toList();
    if (usable.isEmpty) {
      _snack('没有可导入的内容，请先选择 JSON 文件');
      return;
    }
    final issueCount =
        usable.fold<int>(0, (sum, f) => sum + f.report.issues.length);
    if (issueCount > 0) {
      final ok = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('跳过坏条目？'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '选中的文件里有 $issueCount 处字段问题。'
              '继续导入会跳过这些条目，其余内容照常写入本地。',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('跳过并导入'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    final fatalFiles = _files.where((f) => f.report.fatal).length;
    setState(() => _importing = true);
    var sources = 0;
    var categories = 0;
    var articles = 0;
    var skipped = 0;
    final issues = <ImportIssue>[];
    try {
      for (final file in usable) {
        final report = file.report;
        if (report.kind == 'sources') {
          sources += await app.importReport(report);
          categories += report.categories.length;
        } else {
          articles += await app.importReport(report);
        }
        skipped += report.skipped;
        issues.addAll(report.issues);
      }
      if (!mounted) return;
      setState(() {
        _written = true;
        _files.clear();
      });
      await _showSummary(
        sources: sources,
        categories: categories,
        articles: articles,
        skipped: skipped,
        issues: issues,
        fatalFiles: fatalFiles,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showSummary({
    required int sources,
    required int categories,
    required int articles,
    required int skipped,
    required List<ImportIssue> issues,
    required int fatalFiles,
  }) async {
    final lines = <String>[
      if (sources > 0) '来源配置：写入 $sources 个来源，共 $categories 个分类',
      if (articles > 0) '文章快照：写入 $articles 条文章',
      if (skipped > 0) '跳过坏条目：$skipped 条',
      if (fatalFiles > 0) '无法导入的文件：$fatalFiles 个',
      if (sources == 0 && articles == 0) '没有写入任何内容',
    ];
    final issueLines = issues.take(6).map((e) => '· $e').join('\n');
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('导入完成'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            lines.join('\n') +
                (issueLines.isEmpty ? '' : '\n\n问题示例：\n$issueLines'),
            style: const TextStyle(fontSize: 12.5, height: 1.6),
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

  void _showIssues(_PickedFile file) {
    final report = file.report;
    final p = context.palette;
    final content = report.fatal
        ? report.fatalError!
        : (report.issues.isEmpty
            ? '校验通过，没有发现字段问题。'
            : report.issues.take(20).map((e) => '· $e').join('\n'));
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(file.fileName),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            content,
            style: TextStyle(color: p.text2, fontSize: 12.5, height: 1.6),
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              PulseNavBar(
                title: '导入 JSON',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          const _HeroIcon(),
                          const SizedBox(height: 18),
                          Text(
                            '导入数据',
                            style: TextStyle(
                              color: p.text,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '选择 JSON 文件即可批量载入热榜源与离线文章。'
                            '支持 sources 与 feed 两种格式，导入前会逐字段校验。',
                            style: TextStyle(
                              color: p.text2,
                              fontSize: 13.5,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _DropZone(
                            onTap: _pickFiles,
                            count: _files.length,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '文件上限 20 MB；也可以从下方直接载入内置示例。',
                            style: TextStyle(color: p.text3, fontSize: 11),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                    SectionLabel(
                      _files.isEmpty ? '待导入文件' : '待导入文件 · ${_files.length}',
                      trailing: _files.isEmpty
                          ? null
                          : Text(
                              '已校验',
                              style: TextStyle(color: p.green, fontSize: 11.5),
                            ),
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
                    ),
                    if (_files.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: p.surface2.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: p.line),
                          ),
                          child: Text(
                            '还没有选择文件。点上面的虚线区域从「文件」App 选择，'
                            '或先用下面的内置示例体验导入流程。',
                            style: TextStyle(
                              color: p.text3,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final file in _files)
                        _FileRow(
                          file: file,
                          onTap: () => _showIssues(file),
                          onRemove: () => setState(() => _files.remove(file)),
                        ),
                    const SectionLabel(
                      '内置示例',
                      padding: EdgeInsets.fromLTRB(22, 22, 22, 10),
                    ),
                    _BuiltInRow(
                      title: 'hot-sources.json',
                      subtitle: '81 个来源 · 20 个分类',
                      tag: 'SOURCES',
                      color: p.blue,
                      onAdd: () => _addBuiltIn('hot-sources.json'),
                    ),
                    _BuiltInRow(
                      title: 'sample-news.json',
                      subtitle: '30 条微信 24h 热文',
                      tag: 'FEED',
                      color: p.green,
                      onAdd: () => _addBuiltIn('sample-news.json'),
                    ),
                    const SizedBox(height: 22),
                    _Steps(
                      picked: _files.isNotEmpty || _written,
                      checked: _files.isNotEmpty || _written,
                      written: _written,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: PrimaryGradientButton(
                  label: _importing
                      ? '正在写入…'
                      : _usableCount > 0
                          ? '导入 $_usableCount 个文件'
                          : '选择文件后导入',
                  icon: CupertinoIcons.arrow_down_doc,
                  enabled: _hasUsable && !_importing,
                  onTap: _doImport,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: p.accent.withValues(alpha: 0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.accent.withValues(alpha: 0.22),
            p.blue.withValues(alpha: 0.16),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(CupertinoIcons.arrow_up_doc, size: 28, color: p.accent2),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onTap, required this.count});

  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TapScale(
      onTap: onTap,
      scale: 0.99,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: p.text3.withValues(alpha: 0.55),
          radius: 20,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: p.brightness == Brightness.dark ? 0.02 : 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(
                CupertinoIcons.doc_text,
                size: 26,
                color: p.text2.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 10),
              Text(
                count == 0 ? '从「文件」App 选择 JSON' : '继续添加 JSON 文件',
                style: TextStyle(
                  color: p.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '支持多选 · JSON · 最大 20 MB',
                style: TextStyle(color: p.text3, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.7, 0.7, size.width - 1.4, size.height - 1.4),
          Radius.circular(radius),
        ),
      );
    const dash = 7.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.onTap,
    required this.onRemove,
  });

  final _PickedFile file;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final report = file.report;
    final Color tint;
    final String chip;
    if (report.fatal) {
      tint = const Color(0xFFE5484D);
      chip = '不可用';
    } else if (report.hasIssues) {
      tint = p.accent2;
      chip = '${report.issues.length} 处问题';
    } else if (report.kind == 'feed') {
      tint = p.blue;
      chip = '离线';
    } else {
      tint = p.green;
      chip = '可用';
    }
    final tag = report.kind == 'feed'
        ? 'FEED'
        : report.kind == 'sources'
            ? 'JSON'
            : 'ERR';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 9),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: TapScale(
              onTap: onTap,
              scale: 0.995,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: tint.withValues(alpha: 0.26)),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: tint,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            report.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: report.fatal ? tint : p.text3,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: tint.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        chip,
                        style: TextStyle(
                          color: tint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          TapScale(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
              child: Icon(CupertinoIcons.xmark_circle_fill, size: 16, color: p.text3),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuiltInRow extends StatelessWidget {
  const _BuiltInRow({
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.color,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final String tag;
  final Color color;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 9),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: p.surface2.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: color.withValues(alpha: 0.26)),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: p.text2,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: p.text3, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            IconCircleButton(
              icon: CupertinoIcons.add,
              size: 30,
              onTap: onAdd,
              iconColor: color,
            ),
          ],
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({
    required this.picked,
    required this.checked,
    required this.written,
  });

  final bool picked;
  final bool checked;
  final bool written;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final states = [picked, checked, written];
    const labels = ['选择文件', '校验格式', '写入本地'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
                child: Column(
                  children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: states[i] ? p.accentGradient : null,
                        color: states[i] ? null : p.line,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[i],
                      style: TextStyle(
                        color: states[i] ? p.text2 : p.text3,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
