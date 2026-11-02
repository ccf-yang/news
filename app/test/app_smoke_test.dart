import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/app.dart';
import 'package:pulse/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('冷启动进入热榜并切换到设置页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    await AppState.instance.load();

    await tester.pumpWidget(const PulseApp());
    await tester.pump(const Duration(milliseconds: 400));

    // 内置示例让首页首帧就有内容，不需要网络。
    expect(find.text('热榜'), findsWidgets);
    expect(find.text('微信'), findsWidgets);
    expect(find.textContaining('苹果最终确认'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('设置').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('自动刷新'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
