import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Pulse 的深色 / 浅色色板。深色是默认外观（NFR-1）。
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accent2,
    required this.blue,
    required this.green,
    required this.glowA,
    required this.glowB,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accent2;
  final Color blue;
  final Color green;
  final Color glowA;
  final Color glowB;

  static const dark = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF050506),
    surface: Color(0xFF0E0E12),
    surface2: Color(0xFF16161D),
    surface3: Color(0xFF1E1E27),
    line: Color(0x12FFFFFF),
    text: Color(0xFFF5F5F7),
    text2: Color(0x9EF5F5F7),
    text3: Color(0x5CF5F5F7),
    accent: Color(0xFFFF5C38),
    accent2: Color(0xFFFF9147),
    blue: Color(0xFF5B8CFF),
    green: Color(0xFF3DD68C),
    glowA: Color(0x29FF5C38),
    glowB: Color(0x245B8CFF),
  );

  static const light = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFF6F5F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F0F4),
    surface3: Color(0xFFE7E5EC),
    line: Color(0x12000000),
    text: Color(0xFF111114),
    text2: Color(0x9E111114),
    text3: Color(0x5C111114),
    accent: Color(0xFFEA4A26),
    accent2: Color(0xFFF07A34),
    blue: Color(0xFF3D6FEA),
    green: Color(0xFF1EAE68),
    glowA: Color(0x1FEA4A26),
    glowB: Color(0x1A3D6FEA),
  );

  LinearGradient get accentGradient => LinearGradient(
        colors: [accent, accent2],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  @override
  Palette copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? line,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accent2,
    Color? blue,
    Color? green,
    Color? glowA,
    Color? glowB,
  }) {
    return Palette(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      line: line ?? this.line,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      blue: blue ?? this.blue,
      green: green ?? this.green,
      glowA: glowA ?? this.glowA,
      glowB: glowB ?? this.glowB,
    );
  }

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return Palette(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surface2: mix(surface2, other.surface2),
      surface3: mix(surface3, other.surface3),
      line: mix(line, other.line),
      text: mix(text, other.text),
      text2: mix(text2, other.text2),
      text3: mix(text3, other.text3),
      accent: mix(accent, other.accent),
      accent2: mix(accent2, other.accent2),
      blue: mix(blue, other.blue),
      green: mix(green, other.green),
      glowA: mix(glowA, other.glowA),
      glowB: mix(glowB, other.glowB),
    );
  }
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.dark;
}

ThemeData pulseTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: brightness,
  ).copyWith(
    primary: p.accent,
    secondary: p.accent2,
    surface: p.surface,
    error: const Color(0xFFFF453A),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    platform: TargetPlatform.iOS,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    primaryTextTheme: base.primaryTextTheme.apply(bodyColor: p.text),
    dividerColor: p.line,
    extensions: <ThemeExtension<dynamic>>[p],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: p.accent,
      scaffoldBackgroundColor: p.bg,
      barBackgroundColor: p.bg,
      textTheme: CupertinoTextThemeData(
        primaryColor: p.accent,
        textStyle: TextStyle(color: p.text, fontSize: 15),
      ),
    ),
  );
}

/// 全屏背景：顶部两团环境光 + 底色。
class PulseBackground extends StatelessWidget {
  const PulseBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // 渐变终点必须是实色：带 alpha 的全屏渐变会让页面在路由转场里被当成
    // 半透明图层，iOS 上容易看到上一页的残影。
    return Material(
      color: p.bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.bg,
          gradient: RadialGradient(
            center: const Alignment(0.85, -0.95),
            radius: 1.15,
            colors: [p.glowA, p.bg],
            stops: const [0, 0.62],
          ),
        ),
        child: child,
      ),
    );
  }
}
