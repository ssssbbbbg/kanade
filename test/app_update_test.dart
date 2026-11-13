import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/update/app_update.dart';

void main() {
  test('compareVersions orders releases and previews', () {
    expect(compareVersions('v1.3.0', '1.2.9'), 1);
    expect(compareVersions('v1.2.0', '1.2.0'), 0);
    expect(compareVersions('v1.2.0', '1.2.0+15'), 0);
    expect(compareVersions('v1.10.0', '1.9.0'), 1);
    expect(compareVersions('v1.3.0-beta.1', '1.2.0'), 1);
    expect(compareVersions('v1.3.0-beta.1', '1.3.0'), -1);
    expect(compareVersions('v1.3.0', '1.3.0-beta.2'), 1);
    expect(compareVersions('v1.3.0-beta.10', '1.3.0-beta.2'), 1);
    expect(compareVersions('v1.3.0-rc.1', '1.3.0-beta.2'), 1);
    expect(compareVersions('v1.3.0-beta', '1.3.0-beta.1'), -1);
  });
}
