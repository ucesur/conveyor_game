part of '../game_controller.dart';

extension DragSystem on GameController {
  void handleStart(Offset pos) {
    if (gameState != GameState.playing) return;
    for (int i = boxes.length - 1; i >= 0; i--) {
      final b = boxes[i];
      if (b.throwAnim != null) continue;
      if (pos.dx >= b.x - 12 &&
          pos.dx <= b.x + b.size + 12 &&
          pos.dy >= b.y - 12 &&
          pos.dy <= b.y + b.size + 12) {
        draggedBoxId = b.id;
        b.onConveyor = false;
        b.slotIndex = null;
        b.sourceConveyorId = b.conveyorId;
        b.dragStartTime = _lastFrameTime;
        b.x = pos.dx - b.size / 2;
        b.y = pos.dy - b.size / 2;
        b.trail = [];
        _hapticLight();
        GameAudio.instance.play(SoundEffect.drag);
        _notify();
        return;
      }
    }
  }

  void handleMove(Offset pos) {
    if (draggedBoxId == null) return;
    final box = _findBox(draggedBoxId!);
    if (box == null) return;

    final newX = pos.dx - box.size / 2;
    final newY = pos.dy - box.size / 2;
    final trail = box.trail ?? [];
    final bool shouldAdd = trail.isEmpty ||
        (trail.last.dx - box.x).abs() > 3 ||
        (trail.last.dy - box.y).abs() > 3;
    if (shouldAdd) {
      trail.add(Offset(box.x, box.y));
      if (trail.length > 6) trail.removeAt(0);
    }
    box.vx = newX - box.x;
    box.vy = newY - box.y;
    box.x = newX;
    box.y = newY;
    box.trail = trail;
  }

  void handleEnd() {
    if (draggedBoxId == null) return;
    final box = _findBox(draggedBoxId!);
    if (box == null) {
      draggedBoxId = null;
      _notify();
      return;
    }
    final now = _lastFrameTime;

    // Swipe detection
    double swipeVx = box.vx ?? 0.0;
    double swipeVy = box.vy ?? 0.0;
    final trail = box.trail;
    if (trail != null && trail.isNotEmpty) {
      final n = min(3, trail.length);
      swipeVx = (box.x - trail[trail.length - n].dx) / n;
      swipeVy = (box.y - trail[trail.length - n].dy) / n;
    }
    if (swipeVx.abs() >= 3.0 &&
        swipeVx.abs() > swipeVy.abs() &&
        box.sourceConveyorId != null) {
      final sourceConv = _findConveyor(box.sourceConveyorId!);
      final goRight    = swipeVx > 0;
      final targetConv = sourceConv == null ? null : conveyors.where((c) {
        if (!_areAdjacentBelts(sourceConv, c)) return false;
        return goRight ? c.x > sourceConv.x : c.x < sourceConv.x;
      }).firstOrNull;
      if (targetConv != null && !targetConv.maintenance) {
        final h    = getCurrentHeight(targetConv, now);
        final slot = _findFreeSlotIndex(box, targetConv, h);
        if (slot != null) {
          _startThrow(box, targetConv, slot, now);
          _hapticMedium();
          GameAudio.instance.play(SoundEffect.drop);
          draggedBoxId = null;
          _notify();
          return;
        }
      }
      _snapBackToSource(box, now);
      _hapticHeavy();
      _addPopup(box.x + box.size / 2, box.y - 10, '✗', const Color(0xFFEF4444), size: 16);
      draggedBoxId = null;
      _notify();
      return;
    }

    // Drop onto belt
    final bcx = box.x + box.size / 2;
    final bcy = box.y + box.size / 2;
    Conveyor? targetConv;
    for (final conv in conveyors) {
      final h = getCurrentHeight(conv, now);
      if (bcx >= conv.x - 10 && bcx <= conv.x + conv.width + 10 &&
          bcy >= conv.y && bcy <= conv.y + h) {
        targetConv = conv;
        break;
      }
    }

    if (targetConv != null && targetConv.maintenance) {
      _snapBackToSource(box, now);
      draggedBoxId = null;
      _notify();
      return;
    }

    if (targetConv != null && box.sourceConveyorId != null) {
      final src = _findConveyor(box.sourceConveyorId!);
      if (targetConv.id != box.sourceConveyorId &&
          (src == null || !_areAdjacentBelts(src, targetConv))) {
        _snapBackToSource(box, now);
        _addPopup(bcx, bcy - 20, 'TOO FAR', const Color(0xFFEF4444), size: 14);
        draggedBoxId = null;
        _notify();
        return;
      }
    }

    if (targetConv != null) {
      final h    = getCurrentHeight(targetConv, now);
      final slot = _findFreeSlotIndex(box, targetConv, h);
      if (slot == null) { _snapBackToSource(box, now); _hapticHeavy(); }
      else              { _startThrow(box, targetConv, slot, now); _hapticMedium(); GameAudio.instance.play(SoundEffect.drop); }
    } else {
      _snapBackToSource(box, now);
      _hapticHeavy();
    }
    draggedBoxId = null;
    _notify();
  }

