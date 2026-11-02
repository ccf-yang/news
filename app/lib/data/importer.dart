import 'dart:convert';

import '../data/models.dart';

/// 单个字段级问题，path 精确到数据位置，例如 `sources[3].id`。
class ImportIssue {
  const ImportIssue(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => path.isEmpty ? message : '$path：$message';
}

/// 一个 JSON 文件的校验结果。
///
/// 顶层致命错误（版本/kind/JSON 语法）用 [fatalError] 表达，此时不导入任何内容；
/// 单条坏数据只记入 [issues]，启用「跳过坏条目」时其它条目照常写入（FR-1.3 / FR-1.5）。
class ImportReport {
  ImportReport({
    required this.fileName,
    this.kind = '',
    this.fatalError,
    List<NewsSource>? sources,
    List<String>? categories,
    List<Article>? articles,
    this.sourceId,
    this.sourceName,
    this.sourceType,
    this.category,
    this.fetchedAt,
    List<ImportIssue> issues = const [],
    this.skipped = 0,
  })  : sources = sources ?? const [],
        categories = categories ?? const [],
        articles = articles ?? const [],
        issues = List.unmodifiable(issues);

  final String fileName;
  final String kind;
  final String? fatalError;
  final List<NewsSource> sources;
  final List<String> categories;
  final List<Article> articles;
  final String? sourceId;
  final String? sourceName;
  final String? sourceType;
  final String? category;
  final DateTime? fetchedAt;
  final List<ImportIssue> issues;
  final int skipped;

  bool get fatal => fatalError != null;
  bool get hasIssues => issues.isNotEmpty;

  /// 没有致命错误、且至少有一条可写入的数据。
  bool get usable => !fatal && (sources.isNotEmpty || articles.isNotEmpty);

  String get kindLabel {
    switch (kind) {
      case 'sources':
        return '源配置';
      case 'feed':
        return '文章快照';
      default:
        return '未知';
    }
  }

  String get summary {
    if (fatal) return fatalError!;
    if (kind == 'sources') {
      final cats = categories.length;
      return '${sources.length} 个来源 · $cats 个分类'
          '${skipped > 0 ? ' · 跳过 $skipped 条' : ''}';
    }
    if (kind == 'feed') {
      final name = sourceName ?? sourceId ?? '未知来源';
      return '$name · ${articles.length} 条文章'
          '${skipped > 0 ? ' · 跳过 $skipped 条' : ''}';
    }
    return '无可导入内容';
  }
}

/// 与 UI 解耦的纯校验器，方便单元测试。
class PulseImporter {
  static const int supportedVersion = 1;
  static const int maxBytes = 20 * 1024 * 1024;

  static ImportReport parse(String text, {required String fileName}) {
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return ImportReport(
        fileName: fileName,
        fatalError: 'JSON 语法错误：${e.message}${e.offset != null ? '（偏移 ${e.offset}）' : ''}',
      );
    }
    return validate(decoded, fileName: fileName);
  }

  static ImportReport validate(dynamic decoded, {required String fileName}) {
    if (decoded is! Map) {
      return ImportReport(
        fileName: fileName,
        fatalError: '根节点必须是对象（实际是 ${decoded.runtimeType}）',
      );
    }
    final json = Map<String, dynamic>.from(decoded);

    final version = json['version'];
    if (version == null) {
      return ImportReport(fileName: fileName, fatalError: 'version：缺少必需字段');
    }
    if (readInt(version, fallback: -1) != supportedVersion) {
      return ImportReport(
        fileName: fileName,
        fatalError: 'version：期望 $supportedVersion，实际 ${version.toString()}',
      );
    }

    final kind = readString(json['kind']);
    if (kind == null) {
      return ImportReport(fileName: fileName, fatalError: 'kind：缺少必需字段');
    }
    if (kind == 'sources') return _sources(json, fileName);
    if (kind == 'feed') return _feed(json, fileName);
    return ImportReport(
      fileName: fileName,
      fatalError: 'kind：只支持 "sources" 或 "feed"，实际 "$kind"',
    );
  }

