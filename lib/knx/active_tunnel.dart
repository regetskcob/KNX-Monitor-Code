import 'package:flutter/foundation.dart';

import 'knx_tunnel.dart';

/// Connection of the open monitor – for write buttons deep inside views (object list of a device)
/// that otherwise do not know the tunnel. `null` without a monitor (recording, connecting).
final activeTunnel = ValueNotifier<KnxTunnel?>(null);
