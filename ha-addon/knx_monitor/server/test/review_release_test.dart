import 'package:knx_monitor_server/files.dart';
import 'package:test/test.dart';

void main() {
  test('a device over the limit can still delete, but not add', () {
    Map<String, Object?> rule(int i) => {'id': 'r$i', 'owner': 'd1'};
    final stored = {
      'rules': [for (var i = 0; i < 150; i++) rule(i)],
    };
    Map<String, Object?>? put(int n) => mergeDeviceEntries(
      stored,
      {
        'rules': [
          for (var i = 0; i < n; i++) {'id': 'r$i'},
        ],
      },
      list: 'rules',
      key: 'id',
      owner: 'd1',
    );
    expect(put(149), isNotNull);
    expect(put(150), isNull);
    expect(put(151), isNull);
    expect(put(100), isNotNull);
  });
}
