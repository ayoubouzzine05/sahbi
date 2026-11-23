import 'package:flutter_test/flutter_test.dart';
import 'package:sahbi/features/settings/app_settings.dart';
import 'package:sahbi/features/voice/wake_name.dart';

WakeHit? _any(String t) {
  for (final n in wakeNamesFor(const AppSettings())) {
    final h = matchWakeName(t, n);
    if (h != null) return h;
  }
  return null;
}

void main() {
  test('default name MIMO is heard in Arabic script and Latin', () {
    expect(_any('ميمو')?.rest, '');
    expect(_any('Mimo, chno ljaw?')?.rest, 'chno ljaw');
    expect(_any('يا ميمو فين نتا')?.rest, isNotNull);
    expect(_any('mimou')?.rest, '');
  });

  test('everyday words do not wake it', () {
    for (final t in ['mama', 'ماما', 'momo', 'ma3a mama', 'نمو', 'mami']) {
      expect(_any(t), isNull, reason: t);
    }
  });

  test('migration: old default name becomes MIMO, chosen name kept', () {
    expect(migrateToMimo(const AppSettings(robotName: 'صاحبي')).robotName, '');
    expect(migrateToMimo(const AppSettings(robotName: 'Sahbi')).robotName, '');
    final z = migrateToMimo(const AppSettings(robotName: 'Zizou'));
    expect(z.robotName, 'Zizou');
    expect(z.mimoMigrated, isTrue);
    expect(
      AppSettings.decode(z.encode()).mimoMigrated,
      isTrue,
      reason: 'migration runs once',
    );
  });
}
