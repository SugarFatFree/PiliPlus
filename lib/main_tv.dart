import 'dart:io';

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/pages_tv/tv_app.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/json_file_handler.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<void> _initAppPath() async {
  appSupportDirPath = (await getApplicationSupportDirectory()).path;
}

Future<void> _initTmpPath() async {
  tmpDirPath = (await getTemporaryDirectory()).path;
}

Future<void> _initDownPath() async {
  final externalStorageDirPath = (await getExternalStorageDirectory())?.path;
  if (externalStorageDirPath != null) {
    downloadPath = path.join(externalStorageDirPath, PathUtils.downloadDir);
  } else {
    downloadPath = defDownloadPath;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  PlatformUtils.isTV = true;

  await _initAppPath();
  try {
    await GStorage.init();
  } catch (e) {
    await Utils.copyText(e.toString());
    if (kDebugMode) debugPrint('GStorage init error: $e');
    exit(0);
  }

  // TV 默认画质 1080P，默认关闭硬件解码（如果用户没有手动设置过）
  if (!GStorage.setting.containsKey(SettingBoxKey.defaultVideoQa)) {
    GStorage.setting.put(SettingBoxKey.defaultVideoQa, 80); // 1080P
  }
  if (!GStorage.setting.containsKey(SettingBoxKey.enableHA)) {
    GStorage.setting.put(SettingBoxKey.enableHA, false);
  }

  await Future.wait([
    _initDownPath(),
    _initTmpPath(),
    DeviceInfoPlugin().androidInfo.then((info) {
      DeviceUtils.sdkInt = info.version.sdkInt;
    }),
  ]);

  Get.lazyPut(AccountService.new);

  HttpOverrides.global = _TVHttpOverrides();
  CacheManager.autoClearCache();

  await setupServiceLocator();

  Request();
  Request.setCookie();
  RequestUtils.syncHistoryStatus();

  SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);

  // TV immersive mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  if (Pref.dynamicColor) {
    await TVApp.initPlatformState();
  }

  // 接收 Android 转发的 UP/DOWN 按键
  // 用独立 channel 'PiliPlus.tv'，与 PlPlayerController 共享的 'PiliPlus' channel 解耦，
  // 防止视频 dispose 时 Utils.channel.setMethodCallHandler(null) 把我们的 handler 清掉
  const MethodChannel('PiliPlus.tv').setMethodCallHandler((call) async {
    if (call.method == 'tvKey') {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      final action = args['action'] as String;
      final isRepeat = args['isRepeat'] as bool;
      final cb = TVKeyHandler.instance?.callback;
      if (cb != null) {
        cb(key, action, isRepeat);
      } else if (action == 'down') {
        final direction = key == 'arrowUp'
            ? TraversalDirection.up
            : TraversalDirection.down;
        FocusManager.instance.primaryFocus?.focusInDirection(direction);
      }
    }
  });

  if (Pref.enableLog) {
    final customParameters = {
      'BuildConfig':
          '\nBuild Time: ${DateFormatUtils.format(BuildConfig.buildTime, format: DateFormatUtils.longFormatDs)}\n'
          'Commit Hash: ${BuildConfig.commitHash}',
    };
    final fileHandler = await JsonFileHandler.init();
    final Catcher2Options debugConfig = Catcher2Options(
      SilentReportMode(),
      [
        ?fileHandler,
        ConsoleHandler(
          enableDeviceParameters: false,
          enableApplicationParameters: false,
          enableCustomParameters: true,
        ),
      ],
      customParameters: customParameters,
    );
    final Catcher2Options releaseConfig = Catcher2Options(
      SilentReportMode(),
      [?fileHandler, ConsoleHandler(enableCustomParameters: true)],
      customParameters: customParameters,
    );
    Catcher2(
      debugConfig: debugConfig,
      releaseConfig: releaseConfig,
      rootWidget: const TVApp(),
    );
  } else {
    runApp(const TVApp());
  }
}

class _TVHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (kDebugMode || Pref.badCertificateCallback) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }
}