  static ImportReport _sources(Map<String, dynamic> json, String fileName) {
    final raw = json['sources'];
    if (raw is! List) {
      return ImportReport(
        fileName: fileName,
        kind: 'sources',
        fatalError: 'sources：缺少数组',
      );
    }
    if (raw.isEmpty) {
      return ImportReport(
        fileName: fileName,
        kind: 'sources',
        fatalError: 'sources：数组为空',
      );
    }

    final sources = <NewsSource>[];
    final issues = <ImportIssue>[];
    final seen = <String>{};
    var skipped = 0;

    for (var i = 0; i < raw.length; i++) {
      final path = 'sources[$i]';
      final entry = raw[i];
      if (entry is! Map) {
        issues.add(ImportIssue(path, '必须是对象'));
        skipped++;
        continue;
      }
      final map = Map<String, dynamic>.from(entry);
      final id = readString(map['id']);
      final name = readString(map['name']);
      final url = readString(map['url']);
      var bad = false;
      if (id == null) {
        issues.add(ImportIssue('$path.id', '缺少或为空'));
        bad = true;
      }
      if (name == null) {
        issues.add(ImportIssue('$path.name', '缺少或为空'));
        bad = true;
      }
      if (url == null) {
        issues.add(ImportIssue('$path.url', '缺少或为空'));
        bad = true;
      }
      if (bad) {
        skipped++;
        continue;
      }
      final source = NewsSource(
        id: id!,
        name: name!,
        type: readString(map['type']) ?? '',
        category: readString(map['category']) ?? '未分类',
        icon: readString(map['icon']) ?? '',
        url: url!,
      );
      if (!seen.add(source.id)) {
        issues.add(ImportIssue('$path.id', '重复的来源 id「${source.id}」，保留第一条'));
        skipped++;
        continue;
      }
      sources.add(source);
    }

    final categories = <String>[];
    final rawCats = json['categories'];
    if (rawCats is List) {
      for (final c in rawCats) {
        final name = readString(c);
        if (name != null && !categories.contains(name)) categories.add(name);
      }
    }
    for (final s in sources) {
      if (!categories.contains(s.category)) categories.add(s.category);
    }

    return ImportReport(
      fileName: fileName,
      kind: 'sources',
      sources: sources,
      categories: categories,
      issues: issues,
      skipped: skipped,
    );
  }

  static ImportReport _feed(Map<String, dynamic> json, String fileName) {
    final sourceId = readString(json['sourceId']);
    final sourceName = readString(json['sourceName']);
    final raw = json['items'];

    if (sourceId == null) {
      return ImportReport(
        fileName: fileName,
        kind: 'feed',
        fatalError: 'sourceId：缺少必需字段',
      );
    }
    if (sourceName == null) {
      return ImportReport(
        fileName: fileName,
        kind: 'feed',
        fatalError: 'sourceName：缺少必需字段',
      );
    }
    if (raw is! List) {
      return ImportReport(
        fileName: fileName,
        kind: 'feed',
        fatalError: 'items：缺少数组',
      );
    }
    if (raw.isEmpty) {
      return ImportReport(
        fileName: fileName,
        kind: 'feed',
        fatalError: 'items：数组为空',
      );
    }

    final sourceType = readString(json['sourceType']) ?? '';
    final category = readString(json['category']) ?? '未分类';
    final fetchedAt = DateTime.tryParse(readString(json['fetchedAt']) ?? '') ?? DateTime.now();
    final source = NewsSource(
      id: sourceId,
      name: sourceName,
      type: sourceType,
      category: category,
      icon: '',
      url: 'https://base.itab.link/api/top/list?lang=cn&id=$sourceId&size=50',
    );

    final articles = <Article>[];
    final issues = <ImportIssue>[];
    final seen = <String>{};
    var skipped = 0;

    for (var i = 0; i < raw.length; i++) {
      final path = 'items[$i]';
      final entry = raw[i];
      if (entry is! Map) {
        issues.add(ImportIssue(path, '必须是对象'));
        skipped++;
        continue;
      }
      final map = Map<String, dynamic>.from(entry);
      final title = readString(map['title']);
      final link = readString(map['link']);
      var bad = false;
      if (title == null) {
        issues.add(ImportIssue('$path.title', '缺少或为空'));
        bad = true;
      }
      if (link == null) {
        issues.add(ImportIssue('$path.link', '缺少或为空'));
        bad = true;
      }
      if (bad) {
        skipped++;
        continue;
      }
      final article = Article.fromFeedItem(map, source, fallbackRank: i + 1);
      if (!seen.add(article.id)) {
        issues.add(ImportIssue('$path.id', '重复条目，已跳过'));
        skipped++;
        continue;
      }
      articles.add(article);
    }

    return ImportReport(
      fileName: fileName,
      kind: 'feed',
      articles: articles,
      sourceId: sourceId,
      sourceName: sourceName,
      sourceType: sourceType,
      category: category,
      fetchedAt: fetchedAt,
      issues: issues,
      skipped: skipped,
    );
  }
}
