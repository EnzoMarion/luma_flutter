import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/drawing_editor.dart';
import 'package:luma/main.dart';
import 'package:luma/pixel_preview.dart';

void main() {
  testWidgets('aperçu immobile lorsque les animations sont réduites',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Scaffold(body: PixelPreview(columns: 32, text: 'BONJOUR')),
    )));
    await tester.pump(const Duration(seconds: 1));
    final previews = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((widget) => widget.painter is MatrixPainter)
        .toList();
    expect(previews, hasLength(1));
    expect((previews.single.painter! as MatrixPainter).step, -1);
  });
  testWidgets('accueil et recherche de démonstration', (tester) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LumaApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Panneau Luma'), findsOneWidget);
    final demo = find.text('Essayer la démonstration');
    await tester.ensureVisible(demo);
    await tester.pump();
    await tester.tap(demo);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    final device = find.text('Luma RGB · Démonstration');
    expect(device, findsOneWidget);
    await tester.ensureVisible(device);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(device);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Votre message'), findsWidgets);
    expect(find.text('MODE DÉMONSTRATION · SANS MATÉRIEL'), findsOneWidget);
    expect(find.bySemanticsLabel('État du panneau : démonstration'),
        findsOneWidget);
    final violet = find.bySemanticsLabel('Couleur Violet');
    expect(violet, findsOneWidget);
    expect(tester.getSize(violet).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(violet).height, greaterThanOrEqualTo(48));
    await tester.tap(find.text('Afficher sur le panneau'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Démonstration terminée'), findsOneWidget);
    await tester.tap(find.text('Terminé'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Effacer le panneau'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Effacer le panneau ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Effacer le panneau ?'), findsNothing);
    await tester.tap(find.text('Effacer le panneau'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Effacer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Démonstration terminée'), findsOneWidget);
    await tester.tap(find.text('Terminé'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Panneau'));
    await tester.pump();
    expect(find.text('Luminosité'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
    await tester.tap(find.text('Fixe'));
    await tester.pump();
    await tester.tap(find.text('Appliquer les réglages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Démonstration terminée'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('dessin : ajout, favori et validation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DrawingEditor()));
                      },
                      child: const Text('Ouvrir')),
                ))));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Ligne 1, colonne 1'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Ajouter aux favoris'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Ajouter aux favoris'));
    await tester.pump();
    await tester.tap(find.text('Ajouter aux favoris'));
    await tester.pump();
    await tester.ensureVisible(find.text('Valider le dessin'));
    await tester.pump();
    await tester.tap(find.text('Valider le dessin'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.substring(0, 3), '0:1');
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('drawing_favorites_v2'),
        contains(result));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un dessin favori restaure ses pixels et sa couleur',
      (tester) async {
    final bits = '1' + ('0' * 255);
    SharedPreferences.setMockInitialValues({
      'drawing_favorites_v2': ['4:$bits']
    });
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DrawingEditor()));
                      },
                      child: const Text('Ouvrir')),
                ))));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Dessin 1'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Dessin 1'));
    await tester.pump();
    await tester.ensureVisible(find.text('Valider le dessin'));
    await tester.pump();
    await tester.tap(find.text('Valider le dessin'));
    await tester.pumpAndSettle();
    expect(result, '4:$bits');
  });
}
