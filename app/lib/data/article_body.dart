import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charset_converter/charset_converter.dart';
import 'package:http/http.dart' as http;

import 'hot_api.dart';
import 'models.dart';

class ArticleBodyException implements Exception {
  ArticleBodyException(this.message, {this.needsWeb = false});

  final String message;

  /// 站点明确拒绝机器人抓取（403/验证页/正文为空）时置 true，
  /// 阅读页据此自动切到内嵌浏览器，避免用户卡在错误提示上。
  final bool needsWeb;

  @override
  String toString() => message;
}

/// 打开原文前，先尝试在 App 内抓取一份可读正文（FR-4.1）。
///
/// 热榜接口只给标题和链接，因此这里是尽力而为：抓不到就明确提示
/// 用户点「打开原文」，不伪造正文。
class ArticleBodyService {
  ArticleBodyService({http.Client? client, this.timeout = const Duration(seconds: 12)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  Future<String> fetch(Article article) async {
    final uri = Uri.tryParse(article.link);
    if (uri == null || !uri.hasScheme) {
      throw ArticleBodyException('这条热榜没有可用的原文链接');
    }

    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'User-Agent': HotApi.userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          // 部分站点校验站内来源，带上同站根路径可减少直接拒绝。
          'Referer': '${uri.scheme}://${uri.host}/',
        },
      ).timeout(timeout);
    } on TimeoutException {
      throw ArticleBodyException('正文加载超时，可点「打开原文」查看');
    } on SocketException {
      throw ArticleBodyException('当前无网络连接');
    } on http.ClientException {
      throw ArticleBodyException('正文加载失败');
    }

    final code = response.statusCode;
    if (code != 200) {
      final blocked = code == 401 || code == 403 || code == 412 || code == 429;
      throw ArticleBodyException(
        blocked
            ? '站点拦截了文字抓取（HTTP $code），已切换网页模式'
            : '原文返回 HTTP $code',
        needsWeb: blocked || code >= 500,
      );
    }

    final text = await decodeBody(response);
    final extracted = extractArticleText(text);
    // 有些站点不返回 403，而是返回 200 + 验证页（微信/掘金/B 站等）。
    if (_looksBlocked(extracted)) {
      throw ArticleBodyException('站点要求浏览器验证，已切换网页模式', needsWeb: true);
    }
    if (extracted.length < 60) {
      throw ArticleBodyException('这个站点没有提供可读正文，已切换网页模式', needsWeb: true);
    }
    return extracted;
  }

  static bool _looksBlocked(String visibleText) {
    final lower = visibleText.toLowerCase();
    return lower.contains('环境异常') ||
        lower.contains('完成验证') ||
        lower.contains('安全验证') ||
        lower.contains('访问过于频繁') ||
        lower.contains('just a moment') ||
        lower.contains('verify you are human') ||
        lower.contains('enable javascript and cookies');
  }

  static Future<String> decodeBody(http.Response response) async {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final head = latin1.decode(
      response.bodyBytes.take(2048).toList(),
      allowInvalid: true,
    ).toLowerCase();

    final label = _charsetOf(contentType) ?? _charsetOf(head);
    if (label == null || label == 'utf-8' || label == 'utf8') {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    if (label == 'gbk' || label == 'gb2312' || label == 'gb18030') {
      try {
        return await CharsetConverter.decode('gbk', response.bodyBytes);
      } catch (_) {
        return utf8.decode(response.bodyBytes, allowMalformed: true);
      }
    }
    try {
      return await CharsetConverter.decode(label, response.bodyBytes);
    } catch (_) {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
  }

  static String? _charsetOf(String haystack) {
    final m = RegExp("charset\\s*=\\s*[\"']?([a-z0-9_\\-]+)").firstMatch(haystack);
    return m?.group(1);
  }

  /// 从 HTML 中抽取正文段落。纯函数，便于单测。
  static String extractArticleText(String html) {
    var s = html
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
        .replaceAll(
            RegExp(r'<(script|style|noscript|svg|iframe|form|nav|header|footer)[^>]*>[\s\S]*?</\1>',
                caseSensitive: false),
            ' ');

    final article = RegExp(r'<article[^>]*>([\s\S]*?)</article>', caseSensitive: false)
        .firstMatch(s);
    if (article != null) s = article.group(1)!;

    final paragraphs = <String>[];
    for (final m in RegExp(r'<p[^>]*>([\s\S]*?)</p>', caseSensitive: false).allMatches(s)) {
      final text = _plain(m.group(1) ?? '');
      if (text.length >= 15) paragraphs.add(text);
    }

    var result = paragraphs.join('\n\n');
    if (result.length < 120) {
      // 有些站点正文全在 div 里，退化为整页纯文本。
      final whole = _plain(s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'));
      if (whole.length > result.length) result = whole;
    }
    if (result.length > 18000) {
      result = '${result.substring(0, 18000)}…';
    }
    return result;
  }

  static String _plain(String fragment) {
    var s = fragment
        .replaceAll(RegExp(r'<(br|/p|/div|/h[1-6]|/li)\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? '' : String.fromCharCode(code);
    });
    s = s.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
    return s.trim();
  }

  void close() => _client.close();
}
