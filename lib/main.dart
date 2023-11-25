// https://github.com/user154lt/ELK-BLEDOM-Command-Util -- command list
// https://pub.dev/packages/system_tray                 -- system tray
// https://pub.dev/packages/screen_brightness           -- screen brightness
// https://pub.dev/packages/bluetooth_low_energy        -- BLE for Mac

import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:backlight_brightness_ble_controller/brightness.dart';
import 'package:get/get.dart';
import 'package:win_ble/win_ble.dart';
import 'package:win_ble/win_file.dart';

BleDevice? device;
RxString status = RxString("Disconnected");
RxList<String> services = List<String>.empty(growable: true).obs;

void main() async {
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription? scanStream;
  StreamSubscription? connectionStream;
  StreamSubscription? bleStateStream;
  BleState bleState = BleState.Unknown;
  final BrightnessController brightnessController = Get.put(BrightnessController());

  Timer? restart;

  void initialize() async =>
      await WinBle.initialize(serverPath: await WinServer.path, enableLog: true)
          .then((value) => WinBle.startScanning());

  Widget kButton(String txt, onTap) {
    device = null;
    return ElevatedButton(
        onPressed: onTap,
        child: Text(txt, style: const TextStyle(fontSize: 20)));
  }

  @override
  void initState() {
    initialize();
    connectionStream = WinBle.connectionStream.listen((event) {
      log("Connection Event : $event");
      if (device != null &&
          event["device"] == device!.address &&
          event["connected"] == false) {
        status.value = "Disconnected";
        device = null;
      }
    });

    scanStream = WinBle.scanStream.listen((event) async {
      if (await connectionProcess(event)) WinBle.stopScanning();
    });

    bleStateStream =
        WinBle.bleState.listen((BleState state) => bleState = state);

    restart = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (device == null) {
        WinBle.startScanning();
        Future.delayed(
            const Duration(seconds: 10), () => WinBle.stopScanning());
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    WinBle.stopScanning();
    restart?.cancel();
    scanStream?.cancel();
    connectionStream?.cancel();
    bleStateStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Obx(() => Text(status.value))),
    );
  }
}

Future<bool> connectionProcess(BleDevice event) async {
  if (device == null) {
    if (event.name.isNotEmpty && event.name.contains("ELK-BLEDOM")) {
      device = event;
      status.value = "Device has been found";
      await Future.delayed(Duration(seconds: 1));
      if (await connect(device!.address)) {
        status.value = "Device has been connected";
        await Future.delayed(Duration(seconds: 1));
        if (await WinBle.isPaired(device!.address) ||
            await pair(device!.address)) {
          status.value = "Device has been paired";
          await Future.delayed(Duration(seconds: 1));
          services = RxList(await discoverServices(device!.address));
          const String targetS = "0000fff0-0000-1000-8000-00805f9b34fb";
          if (services.toList().contains(targetS)) {
            status.value = "Device has target service";
            await Future.delayed(Duration(seconds: 1));
            var ch = await discoverCharacteristic(device!.address, targetS);
            ch = await discoverCharacteristic(device!.address, targetS);
            const String targetC = "0000fff3-0000-1000-8000-00805f9b34fb";
            if (ch.map((e) => e.uuid.toLowerCase()).contains(targetC)) {
              status.value = "Device has target characteristic";
              await Future.delayed(Duration(seconds: 1));
              if ((await readCharacteristic(device!.address, targetS, targetC))
                  .isNotEmpty) {
                status.value = "Device Ready!";
                return true;
              }
            }
          }
        }
      }
      disconnect(device!.address);
      status.value = "Connection Failed";
      device = null;
    }
    return false;
  }
  return true;
}

Future<List<String>> discoverServices(String address) async {
  List<String> data = [];
  try {
    data = await WinBle.discoverServices(address);
    log("DiscoverService : $data");
  } catch (e) {
    log("DiscoverServiceError : $e");
  }
  return data;
}

Future<bool> connect(String address) async {
  try {
    await WinBle.connect(address);
    log("Connected");
    return true;
  } catch (e) {
    log("ConnectError : $e");
    return false;
  }
}

Future<bool> pair(String address) async {
  try {
    await WinBle.pair(address);
    log("Paired Successfully");
    return true;
  } catch (e) {
    log("PairError : $e");
    return false;
  }
}

Future<bool> unPair(String address) async {
  try {
    await WinBle.unPair(address);
    log("UnPaired Successfully");
    return true;
  } catch (e) {
    log("UnPairError : $e");
    return false;
  }
}

Future<bool> disconnect(String address) async {
  try {
    if (await WinBle.isPaired(address)) await WinBle.unPair(address);
    if (!await WinBle.isPaired(address)) log("UnPaired Successfully");
    await WinBle.disconnect(address).then((e) => log("Disconnected"));
    return true;
  } catch (e) {
    log(e.toString());
    return false;
  }
}

Future<List<BleCharacteristic>> discoverCharacteristic(
    String address, String serviceID) async {
  List<BleCharacteristic> bleChar = [];
  try {
    bleChar = await WinBle.discoverCharacteristics(
        address: address, serviceId: serviceID);
    log(bleChar.toString());
    log(bleChar.map((e) => e.toJson()).toString());
  } catch (e) {
    log("DiscoverCharError : $e");
  }
  return bleChar;
}

Future<List<int>> readCharacteristic(address, serviceID, charID) async {
  try {
    List<int> data = await WinBle.read(
        address: address, serviceId: serviceID, characteristicId: charID);
    log(String.fromCharCodes(data));
    return data;
  } catch (e) {
    log("ReadCharError : $e");
    return [];
  }
}

void writeCharacteristic(String address, String serviceID, String charID,
    String dataTxt, bool writeWithResponse) async {
  try {
    Uint8List data = Uint8List.fromList(dataTxt
        .replaceAll("[", "")
        .replaceAll("]", "")
        .split(",")
        .map((e) => int.parse(e.trim()))
        .toList());
    await WinBle.write(
        address: address,
        service: serviceID,
        characteristic: charID,
        data: data,
        writeWithResponse: writeWithResponse);
  } catch (e) {
    log("writeCharError : $e");
  }
}
