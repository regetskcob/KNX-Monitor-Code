import '../knx/group_catalog.dart';
import '../knx/telegram.dart';

/// Identifier in the QR code of a label. Deliberately not a web URL: the code
/// only resolves in the app that knows the installation, and the label in the
/// distribution board carries nothing but this identifier (no password, no key,
/// no network address).
const deviceLabelPrefix = 'knx-monitor-device';

/// What a QR code points to: device [address] of installation [installation].
typedef DeviceLabelRef = ({String installation, int address});

/// Content of the QR code.
String deviceLabelCode(String installation, int address) =>
    '$deviceLabelPrefix:1:$installation:${formatIndividual(address)}';

/// Reads a QR code; `null` if it is not ours.
DeviceLabelRef? parseDeviceLabel(String text) {
  final parts = text.trim().split(':');
  if (parts.length != 4 || parts[0] != deviceLabelPrefix || parts[1] != '1') return null;
  if (!RegExp(r'^[0-9A-Za-z_-]{1,64}$').hasMatch(parts[2])) return null;
  if (!RegExp(r'^\d{1,2}\.\d{1,2}\.\d{1,3}$').hasMatch(parts[3])) return null;
  final address = parseIndividual(parts[3]);
  return address == null ? null : (installation: parts[2], address: address);
}

/// What a scanned code means for the active installation.
sealed class LabelResolution {
  const LabelResolution();
}

/// The device is in the active installation: open it.
class LabelOpenDevice extends LabelResolution {
  const LabelOpenDevice(this.address);
  final int address;
}

/// The code belongs to installation [installationName] on this device: switch there.
class LabelOtherInstallation extends LabelResolution {
  const LabelOtherInstallation(this.installationName, this.address);
  final String installationName;
  final int address;
}

/// Installation not on this device.
class LabelUnknownInstallation extends LabelResolution {
  const LabelUnknownInstallation(this.address);
  final int address;
}

/// Not a KNX Monitor label.
class LabelForeign extends LabelResolution {
  const LabelForeign();
}

/// Resolves a scanned text locally; nothing goes to the network for it.
LabelResolution resolveDeviceLabel(
  String text, {
  required String activeId,
  required String? Function(String id) nameOf,
}) {
  final ref = parseDeviceLabel(text);
  if (ref == null) return const LabelForeign();
  if (ref.installation == activeId) return LabelOpenDevice(ref.address);
  final name = nameOf(ref.installation);
  return name == null ? LabelUnknownInstallation(ref.address) : LabelOtherInstallation(name, ref.address);
}

/// A label for the distribution board.
class DeviceLabel {
  const DeviceLabel({required this.address, required this.place, required this.function, required this.code});

  final int address;

  /// Installation location according to the project.
  final String place;

  /// Function: name of the device, or the product as a fallback.
  final String function;
  final String code;
}

/// Labels of the devices in [catalog], by address; tunnels are not devices.
List<DeviceLabel> deviceLabels(GroupCatalog catalog, String installation, {Set<int>? only}) => [
  for (final d in catalog.devices.values.toList()..sort((a, b) => a.address.compareTo(b.address)))
    if (!d.isTunnel && (only == null || only.contains(d.address)))
      DeviceLabel(
        address: d.address,
        place: d.location ?? '',
        function: d.name.trim().isNotEmpty ? d.name.trim() : (d.product ?? ''),
        code: deviceLabelCode(installation, d.address),
      ),
];

/// Columns and rows per A4 sheet (common sheets 70 × 37 mm).
const labelColumns = 3;
const labelRows = 8;
