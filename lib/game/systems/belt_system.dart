part of '../game_controller.dart';

extension BeltSystem on GameController {
  void _handleReversals(double now) {
    if (now - _lastReverseCheck <= GameController.reverseCheckInterval) return;
    _lastReverseCheck = now;
    if (conveyors.length <= 1 || _random.nextDouble() >= GameController.reverseChance) return;

    final candidates = conveyors
        .where((c) => !c.maintenance && !c.resizing && !c.frozen)
        .toList();
    if (candidates.isEmpty) return;

    final target = candidates[_random.nextInt(candidates.length)];
    target.pendingDirection = target.direction == ConveyorDirection.down
        ? ConveyorDirection.up : ConveyorDirection.down;
    target.maintenance = true;
    target.maintenanceEnd = now + GameController.maintenanceDuration;

    boxes.removeWhere((b) =>
        b.conveyorId == target.id &&
        b.id != draggedBoxId &&
        b.specialType == null);

    _addPopup(target.x + target.width / 2, target.y + 10, '⚠',
        const Color(0xFFFBBF24), size: 28);
  }

  void _handleResizes(double now) {
    if (now - _lastResizeCheck <= GameController.resizeCheckInterval) return;
    _lastResizeCheck = now;
    if (conveyors.isEmpty || _random.nextDouble() >= GameController.resizeChance) return;

    final candidates = conveyors
        .where((c) => !c.maintenance && !c.resizing && !c.frozen)
        .toList();
    if (candidates.isEmpty) return;

    final target = candidates[_random.nextInt(candidates.length)];
    final currentH = target.height;
    final maxH = GameController.conveyorMaxHeight;
    final defH = GameController.conveyorDefaultHeight;
    final minH = GameController.conveyorMinHeight;
    double newH;
    if (currentH < maxH * 0.55) {
      newH = defH + _random.nextDouble() * (maxH - defH);
    } else if (currentH > maxH * 0.9) {
      newH = minH + _random.nextDouble() * (defH - minH);
    } else {
      newH = _random.nextDouble() < 0.5
          ? minH + _random.nextDouble() * 50
          : maxH - _random.nextDouble() * 40;
    }
    newH = max(minH, min(maxH, newH));

    target.resizing = true;
    target.resizeStart = now;
    target.fromHeight = target.height;
    target.toHeight = newH;

    _addPopup(target.x + target.width / 2, target.y + 10,
        newH > currentH ? '↕+' : '↕−', const Color(0xFF06B6D4), size: 22);
  }

  void _endMaintenance(double now) {
    for (final conv in conveyors) {
      if (conv.maintenance && now >= conv.maintenanceEnd) {
        conv.direction = conv.pendingDirection ?? conv.direction;
        conv.maintenance = false;
        conv.pendingDirection = null;
        conv.maintenanceEnd = 0;
      }
    }
  }

  void _endResize(double now) {
    for (final conv in conveyors) {
      if (conv.resizing &&
          now - conv.resizeStart >= GameController.resizeAnimationDuration) {
        conv.height = conv.toHeight;
        conv.resizing = false;
        conv.fromHeight = conv.toHeight;
      }
    }
  }

  void _endFreeze(double now) {
    for (final conv in conveyors) {
      if (conv.frozen && now >= conv.frozenUntil) {
        conv.frozen = false;
        conv.frozenUntil = 0;
      }
    }
  }
}
