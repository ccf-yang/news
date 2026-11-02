import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'pages/feed_page.dart';
import 'pages/settings_page.dart';
import 'pages/source_picker_page.dart';
import 'state/app_state.dart';
import 'widgets/source_sidebar.dart';

class PulseApp extends StatefulWidget {
  const PulseApp({super.key});

  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp> with WidgetsBindingObserver {
  final AppState app = AppState.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        app.pauseAutoRefresh();
        break;
      case AppLifecycleState.resumed:
        app.resumeAutoRefresh();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  Brightness get _effectiveBrightness {
    switch (app.themeSetting) {
      case 'light':
        return Brightness.light;
      case 'system':
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
      default:
        return Brightness.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final dark = _effectiveBrightness == Brightness.dark;
        return MaterialApp(
          title: 'Pulse',
          debugShowCheckedModeBanner: false,
          theme: pulseTheme(Brightness.light),
          darkTheme: pulseTheme(Brightness.dark),
          themeMode: app.themeMode,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(app.textScale),
              ),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark,
                // 导航器底层垫一层不透明底色，任何路由/转场都不会透出上一页。
                child: ColoredBox(
                  color: context.palette.bg,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          home: const MainShell(),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openSourcePicker() {
    _scaffoldKey.currentState?.closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        CupertinoPageRoute<void>(builder: (_) => const SourcePickerPage()),
      );
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -260) {
      _scaffoldKey.currentState?.openEndDrawer();
    } else if (velocity > 260) {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  double _drawerWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.82;
    return width > 340 ? 340 : width;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final feedTab = _index == 0;
    final sidebar = SourceSidebar(onManage: _openSourcePicker);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: p.bg,
      drawer: feedTab
          ? Drawer(
              width: _drawerWidth(context),
              backgroundColor: p.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
              ),
              child: sidebar,
            )
          : null,
      endDrawer: feedTab
          ? Drawer(
              width: _drawerWidth(context),
              backgroundColor: p.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
              ),
              child: SourceSidebar(onManage: _openSourcePicker),
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 热榜页左右滑都能拉出侧栏：左滑从右边出，右滑从左边出。
        onHorizontalDragEnd: feedTab ? _onHorizontalDragEnd : null,
        child: IndexedStack(
          index: _index,
          children: const [
            FeedPage(),
            SettingsPage(),
          ],
        ),
      ),
      bottomNavigationBar: _PulseTabBar(
        index: _index,
        onChanged: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _PulseTabBar extends StatelessWidget {
  const _PulseTabBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // 这里曾用 BackdropFilter 做毛玻璃；Impeller 下转场/返回时会把模糊快照
    // 留在屏幕上（残影），改用不透明底色，视觉差异很小但渲染稳定。
    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.line)),
      ),
      // 白色 Home 横条占掉底部安全区；把整块交给 SafeArea，按钮都在它上方。
      // 高度压到 56：点击区仍是半屏宽、整条高，但不再顶掉一大块内容。
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: _TabButton(
                  label: '热榜',
                  active: index == 0,
                  onTap: () => onChanged(0),
                ),
              ),
              Expanded(
                child: _TabButton(
                  label: '设置',
                  active: index == 1,
                  onTap: () => onChanged(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底栏只用汉字，不用图标：字形字体缺失时图标会变成方框问号。
///
/// 每个按钮占半屏宽、整条高，点文字旁边的空白也算命中，
/// 不再需要瞄准字本身。
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? p.accent.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active
                    ? p.accent.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? p.accent2 : p.text3,
                fontSize: 17,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
