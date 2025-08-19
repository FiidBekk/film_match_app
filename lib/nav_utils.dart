import 'package:flutter/material.dart';
import 'badge_center.dart';

/// Globális Friends ikon piros pöttyel (ValueListenable-re kötve)
Widget friendsIconWithGlobalBadge() {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      const Icon(Icons.group),
      ValueListenableBuilder<int>(
        valueListenable: BadgeCenter.instance.pendingListenable,
        builder: (_, count, icon) {
          if (count <= 0) return const SizedBox.shrink();
          return Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          );
        },
      ),
    ],
  );
}

/// Egységes Account ikon (ha szereted konstansként használni)
const kAccountIcon = Icon(Icons.person);
