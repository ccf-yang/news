import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class HotFetchException implements Exception {
  HotFetchException(this.message, {this.offline = false});

  final String message;
  final bool offline;

  @override
  String toString() => message;
}

/// 热榜接口客户端。接口返回：{code:200,data:[{index,title,hotValue,link}]}
class HotApi {
  HotApi({http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  Future<List<Article>> fetch(NewsSource source) async {
    if (source.url.trim().isEmpty) {
      throw HotFetchException('「${source.name}」没有配置接口地址');
    }
    final uri = Uri.tryParse(source.url);
    if (uri == null || !uri.hasScheme) {
      throw HotFetchException('「${source.name}」的接口地址无效');
    }

    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'User-Agent': userAgent,
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      ).timeout(timeout);
    } on TimeoutException {
      throw HotFetchException('连接「${source.name}」超时', offline: true);
    } on SocketException {
      throw HotFetchException('当前无网络连接', offline: true);
    } on http.ClientException {
      throw HotFetchException('网络请求失败', offline: true);
    }

    if (response.statusCode != 200) {
      throw HotFetchException('「${source.name}」返回 HTTP ${response.statusCode}');
    }
    return parseListResponse(response.bodyBytes, source);
  }

  /// 纯函数，便于单测。
  static List<Article> parseListResponse(List<int> bytes, NewsSource source) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      throw HotFetchException('「${source.name}」返回的不是有效 JSON');
    }
    if (decoded is! Map) {
      throw HotFetchException('「${source.name}」返回格式异常');
    }
    final map = Map<String, dynamic>.from(decoded);
    final code = readInt(map['code'], fallback: -1);
    if (code != 200) {
      throw HotFetchException('「${source.name}」接口错误 code=$code');
    }
    final data = map['data'];
    if (data is! List) {
      throw HotFetchException('「${source.name}」没有返回榜单数据');
    }

    final items = <Article>[];
    for (var i = 0; i < data.length && items.length < 50; i++) {
      final entry = data[i];
      if (entry is! Map) continue;
      final mapEntry = Map<String, dynamic>.from(entry);
      if (readString(mapEntry['title']) == null) continue;
      items.add(Article.fromApi(mapEntry, source, fallbackRank: i + 1));
    }
    if (items.isEmpty) {
      throw HotFetchException('「${source.name}」榜单为空');
    }
    return items;
  }

  void close() => _client.close();
}
