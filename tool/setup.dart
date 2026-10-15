// À lancer depuis la racine : dart tool/setup.dart
// Génère les plateformes avec VOTRE Flutter, puis ajoute les autorisations BLE.
import 'dart:io';

Future<void> run(String executable, List<String> args) async {
  final process = await Process.start(
    executable,
    args,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  if (await process.exitCode != 0) throw StateError('$executable a échoué.');
}

void copyFolder(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is Directory)
      copyFolder(entity, Directory('${destination.path}/$name'));
    if (entity is File) entity.copySync('${destination.path}/$name');
  }
}

Future<void> main() async {
  if (!File('lib/main.dart').existsSync() ||
      !File('pubspec.yaml').existsSync()) {
    stderr.writeln('Ouvrez un terminal dans le dossier luma_flutter.');
    exitCode = 1;
    return;
  }
  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  const seed = '.platform_seed';
  try {
    final missing = [
      'android',
      'ios',
      'web',
    ].where((p) => !Directory(p).existsSync()).toList();
    if (missing.isNotEmpty) {
      await run(flutter, [
        'create',
        '--no-pub',
        '--platforms',
        missing.join(','),
        '--org',
        'fr.projetled',
        '--project-name',
        'luma',
        seed,
      ]);
      for (final p in missing) {
        copyFolder(Directory('$seed/$p'), Directory(p));
      }
      if (!File('.metadata').existsSync() &&
          File('$seed/.metadata').existsSync()) {
        File('$seed/.metadata').copySync('.metadata');
      }
    }
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    var xml = manifest.readAsStringSync();
    if (!xml.contains('android.permission.BLUETOOTH_SCAN')) {
      xml = xml.replaceFirst('<application', '''
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <application''');
    }
    xml = xml.replaceAll('android:label="luma"', 'android:label="Luma"');
    manifest.writeAsStringSync(xml);
    final info = File('ios/Runner/Info.plist');
    var plist = info.readAsStringSync();
    if (!plist.contains('NSBluetoothAlwaysUsageDescription')) {
      plist = plist.replaceFirst(
        '<dict>',
        '''<dict>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Luma utilise le Bluetooth pour envoyer vos messages à votre panneau LED.</string>''',
      );
      info.writeAsStringSync(plist);
    }
    await run(flutter, ['pub', 'get']);
    stdout.writeln(
      'Prêt. Ouvrez ce dossier dans Android Studio, puis lancez flutter run.',
    );
    stdout.writeln(
      'Sur Mac : même dossier, flutter pub get puis flutter run sur iPhone.',
    );
  } catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}
