import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/data/importer.dart';

void main() {
  group('PulseImporter sources', () {
    test('合法源配置写入来源与分类', () {
      final report = PulseImporter.parse(
        jsonEncode({
          'version': 1,
          'kind': 'sources',
          'categories': ['综合', '科技'],
          'sources': [
            {
              'id': 'a',
              'name': '微信',
              'type': '24h热文榜',
              'category': '综合',
              'url': 'https://example.com/a',
            },
            {
              'id': 'b',
              'name': '知乎',
              'category': '社区',
              'url': 'https://example.com/b',
            },
          ],
        }),
        fileName: 'sources.json',
      );

      expect(report.fatal, isFalse);
      expect(report.usable, isTrue);
      expect(report.sources, hasLength(2));
      expect(report.categories, containsAll(['综合', '科技', '社区']));
      expect(report.sources.first.enabled, isFalse);
    });

    test('坏条目按字段路径记录并跳过', () {
      final report = PulseImporter.parse(
        jsonEncode({
          'version': 1,
          'kind': 'sources',
          'sources': [
            {'id': 'ok', 'name': '微信', 'url': 'https://example.com'},
            {'id': '', 'name': '知乎', 'url': 'https://example.com'},
            'not-an-object',
          ],
        }),
        fileName: 'sources.json',
      );

      expect(report.sources, hasLength(1));
      expect(report.skipped, 2);
      expect(report.issues.map((e) => e.path), containsAll([
        'sources[1].id',
        'sources[2]',
      ]));
    });

    test('重复 id 保留第一条', () {
      final report = PulseImporter.parse(
        jsonEncode({
          'version': 1,
          'kind': 'sources',
          'sources': [
            {'id': 'dup', 'name': '一', 'url': 'https://example.com/1'},
            {'id': 'dup', 'name': '二', 'url': 'https://example.com/2'},
          ],
        }),
        fileName: 'sources.json',
      );

      expect(report.sources.single.name, '一');
      expect(report.skipped, 1);
    });
  });

  group('PulseImporter 顶层校验', () {
    test('JSON 语法错误是致命错误', () {
      final report = PulseImporter.parse('{oops', fileName: 'bad.json');
      expect(report.fatal, isTrue);
      expect(report.fatalError, contains('JSON 语法错误'));
      expect(report.usable, isFalse);
    });

    test('版本不匹配是致命错误', () {
      final report = PulseImporter.parse(
        jsonEncode({'version': 2, 'kind': 'sources', 'sources': []}),
        fileName: 'bad.json',
      );
      expect(report.fatal, isTrue);
      expect(report.fatalError, contains('version'));
    });

    test('未知 kind 被拒绝', () {
      final report = PulseImporter.parse(
        jsonEncode({'version': 1, 'kind': 'other'}),
        fileName: 'bad.json',
      );
      expect(report.fatal, isTrue);
      expect(report.fatalError, contains('kind'));
    });
  });

  group('PulseImporter feed', () {
    test('合法快照写入文章与来源信息', () {
      final report = PulseImporter.parse(
        jsonEncode({
          'version': 1,
          'kind': 'feed',
          'sourceId': 'wx',
          'sourceName': '微信',
          'sourceType': '24h热文榜',
          'category': '综合',
          'fetchedAt': '2026-11-02T09:41:00+08:00',
          'items': [
            {
              'rank': 1,
              'title': '标题一',
              'hotValue': '10.0万',
              'link': 'https://example.com/1',
            },
          ],
        }),
        fileName: 'feed.json',
      );

      expect(report.usable, isTrue);
      expect(report.kind, 'feed');
      expect(report.sourceId, 'wx');
      expect(report.articles.single.title, '标题一');
      expect(report.articles.single.sourceName, '微信');
      expect(report.fetchedAt, isNotNull);
    });

    test('缺少 link 的条目被跳过', () {
      final report = PulseImporter.parse(
        jsonEncode({
          'version': 1,
          'kind': 'feed',
          'sourceId': 'wx',
          'sourceName': '微信',
          'items': [
            {'title': '没有链接'},
            {'title': '正常', 'link': 'https://example.com/ok'},
          ],
        }),
        fileName: 'feed.json',
      );

      expect(report.articles, hasLength(1));
      expect(report.skipped, 1);
      expect(report.issues.single.path, 'items[0].link');
    });

    test('items 为空是致命错误', () {
      final report = PulseImporter.parse(
        jsonEncode({
          'version': 1,
          'kind': 'feed',
          'sourceId': 'wx',
          'sourceName': '微信',
          'items': [],
        }),
        fileName: 'feed.json',
      );
      expect(report.fatal, isTrue);
    });
  });
}
