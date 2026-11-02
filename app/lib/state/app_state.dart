import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/hot_api.dart';
import '../data/importer.dart';
import '../data/models.dart';

/// 新装时默认启用的 12 个来源（与设计稿「已启用 12」一致）。
const Set<String> kDefaultEnabledIds = {
  'WnBe01o371', // 微信
  'mproPpoq6O', // 知乎
  'KqndgxeLl9', // 微博
  'Jb0vmloB1G', // 百度
  '74KvxwokxM', // 哔哩哔哩
  'DpQvNABoNE', // 抖音
  'Q1Vd5Ko85R', // 36氪
  'Y2KeDGQdNP', // 少数派
  '5VaobgvAj1', // 虎嗅网
  'rYqoXz8dOD', // 掘金
  'rYqoXQ8vOD', // GitHub
  'toutiao', // 今日头条
};

const List<String> kChipSourceNames = ['微信', '知乎', '微博', '百度'];

class RefreshResult {
  const RefreshResult({required this.ok, this.message});

  final bool ok;
  final String? message;
}

/// 全局状态：来源、快照、收藏、已读、设置与自动刷新定时器。
///
/// 数据量很小（81 个源 + 每源最多 50 条），直接用 SharedPreferences 存 JSON，
/// 避免为了缓存引入数据库；首屏只做一次 prefs 读取，满足冷启动 1.5s 的目标。
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const String appVersion = '1.0.5';
  static const String appBuild = '6';
  static const Duration autoRefreshInterval = Duration(minutes: 30);

  static const _kSources = 'pulse.sources.v1';
  static const _kCategories = 'pulse.categories.v1';
  static const _kFeeds = 'pulse.feeds.v1';
  static const _kRead = 'pulse.read.v1';
  static const _kSaved = 'pulse.saved.v1';
  static const _kRecent = 'pulse.recent.v1';
  static const _kCurrent = 'pulse.current.v1';
  static const _kSettings = 'pulse.settings.v1';

  final HotApi _api = HotApi();

  late SharedPreferences _prefs;
  bool _loaded = false;

  final List<NewsSource> sources = [];
  final List<String> categories = [];
  final Map<String, FeedSnapshot> feeds = {};
  final Set<String> readIds = {};
  final Map<String, SavedEntry> saved = {};
  final List<String> recentSourceIds = [];
  final Set<String> refreshingIds = {};
  final Map<String, String> sourceErrors = {};
  final Map<String, String> articleBodies = {};

  String? currentSourceId;

  bool autoRefresh = false;
  bool forceWebMode = true;
  String themeSetting = 'dark'; // dark | light | system
  double textScale = 1.0;

  DateTime? lastRefreshAt;
  int lastRefreshSuccess = 0;
  int lastRefreshTotal = 0;

  Timer? _timer;
  bool _inForeground = true;
  bool _autoRunning = false;

  bool get loaded => _loaded;
  int get enabledCount => sources.where((s) => s.enabled).length;

  ThemeMode get themeMode {
    switch (themeSetting) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  String get themeLabel {
    switch (themeSetting) {
      case 'light':
        return '浅色';
      case 'system':
        return '跟随系统';
      default:
        return '深色';
    }
  }

  NewsSource? get currentSource {
    final id = currentSourceId;
    if (id == null) return null;
    return sourceById(id);
  }

  NewsSource? sourceById(String? id) {
    if (id == null) return null;
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  FeedSnapshot? feedFor(String sourceId) => feeds[sourceId];

  List<Article> articlesFor(String sourceId) => feeds[sourceId]?.items ?? const [];

  List<NewsSource> get enabledSources =>
      sources.where((s) => s.enabled).toList(growable: false);

  bool isRefreshing(String sourceId) => refreshingIds.contains(sourceId);

  String? errorFor(String sourceId) => sourceErrors[sourceId];

  bool isRead(String articleId) => readIds.contains(articleId);

  bool isSaved(String articleId) => saved.containsKey(articleId);

  /// 顶部来源 chips：常用四源，当前来源不在其中时挤掉最后一个。
  List<NewsSource> get chipSources {
    final enabled = enabledSources;
    final picks = <NewsSource>[];
    for (final name in kChipSourceNames) {
      for (final s in enabled) {
        if (s.name == name && !picks.contains(s)) {
          picks.add(s);
          break;
        }
      }
    }
    for (final s in enabled) {
      if (picks.length >= 4) break;
      if (!picks.contains(s)) picks.add(s);
    }
    final current = currentSource;
    if (current != null && !picks.contains(current)) {
      if (picks.length >= 4) picks.removeLast();
      picks.add(current);
    }
    return picks;
  }

  List<NewsSource> recentSources() {
    final result = <NewsSource>[];
    for (final id in recentSourceIds) {
      final s = sourceById(id);
      if (s != null) result.add(s);
    }
    return result;
  }

  Article? articleById(String id) {
    final entry = saved[id];
    if (entry != null) return entry.article;
    for (final feed in feeds.values) {
      for (final a in feed.items) {
        if (a.id == id) return a;
      }
    }
    return null;
  }

  List<SavedEntry> get savedEntries {
    final list = saved.values.toList();
    list.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return list;
  }

  int get savedSourceCount => saved.values.map((e) => e.article.sourceId).toSet().length;

  /// 缓存占用：热榜快照 + 收藏 + 已读，仅用于设置页的粗略展示。
  int get cacheBytes {
    var total = 0;
    for (final f in feeds.values) {
      total += jsonEncode(f.toJson()).length;
    }
    for (final e in saved.values) {
      total += jsonEncode(e.toJson()).length;
    }
    total += readIds.fold<int>(0, (sum, id) => sum + id.length);
    return total;
  }

  // ---------------------------------------------------------------- load / seed

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();

    sources
      ..clear()
      ..addAll(_decodeSources(_prefs.getString(_kSources)));
    categories
      ..clear()
      ..addAll(_decodeStrings(_prefs.getString(_kCategories)));
    feeds
      ..clear()
      ..addAll(_decodeFeeds(_prefs.getString(_kFeeds)));
    readIds
      ..clear()
      ..addAll(_decodeStrings(_prefs.getString(_kRead)));
    saved
      ..clear()
      ..addAll(_decodeSaved(_prefs.getString(_kSaved)));
    recentSourceIds
      ..clear()
      ..addAll(_decodeStrings(_prefs.getString(_kRecent)).take(8));
    currentSourceId = _prefs.getString(_kCurrent);

    final settings = _decodeMap(_prefs.getString(_kSettings));
    autoRefresh = settings['autoRefresh'] == true;
    // 1.0.4 起网页模式默认开启。老版本可能把 false 写进了设置，
    // 用一次性标记把默认值迁移过来；用户之后主动关掉会带上标记，不再被覆盖。
    final webDefaultApplied = settings['webDefaultOnV1'] == true;
    forceWebMode =
        webDefaultApplied ? settings['forceWebMode'] != false : true;
    themeSetting = readString(settings['theme']) ?? 'dark';
    textScale = (settings['textScale'] is num)
        ? (settings['textScale'] as num).toDouble().clamp(0.9, 1.4)
        : 1.0;
    lastRefreshAt = DateTime.tryParse(readString(settings['lastRefreshAt']) ?? '');
    lastRefreshSuccess = readInt(settings['lastRefreshSuccess']);
    lastRefreshTotal = readInt(settings['lastRefreshTotal']);

    if (sources.isEmpty) {
      await _seedBuiltIn();
    }

    if (sourceById(currentSourceId) == null) {
      currentSourceId = _defaultCurrentId();
    }
    if (categories.isEmpty) {
      for (final s in sources) {
        if (!categories.contains(s.category)) categories.add(s.category);
      }
    }

    _loaded = true;
    if (autoRefresh) _startTimer();
    notifyListeners();
  }

  String? _defaultCurrentId() {
    for (final name in kChipSourceNames) {
      for (final s in sources) {
        if (s.name == name && s.enabled) return s.id;
      }
    }
    for (final s in sources) {
      if (s.enabled) return s.id;
    }
    return sources.isEmpty ? null : sources.first.id;
  }

  /// 首次启动：内置 81 个来源 + 微信 30 条示例快照，保证离线也能看到内容。
  Future<void> _seedBuiltIn() async {
    try {
      final sourceText =
          await rootBundle.loadString('assets/data/hot-sources.json');
      final feedText = await rootBundle.loadString('assets/data/sample-news.json');

      final sourceReport = PulseImporter.parse(
        sourceText,
        fileName: 'hot-sources.json',
      );
      if (sourceReport.usable) {
        for (final s in sourceReport.sources) {
          sources.add(s.copyWith(enabled: kDefaultEnabledIds.contains(s.id)));
        }
        categories
          ..clear()
          ..addAll(sourceReport.categories);
      }

      final feedReport = PulseImporter.parse(feedText, fileName: 'sample-news.json');
      if (feedReport.usable) {
        final id = feedReport.sourceId!;
        var source = sourceById(id);
        if (source == null) {
          source = NewsSource(
            id: id,
            name: feedReport.sourceName ?? '微信',
            type: feedReport.sourceType ?? '',
            category: feedReport.category ?? '综合',
            icon: '',
            url: 'https://base.itab.link/api/top/list?lang=cn&id=$id&size=50',
            enabled: true,
          );
          sources.add(source);
        } else if (!source.enabled) {
          _replaceSource(source.copyWith(enabled: true));
          source = sourceById(id);
        }
        feeds[id] = FeedSnapshot(
          sourceId: id,
          fetchedAt: feedReport.fetchedAt ?? DateTime.now(),
          items: feedReport.articles,
        );
      }

      currentSourceId = sourceById('WnBe01o371') != null
          ? 'WnBe01o371'
          : _defaultCurrentId();

      await _persistSources();
      await _persistFeeds();
    } catch (e) {
      debugPrint('内置数据载入失败: $e');
    }
  }

  // ---------------------------------------------------------------- persistence

  List<NewsSource> _decodeSources(String? raw) {
    final list = _decodeList(raw);
    final result = <NewsSource>[];
    for (final item in list) {
      if (item is Map) {
        final source = NewsSource.fromJson(Map<String, dynamic>.from(item));
        if (source.id.isNotEmpty) result.add(source);
      }
    }
    return result;
  }

  Map<String, FeedSnapshot> _decodeFeeds(String? raw) {
    final map = _decodeMap(raw);
    final result = <String, FeedSnapshot>{};
    map.forEach((key, value) {
      if (value is Map) {
        final snapshot = FeedSnapshot.fromJson(Map<String, dynamic>.from(value));
        result[key] = FeedSnapshot(
          sourceId: key,
          fetchedAt: snapshot.fetchedAt,
          items: snapshot.items,
        );
      }
    });
    return result;
  }

  Map<String, SavedEntry> _decodeSaved(String? raw) {
    final map = <String, SavedEntry>{};
    for (final item in _decodeList(raw)) {
      if (item is Map) {
        final entry = SavedEntry.fromJson(Map<String, dynamic>.from(item));
        if (entry.article.id.isNotEmpty) map[entry.article.id] = entry;
      }
    }
    return map;
  }

  List<String> _decodeStrings(String? raw) {
    final result = <String>[];
    for (final item in _decodeList(raw)) {
      final s = readString(item);
      if (s != null) result.add(s);
    }
    return result;
  }

  List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _persistSources() async {
    await _prefs.setString(
      _kSources,
      jsonEncode(sources.map((e) => e.toJson()).toList()),
    );
    await _prefs.setString(_kCategories, jsonEncode(categories));
  }

  Future<void> _persistFeeds() async {
    final map = <String, dynamic>{};
    feeds.forEach((key, value) => map[key] = value.toJson());
    await _prefs.setString(_kFeeds, jsonEncode(map));
  }

  Future<void> _persistSaved() async {
    await _prefs.setString(
      _kSaved,
      jsonEncode(saved.values.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistRead() async {
    await _prefs.setString(_kRead, jsonEncode(readIds.toList()));
  }

  Future<void> _persistRecent() async {
    await _prefs.setString(_kRecent, jsonEncode(recentSourceIds));
  }

  Future<void> _persistCurrent() async {
    final id = currentSourceId;
    if (id == null) {
      await _prefs.remove(_kCurrent);
    } else {
      await _prefs.setString(_kCurrent, id);
    }
  }

  Future<void> _persistSettings() async {
    await _prefs.setString(
      _kSettings,
      jsonEncode({
        'autoRefresh': autoRefresh,
        'forceWebMode': forceWebMode,
        'webDefaultOnV1': true,
        'theme': themeSetting,
        'textScale': textScale,
        'lastRefreshAt': lastRefreshAt?.toIso8601String(),
        'lastRefreshSuccess': lastRefreshSuccess,
        'lastRefreshTotal': lastRefreshTotal,
      }),
    );
  }

  // ---------------------------------------------------------------- selection

  void selectSource(String id, {bool recordRecent = true}) {
    if (sourceById(id) == null) return;
    currentSourceId = id;
    if (recordRecent) {
      recentSourceIds.remove(id);
      recentSourceIds.insert(0, id);
      if (recentSourceIds.length > 8) {
        recentSourceIds.removeRange(8, recentSourceIds.length);
      }
      _persistRecent();
    }
    _persistCurrent();
    notifyListeners();
  }

  void setSourceEnabled(String id, bool enabled) {
    final index = sources.indexWhere((s) => s.id == id);
    if (index < 0) return;
    sources[index] = sources[index].copyWith(enabled: enabled);
    if (enabled && currentSourceId == null) currentSourceId = id;
    _persistSources();
    notifyListeners();
  }

  void _replaceSource(NewsSource source) {
    final index = sources.indexWhere((s) => s.id == source.id);
    if (index >= 0) {
      sources[index] = source;
    } else {
      sources.add(source);
    }
  }

  // ---------------------------------------------------------------- read / save

  void markRead(Article article) {
    if (readIds.add(article.id)) {
      _persistRead();
      notifyListeners();
    }
  }

  bool toggleSaved(Article article) {
    final nowSaved = !saved.containsKey(article.id);
    if (nowSaved) {
      saved[article.id] = SavedEntry(article: article, savedAt: DateTime.now());
    } else {
      saved.remove(article.id);
    }
    _persistSaved();
    notifyListeners();
    return nowSaved;
  }

  Future<void> removeSaved(String articleId) async {
    if (saved.remove(articleId) != null) {
      await _persistSaved();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- refresh

  Future<RefreshResult> refreshSource(NewsSource source) async {
    if (refreshingIds.contains(source.id)) {
      return const RefreshResult(ok: false, message: '正在刷新');
    }
    refreshingIds.add(source.id);
    sourceErrors.remove(source.id);
    notifyListeners();

    try {
      final items = await _api.fetch(source);
      feeds[source.id] = FeedSnapshot(
        sourceId: source.id,
        fetchedAt: DateTime.now(),
        items: items,
      );
      await _persistFeeds();
      return const RefreshResult(ok: true);
    } on HotFetchException catch (e) {
      sourceErrors[source.id] = e.message;
      return RefreshResult(ok: false, message: e.message);
    } catch (e) {
      sourceErrors[source.id] = '刷新失败：$e';
      return RefreshResult(ok: false, message: '刷新失败：$e');
    } finally {
      refreshingIds.remove(source.id);
      notifyListeners();
    }
  }

  Future<RefreshResult> refreshCurrent() async {
    final source = currentSource;
    if (source == null) {
      return const RefreshResult(ok: false, message: '还没有可刷新的来源');
    }
    return refreshSource(source);
  }

  /// 仅刷新已启用来源（FR-6.2），最多 3 路并发。
  Future<int> refreshEnabledSources({bool fromAuto = false}) async {
    if (_autoRunning) return lastRefreshSuccess;
    final targets = enabledSources;
    if (targets.isEmpty) {
      if (fromAuto) {
        lastRefreshAt = DateTime.now();
        lastRefreshSuccess = 0;
        lastRefreshTotal = 0;
        await _persistSettings();
        notifyListeners();
      }
      return 0;
    }

    _autoRunning = true;
    final queue = List<NewsSource>.from(targets);
    var success = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final source = queue.removeAt(0);
        final result = await refreshSource(source);
        if (result.ok) success++;
      }
    }

    try {
      await Future.wait(
        List.generate(math.min(3, queue.length), (_) => worker()),
      );
      lastRefreshAt = DateTime.now();
      lastRefreshSuccess = success;
      lastRefreshTotal = targets.length;
      await _persistSettings();
      return success;
    } finally {
      _autoRunning = false;
      notifyListeners();
    }
  }

  void setAutoRefresh(bool value) {
    if (autoRefresh == value) return;
    autoRefresh = value;
    if (value) {
      _startTimer();
    } else {
      _timer?.cancel();
      _timer = null;
    }
    _persistSettings();
    notifyListeners();
  }

  void setForceWebMode(bool value) {
    forceWebMode = value;
    _persistSettings();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(autoRefreshInterval, (_) {
      if (!_inForeground || !autoRefresh) return;
      refreshEnabledSources(fromAuto: true);
    });
  }

  /// App 进入后台时暂停；回到前台立即补一次（FR-6.3）。
  void pauseAutoRefresh() {
    _inForeground = false;
    _timer?.cancel();
    _timer = null;
  }

  void resumeAutoRefresh() {
    if (_inForeground) return;
    _inForeground = true;
    if (!autoRefresh) return;
    _startTimer();
    refreshEnabledSources(fromAuto: true);
  }

  // ---------------------------------------------------------------- settings

  void setTheme(String value) {
    if (!const {'dark', 'light', 'system'}.contains(value)) return;
    themeSetting = value;
    _persistSettings();
    notifyListeners();
  }

  void cycleTheme() {
    const order = ['dark', 'light', 'system'];
    final index = order.indexOf(themeSetting);
    setTheme(order[(index + 1) % order.length]);
  }

  void setTextScale(double value) {
    textScale = value.clamp(0.9, 1.4);
    _persistSettings();
    notifyListeners();
  }

  void cycleTextScale() {
    const order = [0.95, 1.0, 1.15, 1.3];
    final index = order.indexOf(textScale);
    setTextScale(order[(index + 1) % order.length]);
  }

  String get textScaleLabel {
    if (textScale < 0.98) return '小';
    if (textScale < 1.08) return '标准';
    if (textScale < 1.22) return '大';
    return '特大';
  }

  Future<void> clearCache() async {
    feeds.clear();
    sourceErrors.clear();
    articleBodies.clear();
    await _persistFeeds();
    notifyListeners();
  }

  void cacheBody(String articleId, String body) {
    if (articleBodies.length > 30) articleBodies.clear();
    articleBodies[articleId] = body;
  }

  // ---------------------------------------------------------------- import / export

  /// 返回实际写入的条目数。跳过坏条目在 [ImportReport.issues] 里已有记录。
  Future<int> importReport(ImportReport report) async {
    if (!report.usable) return 0;
    if (report.kind == 'sources') {
      for (final s in report.sources) {
        final old = sourceById(s.id);
        if (old != null) {
          _replaceSource(
            s.copyWith(enabled: old.enabled),
          );
        } else {
          _replaceSource(
            s.copyWith(enabled: kDefaultEnabledIds.contains(s.id)),
          );
        }
      }
      for (final c in report.categories) {
        if (!categories.contains(c)) categories.add(c);
      }
      if (sourceById(currentSourceId) == null) {
        currentSourceId = _defaultCurrentId();
      }
      await _persistSources();
      await _persistCurrent();
      notifyListeners();
      return report.sources.length;
    }

    final id = report.sourceId!;
    final existing = sourceById(id);
    if (existing == null) {
      _replaceSource(
        NewsSource(
          id: id,
          name: report.sourceName ?? id,
          type: report.sourceType ?? '',
          category: report.category ?? '未分类',
          icon: '',
          url: 'https://base.itab.link/api/top/list?lang=cn&id=$id&size=50',
          enabled: true,
        ),
      );
    }
    feeds[id] = FeedSnapshot(
      sourceId: id,
      fetchedAt: report.fetchedAt ?? DateTime.now(),
      items: report.articles,
    );
    if (sourceById(currentSourceId) == null) currentSourceId = id;
    await _persistFeeds();
    await _persistSources();
    await _persistCurrent();
    notifyListeners();
    return report.articles.length;
  }

  Map<String, dynamic> buildExport() {
    final feedMap = <String, dynamic>{};
    feeds.forEach((key, value) => feedMap[key] = value.toJson());
    return {
      'version': 1,
      'kind': 'pulse-export',
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'Pulse $appVersion ($appBuild)',
      'settings': {
        'autoRefresh': autoRefresh,
        'forceWebMode': forceWebMode,
        'theme': themeSetting,
        'textScale': textScale,
        'lastRefreshAt': lastRefreshAt?.toIso8601String(),
        'lastRefreshSuccess': lastRefreshSuccess,
        'lastRefreshTotal': lastRefreshTotal,
      },
      'sources': sources.map((e) => e.toJson()).toList(),
      'categories': categories,
      'feeds': feedMap,
      'read': readIds.toList(),
      'saved': saved.values.map((e) => e.toJson()).toList(),
      'recent': recentSourceIds,
      'current': currentSourceId,
    };
  }

  String buildExportJson() =>
      const JsonEncoder.withIndent('  ').convert(buildExport());

  @override
  void dispose() {
    _timer?.cancel();
    _api.close();
    super.dispose();
  }
}
