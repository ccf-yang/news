import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  try {
    await AppState.instance.load();
  } catch (e) {
    debugPrint('状态载入失败，将以空数据启动: $e');
  }
  runApp(const PulseApp());
}
