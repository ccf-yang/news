import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 来源品牌色；未知来源用名称哈希稳定取色。
Color sourceColor(String name) {
  const known = <String, Color>{
    '微信': Color(0xFF07C160),
    '知乎': Color(0xFF0084FF),
    '微博': Color(0xFFE6162D),
    '百度': Color(0xFF2932E1),
    '哔哩哔哩': Color(0xFFFB7299),
    '抖音': Color(0xFF00C8D7),
    '36氪': Color(0xFF5B8CFF),
    '少数派': Color(0xFFD33A31),
    '虎嗅网': Color(0xFFF04A23),
    '掘金': Color(0xFF1E80FF),
    'GitHub': Color(0xFF4A4F57),
    '今日头条': Color(0xFFF04142),
    '淘宝': Color(0xFFFF5000),
    '淘宝 ‧ 天猫': Color(0xFFFF5000),
    '豆瓣电影': Color(0xFF007722),
    '豆瓣社区': Color(0xFF007722),
    'IT之家': Color(0xFFD22222),
    '虎扑社区': Color(0xFFC8102E),
    '什么值得买': Color(0xFFE94B4B),
    'App Store': Color(0xFF007AFF),
    'Product Hunt': Color(0xFFDA552F),
    'Dribbble': Color(0xFFEA4C89),
    'TapTap': Color(0xFF12C2C9),
    '知乎日报': Color(0xFF0084FF),
    '微信读书': Color(0xFF2F7BE8),
    '雪球': Color(0xFF1E6FFF),
    '第一财经': Color(0xFFC8102E),
  };
  final exact = known[name];
  if (exact != null) return exact;
  var hash = 0;
  for (final code in name.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.52, 0.48).toColor();
}

/// 来源 logo 上的文字：中文取 1 个字，英文/数字最多 3 个字符。
String sourceBadge(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  if (RegExp(r'^[0-9]').hasMatch(trimmed)) {
    return trimmed.length <= 3 ? trimmed : trimmed.substring(0, 3);
  }
  if (RegExp(r'^[A-Za-z]').hasMatch(trimmed)) {
    final word = trimmed.split(RegExp(r'\s+')).first;
    return word.length <= 2 ? word.toUpperCase() : word.substring(0, 1).toUpperCase();
  }
  return trimmed.substring(0, 1);
}

String two(int value) => value.toString().padLeft(2, '0');

String hm(DateTime time) => '${two(time.hour)}:${two(time.minute)}';

String clockLabel(DateTime? time) {
  if (time == null) return '尚未刷新';
  return hm(time.toLocal());
}

String updatedLabel(DateTime? time) {
  if (time == null) return '尚未更新';
  final local = time.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
  if (sameDay) return '${hm(local)} 更新';
  return '${local.month}月${local.day}日 ${hm(local)} 更新';
}

String relativeTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.inSeconds < 45) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays == 1) return '昨天 ${hm(time.toLocal())}';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${time.toLocal().month} 月 ${time.toLocal().day} 日';
}

String savedTimeLabel(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天 ${hm(local)}';
  if (diff == 1) return '昨天 ${hm(local)}';
  if (local.year == current.year) return '${local.month} 月 ${local.day} 日';
  return '${local.year} 年 ${local.month} 月 ${local.day} 日';
}

String refreshLine(DateTime? last, int success, int total) {
  if (last == null) return '尚未自动刷新';
  final base = '${savedTimeLabel(last)} · $success/$total 个来源成功';
  return base;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

String hostOf(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null || uri.host.isEmpty) return link;
  return uri.host.replaceFirst(RegExp(r'^www\.'), '');
}

/// 两行标题的稳定高度，避免滚动抖动（NFR-3）。
double feedTitleHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(14.5);
  return scale * 1.42 * 2 + 1;
}

double clampScale(double value) => math.max(0.9, math.min(1.4, value));
