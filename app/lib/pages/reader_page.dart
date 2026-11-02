import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/article_body.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.article});

  final Article article;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

enum _ReaderMode { text, web }

class _ReaderPageState extends State<ReaderPage> {
  final AppState app = AppState.instance;
  final ArticleBodyService _bodyService = ArticleBodyService();

  String? _body;
  String? _error;
  bool _loading = false;

  _ReaderMode _mode = _ReaderMode.text;
  WebViewController? _web;
  String? _webNotice;
  String? _webError;
  bool _webLoading = true;
  bool _webLoaded = false;
  double _webProgress = 0;

  Article get article => widget.article;

  @override
  void initState() {
    super.initState();
    _body = app.articleBodies[article.id];
    _mode = app.forceWebMode ? _ReaderMode.web : _ReaderMode.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      app.markRead(article);
      if (_mode == _ReaderMode.web) {
        _ensureWebController();
      } else if (_body == null) {
        _loadBody();
      }
    });
  }

  @override
  void dispose() {
    _bodyService.close();
    super.dispose();
  }

  Future<void> _loadBody({
    bool force = false,
    bool allowWebFallback = true,
  }) async {
    if (_loading) return;
    if (!force && _body != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await _bodyService.fetch(article);
      app.cacheBody(article.id, text);
      if (mounted) setState(() => _body = text);
    } on ArticleBodyException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        // 403 / 验证页 / 无正文：不用让用户对着错误发呆，直接上浏览器内核。
        if (e.needsWeb && allowWebFallback) _switchToWeb(auto: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '正文加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchToWeb({bool auto = false}) {
    if (_mode == _ReaderMode.web) return;
    setState(() {
      _mode = _ReaderMode.web;
      if (auto) _webNotice = '站点限制了文字抓取，已改用网页模式';
    });
    _ensureWebController();
  }

  void _switchToText() {
    if (_mode == _ReaderMode.text) return;
    setState(() => _mode = _ReaderMode.text);
    if (_body == null && !_loading) {
      // 用户主动切回文字模式时不要再自动弹回网页，失败就显示错误卡片。
      _loadBody(force: true, allowWebFallback: false);
    }
  }

  void _ensureWebController() {
    if (_web != null) return;
    final uri = Uri.tryParse(article.link);
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _webLoading = false;
        _webError = '这条热榜没有可用的原文链接';
      });
      return;
    }
    final p = context.palette;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(p.bg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _webLoading = true;
                _webLoaded = false;
                _webProgress = 0;
                _webError = null;
              });
            }
          },
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _webProgress = progress / 100;
                if (progress >= 100) _webLoading = false;
                // 有些页面 onPageFinished 会被挂起的子资源拖很久。进度到 85%
                // 主体已经画出来了，就撤掉加载遮罩，别让转圈一直挡着。
                if (progress >= 85) _webLoaded = true;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _webLoading = false;
                _webLoaded = true;
              });
            }
          },
          onWebResourceError: (error) {
            // -999 取消、-1002 不支持的 scheme（页面里跳 zhihu:// 之类）都很常见，
            // 不能拿全屏错误盖住已经渲染出来的正文；页面已加载完成后也不再覆盖。
            if (_webLoaded ||
                !(error.isForMainFrame ?? true) ||
                error.errorCode == -999 ||
                error.errorCode == -1002) {
              return;
            }
            if (mounted) {
              setState(() {
                _webLoading = false;
                _webError = '网页加载失败（${error.errorCode}）';
              });
            }
          },
        ),
      )
      ..loadRequest(uri);
    _web = controller;
  }

  Future<void> _handleBack() async {
    if (_mode == _ReaderMode.web && _web != null && await _web!.canGoBack()) {
      await _web!.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openOriginal() async {
    final uri = Uri.tryParse(article.link);
    if (uri == null || !uri.hasScheme) {
      _snack('这条热榜没有可用的原文链接');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('无法打开系统浏览器');
    } catch (_) {
      _snack('无法打开系统浏览器');
    }
  }

  Future<void> _share() async {
    try {
      await Share.share(
        '${article.title}\n${article.link}',
        subject: article.title,
      );
    } catch (e) {
      _snack('分享失败：$e');
    }
  }

  void _toggleSaved() {
    final nowSaved = app.toggleSaved(article);
    HapticFeedback.mediumImpact();
    _snack(nowSaved ? '已收藏，可在「设置 → 我的收藏」查看' : '已取消收藏');
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: article.link));
    _snack('原文链接已复制');
  }

  void _showMore() {
    final p = context.palette;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(
          article.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.text, fontSize: 13.5),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _toggleSaved();
            },
            child: Text(app.isSaved(article.id) ? '取消收藏' : '收藏'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _share();
            },
            child: const Text('分享'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _copyLink();
            },
            child: const Text('复制原文链接'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _openOriginal();
            },
            child: const Text('用浏览器打开原文'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    final p = context.palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: p.surface3,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) {
              final web = _mode == _ReaderMode.web;
              return Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        IconCircleButton(
                          icon: CupertinoIcons.chevron_back,
                          onTap: _handleBack,
                        ),
                        Expanded(
                          child: Center(child: _SourcePill(article: article)),
                        ),
                        IconCircleButton(
                          icon: web
                              ? CupertinoIcons.doc_text
                              : CupertinoIcons.globe,
                          tooltip: web ? '切换到文字模式' : '切换到网页模式',
                          onTap: web ? _switchToText : _switchToWeb,
                          background: Colors.transparent,
                          border: false,
                        ),
                        IconCircleButton(
                          icon: CupertinoIcons.ellipsis,
                          onTap: _showMore,
                          background: Colors.transparent,
                          border: false,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  if (web && _webNotice != null)
                    NoticeBar(
                      text: _webNotice!,
                      icon: CupertinoIcons.globe,
                      actionLabel: '知道了',
                      onAction: () => setState(() => _webNotice = null),
                    ),
                  Expanded(
                    child: web
                        ? _WebBody(
                            controller: _web,
                            loading: _webLoading,
                            loaded: _webLoaded,
                            progress: _webProgress,
                            error: _webError,
                            onRetry: () {
                              setState(() {
                                _webError = null;
                                _webLoading = true;
                              });
                              _web?.reload();
                            },
                            onOpenExternal: _openOriginal,
                          )
                        : ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(22, 6, 22, 32),
                            children: [
                              Text(
                                article.title,
                                style: TextStyle(
                                  color: p.text,
                                  fontSize: 25,
                                  height: 1.36,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _Byline(article: article),
                              const SizedBox(height: 20),
                              _HighlightCard(article: article),
                              const SizedBox(height: 20),
                              if (_loading) _LoadingBody(),
                              if (!_loading && _body != null)
                                _BodyText(text: _body!),
                              if (!_loading && _body == null && _error != null)
                                _BodyError(
                                  message: _error!,
                                  onRetry: () => _loadBody(force: true),
                                  onWeb: _switchToWeb,
                                ),
                              const SizedBox(height: 28),
                              Center(
                                child: Text(
                                  '内容来自 ${hostOf(article.link)} · 观点归原作者所有',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: p.text3, fontSize: 11, height: 1.6),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: sourceColor(article.sourceName),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              article.sourceType.isEmpty
                  ? article.sourceName
                  : '${article.sourceName} · ${article.sourceType}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.text2, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Byline extends StatelessWidget {
  const _Byline({required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rankText = article.rank > 0 ? '热榜第 ${article.rank} 名' : '热榜';
    return Row(
      children: [
        Container(
          width: 17,
          height: 17,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sourceColor(article.sourceName),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            sourceBadge(article.sourceName),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${article.sourceName} · $rankText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text3, fontSize: 11.5),
          ),
        ),
        if (article.hotValue.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text('|', style: TextStyle(color: p.text3, fontSize: 11)),
          const SizedBox(width: 8),
          HeatPill(article.hotValue),
        ],
      ],
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = sourceColor(article.sourceName);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.18),
            p.surface2,
            p.blue.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Row(
        children: [
          SourceLogo(name: article.sourceName, size: 44, radius: 13),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.sourceName,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (article.category.isNotEmpty) article.category,
                    if (article.rank > 0) '第 ${article.rank} 名',
                    if (article.hotValue.isNotEmpty) '热度 ${article.hotValue}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text3, fontSize: 11.5, height: 1.5),
                ),
              ],
            ),
          ),
          Icon(CupertinoIcons.flame_fill, color: p.accent2, size: 22),
        ],
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  const _BodyText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              paragraph,
              style: TextStyle(
                color: p.text.withValues(alpha: 0.82),
                fontSize: 14.5,
                height: 1.85,
                letterSpacing: 0.1,
              ),
            ),
          ),
      ],
    );
  }
}

