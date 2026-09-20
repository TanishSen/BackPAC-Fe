import 'package:backPAC/features/auth/data/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the home screen calls you.
///
/// The greeting used to be the literal string 'Jasmin' from the mockups, which
/// meant every real user was welcomed by a stranger's name. These cover the
/// fallback chain that replaced it.
void main() {
  group('a name out of an email address', () {
    // Reached through the public getter's helper by way of the same rules;
    // these are the shapes real addresses actually take.
    String? nameFrom(String email) => AuthService.nameFromEmailForTest(email);

    test('takes the first name and capitalises it', () {
      expect(nameFrom('tanish@gmail.com'), 'Tanish');
      expect(nameFrom('TANISH@gmail.com'), 'Tanish');
    });

    test('cuts at the separator people actually use', () {
      expect(nameFrom('tanish.sen@gmail.com'), 'Tanish');
      expect(nameFrom('tanish_sen@gmail.com'), 'Tanish');
      expect(nameFrom('tanish-sen@gmail.com'), 'Tanish');
      expect(nameFrom('tanish+travel@gmail.com'), 'Tanish');
      expect(nameFrom('tanishsen.2520@gmail.com'), 'Tanishsen');
    });

    test('drops trailing digits rather than reading them out', () {
      expect(nameFrom('tanish2520@gmail.com'), 'Tanish');
    });

    test('gives up instead of greeting someone by nonsense', () {
      // A one-letter or numeric local part is not a name, and "Hi, X" is
      // worse than a neutral greeting.
      expect(nameFrom('t@gmail.com'), isNull);
      expect(nameFrom('2520@gmail.com'), isNull);
      expect(nameFrom('not-an-email'), isNull);
    });
  });
}
