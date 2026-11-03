/// What a paired device without admin rights may send via `/ws/bus`.
///
/// Otherwise arbitrary cEMI frames would go onto the bus through the relay:
/// A_Restart, A_Memory_Write, A_PropertyValue_Write, A_IndividualAddress_Write.
/// That would allow reprogramming or disabling any device in the installation.
library;

import 'package:knx/knx.dart';

/// A_GroupValue_Read, _Response and _Write to a group address, also as
/// A_SecureService (Data Secure): the receiver checks its content with the
/// group key, and sent to a group address it is itself a group value.
///
/// Not allowed: individual addresses (connections, memory, properties,
/// restart), group 0/0/0 (system broadcast, used for address assignment and
/// programming mode) and all other services.
bool deviceMaySend(List<int> cemi) {
  if (!isLDataRequest(cemi)) return false;
  final i = 2 + cemi[1];
  // Two bytes of APCI need at least npdu = 1.
  if (cemi.length < i + 9) return false;
  // No bytes after the stated length that a device might read differently.
  if (cemi.length != i + 8 + cemi[i + 6]) return false;
  if (cemi[i + 1] & 0x80 == 0) return false;
  if (cemi[i + 4] == 0 && cemi[i + 5] == 0) return false;
  // Upper 6 bits of the TPCI: only T_Data_Group.
  if (cemi[i + 7] & 0xFC != 0) return false;
  final apci = ((cemi[i + 7] & 0x03) << 8) | cemi[i + 8];
  return switch (apci & 0x3C0) {
    0x000 || 0x040 || 0x080 => true,
    _ => apci == 0x3F1,
  };
}
