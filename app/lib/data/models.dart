/// 数据模型：来源、文章与一次热榜快照。
///
/// 字段命名沿用需求文档 5.1 / 5.2 的数据契约，确保导出的 JSON
/// 与仓库里的 hot-sources.json / sample-news.json 互通。
library;

String? readString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

int readInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  final s = value?.toString();
  if (s == null) return fallback;
  return int.tryParse(s.trim()) ?? fallback;
}

/// 文章稳定 id：优先用原文链接，缺失时退化为来源 + 标题。
String articleIdOf({
  required String sourceId,
  required String link,
  required String title,
}) {
  final base = link.trim().isNotEmpty ? link.trim() : title.trim();
  return '$sourceId|$base';
}

class NewsSource {
  const NewsSource({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    required this.icon,
    required this.url,
    this.enabled = false,
  });

  final String id;
  final String name;
  final String type;
  final String category;
  final String icon;
  final String url;
  final bool enabled;

  NewsSource copyWith({bool? enabled, String? name, String? type, String? category, String? icon, String? url}) {
    return NewsSource(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      category: category ?? this.category,
      icon: icon ?? this.icon,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'category': category,
        'icon': icon,
        'url': url,
        'enabled': enabled,
      };

  factory NewsSource.fromJson(Map<String, dynamic> json, {bool enabled = false}) {
    return NewsSource(
      id: readString(json['id']) ?? '',
      name: readString(json['name']) ?? '未命名来源',
      type: readString(json['type']) ?? '',
      category: readString(json['category']) ?? '未分类',
      icon: readString(json['icon']) ?? '',
      url: readString(json['url']) ?? '',
      enabled: json['enabled'] is bool ? json['enabled'] as bool : enabled,
    );
  }

  /// 分类接口 / Top 榜接口返回的单条来源。
  factory NewsSource.fromApi(Map<String, dynamic> json) {
    final id = readString(json['id']) ?? '';
    final base = readString(json['url']);
    return NewsSource(
      id: id,
      name: readString(json['name']) ?? '未命名来源',
      type: readString(json['type']) ?? '',
      category: readString(json['category']) ?? '未分类',
      icon: readString(json['icon']) ?? '',
      url: base ??
          'https://base.itab.link/api/top/list?lang=cn&id=$id&size=50',
    );
  }
}

class Article {
  const Article({
    required this.id,
    required this.rank,
    required this.title,
    required this.hotValue,
    required this.link,
    required this.sourceId,
    required this.sourceName,
    required this.sourceType,
    required this.category,
  });

  final String id;
  final int rank;
  final String title;
  final String hotValue;
  final String link;
  final String sourceId;
  final String sourceName;
  final String sourceType;
  final String category;

  factory Article.fromFeedItem(
    Map<String, dynamic> json,
    NewsSource source, {
    required int fallbackRank,
  }) {
    final title = readString(json['title']) ?? '无标题';
    final link = readString(json['link']) ?? '';
    return Article(
      id: readString(json['id']) ??
          articleIdOf(sourceId: source.id, link: link, title: title),
      rank: readInt(json['rank'] ?? json['index'], fallback: fallbackRank),
      title: title,
      hotValue: readString(json['hotValue']) ?? '',
      link: link,
      sourceId: readString(json['sourceId']) ?? source.id,
      sourceName: readString(json['sourceName']) ?? source.name,
      sourceType: readString(json['sourceType']) ?? source.type,
      category: readString(json['category']) ?? source.category,
    );
  }

  /// 数据源接口返回：{index, title, hotValue, link}
  factory Article.fromApi(
    Map<String, dynamic> json,
    NewsSource source, {
    required int fallbackRank,
  }) {
    final title = readString(json['title']) ?? '无标题';
    final link = readString(json['link']) ?? '';
    return Article(
      id: articleIdOf(sourceId: source.id, link: link, title: title),
      rank: readInt(json['index'] ?? json['rank'], fallback: fallbackRank),
      title: title,
      hotValue: readString(json['hotValue']) ?? '',
      link: link,
      sourceId: source.id,
      sourceName: source.name,
      sourceType: source.type,
      category: source.category,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rank': rank,
        'title': title,
        'hotValue': hotValue,
        'link': link,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'sourceType': sourceType,
        'category': category,
      };

  factory Article.fromJson(Map<String, dynamic> json) {
    final sourceId = readString(json['sourceId']) ?? '';
    final title = readString(json['title']) ?? '无标题';
    final link = readString(json['link']) ?? '';
    return Article(
      id: readString(json['id']) ??
          articleIdOf(sourceId: sourceId, link: link, title: title),
      rank: readInt(json['rank'], fallback: 0),
      title: title,
      hotValue: readString(json['hotValue']) ?? '',
      link: link,
      sourceId: sourceId,
      sourceName: readString(json['sourceName']) ?? '',
      sourceType: readString(json['sourceType']) ?? '',
      category: readString(json['category']) ?? '',
    );
  }
}

class FeedSnapshot {
  const FeedSnapshot({
    required this.sourceId,
    required this.fetchedAt,
    required this.items,
  });

  final String sourceId;
  final DateTime fetchedAt;
  final List<Article> items;

  bool get isEmpty => items.isEmpty;

  Map<String, dynamic> toJson() => {
        'fetchedAt': fetchedAt.toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory FeedSnapshot.fromJson(Map<String, dynamic> json) {
    final items = <Article>[];
    for (final raw in (json['items'] as List? ?? const [])) {
      if (raw is Map<String, dynamic>) {
        items.add(Article.fromJson(raw));
      } else if (raw is Map) {
        items.add(Article.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return FeedSnapshot(
      sourceId: readString(json['sourceId']) ?? '',
      fetchedAt: DateTime.tryParse(readString(json['fetchedAt']) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      items: items,
    );
  }
}

class SavedEntry {
  const SavedEntry({required this.article, required this.savedAt});

  final Article article;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'article': article.toJson(),
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['article'];
    return SavedEntry(
      article: raw is Map
          ? Article.fromJson(Map<String, dynamic>.from(raw))
          : Article.fromJson(const {}),
      savedAt: DateTime.tryParse(readString(json['savedAt']) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
