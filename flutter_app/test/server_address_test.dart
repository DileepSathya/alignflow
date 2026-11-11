import 'package:alignflow/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes a PC address and supplies the default API port', () {
    expect(normalizeServerAddress(' 192.168.1.25 '),
        'http://192.168.1.25:8000');
    expect(normalizeServerAddress('192.168.1.25:9000'),
        'http://192.168.1.25:9000');
  });

  test('rejects malformed and unsafe server addresses', () {
    for (final address in [
      '',
      '192.168.1.999:8000',
      'http://user:pass@192.168.1.25:8000',
      'http://192.168.1.25:8000/login',
      'ftp://192.168.1.25:8000',
    ]) {
      expect(() => normalizeServerAddress(address), throwsA(isA<ApiException>()));
    }
  });
}
