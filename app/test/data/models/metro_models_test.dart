import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/data/models/metro_models.dart';

void main() {
  test('MetroLiveArrival carries line, destination, seconds', () {
    const a = MetroLiveArrival(
      line: 'BR',
      destination: '南港展覽館',
      estimateSeconds: 90,
    );
    expect(a.line, 'BR');
    expect(a.destination, '南港展覽館');
    expect(a.estimateSeconds, 90);
  });
}
