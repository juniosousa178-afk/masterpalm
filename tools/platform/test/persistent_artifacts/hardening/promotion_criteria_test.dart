import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('promotion criteria remains declarative', () {
    const criteria = PersistentArtifactBackendPromotionCriteria();
    final json = criteria.toJson();
    expect(json['requireProductionBlock'], isTrue);
    expect(json['requireNoBootstrapRegistration'], isTrue);
  });
}
