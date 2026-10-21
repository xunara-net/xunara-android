import 'package:flutter/material.dart';

import '../models.dart';

class DevicePresence extends StatelessWidget {
  const DevicePresence({required this.device, super.key});
  final NetworkDevice device;

  @override
  Widget build(BuildContext context) {
    final color = switch (device.online) {
      true => const Color(0xFF0A825D),
      false => Colors.blueGrey,
      null => Colors.grey,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 5),
        Text(device.onlineLabel, style: TextStyle(color: color)),
      ],
    );
  }
}
