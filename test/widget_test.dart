import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/main.dart';

void main() {
  testWidgets('accueil mobile et parcours de démonstration', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LumaApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Luma rouge'), findsOneWidget);
    final demo = find.text('Essayer sans panneau · Démonstration');
    await tester.ensureVisible(demo);
    await tester.tap(demo);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    final device = find.text('Luma rouge · Démonstration');
    await tester.ensureVisible(device);
    await tester.tap(device);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Un mot. Un sourire.'), findsOneWidget);
    expect(find.text('MODE DÉMONSTRATION · SANS MATÉRIEL'), findsOneWidget);
    await tester.tap(find.text('Afficher sur le panneau'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Démonstration réussie.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
