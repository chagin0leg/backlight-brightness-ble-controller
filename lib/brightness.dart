import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:get/get.dart';

class BrightnessController extends GetxController {
  Rx<int?> value = null.obs;
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _timer = Timer.periodic(const Duration(seconds: 1),
        (t) async => value = (await _getMonitorBrightness()).obs);
  }

  Future<int?> _getMonitorBrightness() async {
    try {
      final process = await Process.start(
        'powershell',
        [
          '(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightness).CurrentBrightness'
        ],
      );
      final output = await process.stdout.transform(utf8.decoder).join();
      final brightness = int.tryParse(output.trim());
      if (brightness == null) throw ('Error parsing the received value');
      return brightness;
    } catch (e) {
      log('Error getting monitor brightness: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
