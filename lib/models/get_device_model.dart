import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';


final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();

Future<String> getDeviceModel() async {
  if (Platform.isAndroid) {
    final androidInfo = await deviceInfoPlugin.androidInfo;
    return "${androidInfo.manufacturer} ${androidInfo.model}";
  } else if (Platform.isIOS) {
    final iosInfo = await deviceInfoPlugin.iosInfo;
    return iosInfo.utsname.machine ;
  } else {
    return "Unknown Device";
  }
}