  void _snapBackToSource(Box box, double now) {
    if (box.sourceConveyorId == null) {
      boxes.removeWhere((b) => b.id == box.id);
      return;
    }
    final src = _findConveyor(box.sourceConveyorId!);
    if (src == null) { boxes.removeWhere((b) => b.id == box.id); return; }
    final h       = getCurrentHeight(src, now);
    final fallback = _currentEntrySlot(src, h);
    _startThrow(box, src, _findFreeSlotIndex(box, src, h) ?? fallback, now);
  }

  int? _findFreeSlotIndex(Box box, Conveyor targetConv, double currentH) {
    final nSlots  = GameController._numSlots(currentH);
    final closest = _closestSlotIndex(targetConv, box.y, currentH, nSlots);
    for (int r = 0; r < nSlots; r++) {
      for (final s in (r == 0 ? [closest] : [closest - r, closest + r])) {
        if (s < 0 || s >= nSlots) continue;
        if (_isSlotFree(targetConv, s, box.id, forDrop: true)) return s;
      }
    }
    return null;
  }

  void _startThrow(Box box, Conveyor targetConv, int slot, double now) {
    final convH = getCurrentHeight(targetConv, now);
    box.throwAnim = ThrowAnim(
      startTime: now,
      startX: box.x,
      startY: box.y,
      endX: targetConv.x + (targetConv.width - GameController.boxSize) / 2,
      endY: _slotYScrolled(targetConv, slot, convH),
      targetConvId: targetConv.id,
      targetSlot: slot,
    );
    box.onConveyor = false;
    box.sourceConveyorId = null;
    box.dragStartTime = null;
  }

  void _updateThrows(double now) {
    for (final box in boxes) {
      final anim = box.throwAnim;
      if (anim == null) continue;
      final elapsed = now - anim.startTime;

      if (elapsed < anim.flightDuration) {
        final eased = easeOut(elapsed / anim.flightDuration);
        box.x = anim.startX + (anim.endX - anim.startX) * eased;
        box.y = anim.startY + (anim.endY - anim.startY) * eased;
        continue;
      }

      if (!box.onConveyor || box.conveyorId != anim.targetConvId) {
        box.x = anim.endX;
        box.onConveyor = true;
        box.conveyorId = anim.targetConvId;
        box.entering   = false;
        final tConv = _findConveyor(anim.targetConvId);
        if (tConv != null) {
          final convH = getCurrentHeight(tConv, now);
          final ns    = GameController._numSlots(convH);
          if (anim.targetSlot != GameController._exitSlot && anim.targetSlot < ns) {
            box.y = _slotYScrolled(tConv, anim.targetSlot, convH);
            box.slotIndex = anim.targetSlot;
          } else {
            box.y = anim.endY;
            box.slotIndex = GameController._exitSlot;
          }
        } else {
          box.y = anim.endY;
        }
        _spawnDust(box.x + box.size / 2, box.y + box.size, box.color);
      }

      if (elapsed >= anim.totalDuration) {
        box.throwAnim = null;
        box.trail = null;
        box.vx = null;
        box.vy = null;
      }
    }
  }

  ThrowPose throwPose(Box box) {
    final anim = box.throwAnim;
    if (anim == null) return const ThrowPose();
    final elapsed = currentTime - anim.startTime;

    if (elapsed < anim.flightDuration) {
      final t  = elapsed / anim.flightDuration;
      final dx = anim.endX - anim.startX;
      return ThrowPose(
        scaleX:   1.35 - 0.35 * t,
        scaleY:   1.35 - 0.35 * t,
        rotation: (currentTime * 0.6) % 360 + max(-30.0, min(30.0, dx * 0.25)),
        liftY:    -8 * (1 - t),
      );
    }

    final squashEnd = anim.flightDuration + anim.squashDuration;
    if (elapsed < squashEnd) {
      final intensity = 1 - (elapsed - anim.flightDuration) / anim.squashDuration;
      return ThrowPose(scaleX: 1.0 + intensity * 0.25, scaleY: 1.0 - intensity * 0.20);
    }

    final bounce = sin((elapsed - squashEnd) / anim.settleDuration * pi) * 0.06;
    return ThrowPose(scaleX: 1.0 + bounce, scaleY: 1.0 + bounce);
  }
}
