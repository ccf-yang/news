import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/data/hot_api.dart';
import 'package:pulse/data/models.dart';

const source = NewsSource(
  id: 'wx',
  name: '微信',
  type: '24h热文榜',
  category: '综合',
  icon: '',
  url: 'https://example.com/list',
);

List<int> bytesOf(Object body) => utf8.encode(jsonEncode(body));

void main() {
  test('解析正常榜单并保留 index 排名', () {
    final items = HotApi.parseListResponse(
      bytesOf({
        'code': 200,
        'data': [
          {'index': 3, 'title': '标题三', 'hotValue': '9.9万', 'link': 'https://example.com/3'},
          {'index': 1, 'title': '标题一', 'hotValue': '10.0万', 'link': 'https://example.com/1'},
        ],
      }),
      source,
    );

    expect(items, hasLength(2));
    expect(items.first.rank, 3);
    expect(items.first.sourceName, '微信');
    expect(items[1].rank, 1);
    expect(items[1].id, 'wx|https://example.com/1');
  });

  test('最多保留 50 条', () {
    final data = List.generate(
      80,
      (i) => {
        'index': i + 1,
        'title': '标题 $i',
        'hotValue': '',
        'link': 'https://example.com/$i',
      },
    );
    final items = HotApi.parseListResponse(
      bytesOf({'code': 200, 'data': data}),
      source,
    );
    expect(items, hasLength(50));
  });

  test('无标题的条目被忽略但索引仍然有效', () {
    final items = HotApi.parseListResponse(
      bytesOf({
        'code': 200,
        'data': [
          {'index': 1, 'title': ''},
          {'index': 2, 'title': '有效', 'link': 'https://example.com/2'},
        ],
      }),
      source,
    );
    expect(items.single.rank, 2);
  });

  test('code 非 200 抛错', () {
    expect(
      () => HotApi.parseListResponse(bytesOf({'code': 500, 'data': []}), source),
      throwsA(isA<HotFetchException>()),
    );
  });

  test('无效 JSON 抛错', () {
    expect(
      () => HotApi.parseListResponse(utf8.encode('nope'), source),
      throwsA(isA<HotFetchException>()),
    );
  });

  test('榜单为空抛错', () {
    expect(
      () => HotApi.parseListResponse(bytesOf({'code': 200, 'data': []}), source),
      throwsA(isA<HotFetchException>()),
    );
  });
}
