import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_masa_tenisi/oyun_masa_tenisi.dart';

void main() {
  test('33 dilde ad, slogan, anlatım ve eğitim var', () {
    expect(masaTenisiConfig.gameId, 'oyun-masa-tenisi');
    expect(masaTenisiConfig.title.length, 33);
    expect(masaTenisiConfig.tagline.length, 33);
    for (final s in masaTenisiConfig.tutorial) {
      expect(s.text.length, 33);
      expect(s.text.every((t) => t.trim().isNotEmpty), isTrue);
    }
  });
}