class _LoadingBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation<Color>(p.accent),
              ),
            ),
            const SizedBox(width: 9),
            Text('正在载入正文…', style: TextStyle(color: p.text3, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 11,
              width: i % 3 == 2 ? 220 : double.infinity,
              decoration: BoxDecoration(
                color: p.surface3.withValues(alpha: i.isEven ? 0.9 : 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

class _BodyError extends StatelessWidget {
  const _BodyError({
    required this.message,
    required this.onRetry,
    required this.onWeb,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onWeb;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.doc_text, size: 16, color: p.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: p.text2, fontSize: 12.5, height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GhostButton(
                label: '重试',
                icon: CupertinoIcons.arrow_clockwise,
                height: 38,
                onTap: onRetry,
              ),
              const SizedBox(width: 10),
              GhostButton(
                label: '网页模式',
                icon: CupertinoIcons.globe,
                height: 38,
                onTap: onWeb,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '部分站点禁止 App 直接抓正文，网页模式会用系统浏览器内核打开原文。',
            style: TextStyle(color: p.text3, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _WebBody extends StatelessWidget {
  const _WebBody({
    required this.controller,
    required this.loading,
    required this.loaded,
    required this.progress,
    required this.error,
    required this.onRetry,
    required this.onOpenExternal,
  });

  final WebViewController? controller;
  final bool loading;
  final bool loaded;
  final double progress;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // 初次渲染时 WKWebView 会先给出空白页，直接撤掉遮罩就会白闪一下。
    // 主体画出来（loaded）之前一直用不透明底色盖着，然后淡出。
    final cover = !loaded && error == null;
    return Stack(
      children: [
        if (controller != null)
          Positioned.fill(child: WebViewWidget(controller: controller!))
        else
          const SizedBox.expand(),
        if (loading && error == null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              value: progress > 0 ? progress : null,
              backgroundColor: p.line,
              valueColor: AlwaysStoppedAnimation<Color>(p.accent),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !cover,
            child: AnimatedOpacity(
              opacity: cover ? 1 : 0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              child: ColoredBox(
                color: p.bg,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (error != null)
          Positioned.fill(
            child: ColoredBox(
              color: p.bg,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.wifi_exclamationmark,
                          size: 30, color: p.text3),
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.text2, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '该站点可能在网页模式下也要求验证，可直接用系统浏览器打开。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.text3, fontSize: 11, height: 1.5),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GhostButton(
                            label: '重试',
                            icon: CupertinoIcons.arrow_clockwise,
                            height: 40,
                            onTap: onRetry,
                          ),
                          const SizedBox(width: 10),
                          GhostButton(
                            label: '系统浏览器',
                            icon: CupertinoIcons.arrow_up_right,
                            height: 40,
                            onTap: onOpenExternal,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
