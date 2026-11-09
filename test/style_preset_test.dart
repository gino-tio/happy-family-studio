import 'package:flutter_test/flutter_test.dart';
import 'package:happy_family_studio/models/style_preset.dart';

void main() {
  test('every preset fits the 1000-char style limit', () {
    for (final p in StylePreset.all) {
      expect(p.style.length, lessThanOrEqualTo(1000), reason: p.label);
    }
  });

  test('City Pop preset is offered', () {
    final cityPop = StylePreset.all.firstWhere((p) => p.label == 'City Pop');
    expect(cityPop.style, contains('105 BPM'));
    expect(cityPop.style, contains('Dm9'));
  });
}
