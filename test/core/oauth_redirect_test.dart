import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';

void main() {
  test('production OAuth callback preserves the deployed app base path', () {
    expect(
      oauthRedirectUri(
        Uri.parse('https://cardcompass.in/app/dashboard?x=1#fragment'),
      ),
      Uri.parse('https://cardcompass.in/app/'),
    );
  });

  test('local callback keeps its allow-listed origin and app path', () {
    expect(
      oauthRedirectUri(Uri.parse('http://127.0.0.1:8080/app/')),
      Uri.parse('http://127.0.0.1:8080/app/'),
    );
  });

  test('an unlisted host cannot become an OAuth callback target', () {
    expect(
      () => oauthRedirectUri(Uri.parse('https://attacker.example/app/')),
      throwsStateError,
    );
  });
}
