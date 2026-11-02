// 临时诊断脚本：热榜第一页的原文链接在 Dart HTTP 下的真实返回。
// 用法：dart run tool/probe_links.dart [sourceLimit] [articlesPerSource]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

Future<void> main(List<String> args) async {
  final limit = args.isNotEmpty ? int.parse(args[0]) : 20;
  final per = args.length > 1 ? int.parse(args[1]) : 3;
  final raw = await File('assets/data/hot-sources.json').readAsString();
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final sources = (data['sources'] as List).cast<Map<String, dynamic>>();

  final client = http.Client();
  final rows = <String>[];
  final hostStats = <String, List<int>>{};
  var ok = 0, bad = 0;

  for (final s in sources.take(limit)) {
    final name = (s['name'] ?? '') as String;
    final listUrl = (s['url'] ?? '') as String;
    try {
      final r = await client
          .get(Uri.parse(listUrl), headers: {
            'User-Agent': ua,
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          })
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        rows.add('LIST $name ${r.statusCode}');
        continue;
      }
      final body = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      final items = (body['data'] as List).cast<Map<String, dynamic>>();
      for (final item in items.take(per)) {
        final link = (item['link'] ?? '') as String;
        final uri = Uri.tryParse(link);
        if (uri == null) continue;
        final host = uri.host;
        try {
          final p = await client.get(uri, headers: {
            'User-Agent': ua,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          }).timeout(const Duration(seconds: 12));
          final text = utf8.decode(p.bodyBytes, allowMalformed: true);
          var note = '';
          if (p.statusCode != 200) {
            note = text.length > 160 ? text.substring(0, 120) : text;
            note = note.replaceAll(RegExp(r'\s+'), ' ');
            bad++;
          } else {
            final lower = text.toLowerCase();
            if (lower.contains('captcha') || lower.contains('环境异常')) {
              note = 'CAPTCHA';
              bad++;
            } else if (text.length < 400) {
              note = 'SHORT:${text.length}';
              bad++;
            } else {
              ok++;
            }
          }
          final finalHost = p.request?.url.host ?? host;
          rows.add('PAGE $host -> $finalHost ${p.statusCode} ${p.bodyBytes.length}B $note');
          hostStats.putIfAbsent(host, () => []).add(p.statusCode);
          if (p.request?.url != null && p.request!.url.host != host) {
            rows.add('  REDIR ${p.request!.url}');
          }
        } on TimeoutException {
          rows.add('PAGE $host TIMEOUT');
          bad++;
        } catch (e) {
          rows.add('PAGE $host ERR $e');
          bad++;
        }
      }
    } on TimeoutException {
      rows.add('LIST $name TIMEOUT');
    } catch (e) {
      rows.add('LIST $name ERR $e');
    }
  }

  client.close();
  stdout.writeln(rows.join('\n'));
  stdout.writeln('\n=== SUMMARY ok=$ok bad=$bad ===');
  final hosts = hostStats.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final h in hosts.take(40)) {
    final s = h.value;
    final okCount = s.where((c) => c == 200).length;
    stdout.writeln('${h.key}: n=${s.length} 200=$okCount codes=${s.toSet().toList()}');
  }
}
