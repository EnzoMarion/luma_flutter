import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/controller.dart';
import 'package:luma/protocol.dart';

void main() {
  test('anciens index et messages arabes sont migrés', () async {
    SharedPreferences.setMockInitialValues({
      'luma.alphabet': 5,
      'luma.message': 'مرحبا',
      'favorites': ['MERCI', 'مرحبا'],
    });
    final controller = LumaController();
    await controller.loadFavorites();
    expect(controller.settings.alphabet, PanelAlphabet.japanese);
    expect(controller.message, 'MERCI');
    expect(controller.favorites, ['MERCI']);
    controller.dispose();
  });
  test('restaure message, réglages et favoris', () async {
    SharedPreferences.setMockInitialValues({
      'luma.message': 'À BIENTÔT',
      'luma.brightness': 10,
      'luma.speed': 20,
      'luma.mode': ScrollMode.fixed.index,
      'luma.power': false,
      'luma.icon': 3,
      'favorites': ['MERCI', 'À BIENTÔT'],
    });
    final controller = LumaController();
    await controller.loadFavorites();
    expect(controller.message, 'À BIENTÔT');
    expect(controller.settings.brightness, 10);
    expect(controller.settings.speedMs, 20);
    expect(controller.settings.mode, ScrollMode.fixed);
    expect(controller.settings.power, isFalse);
    expect(controller.icon, 3);
    expect(controller.favorites, ['MERCI', 'À BIENTÔT']);
    await controller.toggleFavorite();
    expect((await SharedPreferences.getInstance()).getStringList('favorites'), ['MERCI']);
    controller.updateMessage('merci');
    await controller.toggleFavorite();
    expect(controller.favorites, isEmpty);
    controller.dispose();
  });
}
