import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/data/importer.dart';

void main() {
  test('内置 hot-sources.json：81 个来源、20 个分类', () {
    final text = File('assets/data/hot-sources.json').readAsStringSync();
    final report = PulseImporter.parse(text, fileName: 'hot-sources.json');

    expect(report.fatal, isFalse);
    expect(report.sources, hasLength(81));
    expect(report.categories, hasLength(20));
    expect(report.sources.every((s) => s.url.startsWith('https://')), isTrue);
    expect(report.sources.map((s) => s.id).toSet(), hasLength(81));
  });

  test('内置 sample-news.json：微信 30 条文章', () {
    final text = File('assets/data/sample-news.json').readAsStringSync();
    final report = PulseImporter.parse(text, fileName: 'sample-news.json');

    expect(report.fatal, isFalse);
    expect(report.usable, isTrue);
    expect(report.sourceName, '微信');
    expect(report.articles, hasLength(30));
    expect(report.articles.first.rank, 1);
    expect(jsonEncode(report.articles.first.toJson()), contains('"sourceId":"WnBe01o371"'));
  });
}
