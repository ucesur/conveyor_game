part of '../game_controller.dart';

extension BoxSystem on GameController {
  // ---- Slot helpers ----
  double _slotY(Conveyor conv, int s) =>
      conv.y + s * GameController.boxSize;

  double _slotYScrolled(Conveyor conv, int s, double convH) {
    final n    = GameController._numSlots(convH);
    final bs   = GameController.boxSize;
    final absOff = beltOffset(conv.speed, conv.direction).abs();
    final k = (absOff / bs).floor();
    final f = absOff % bs;
    if (conv.direction == ConveyorDirection.down) {
      return conv.y + (s + k) % n * bs + f;
    } else {
      return conv.y + ((s - k) % n + n) % n * bs - f;
    }
  }

  int _currentEntrySlot(Conveyor conv, double convH) {
    final n  = GameController._numSlots(convH);
    final bs = GameController.boxSize;
    final k  = (beltOffset(conv.speed, conv.direction).abs() / bs).floor();
    return conv.direction == ConveyorDirection.down
        ? (n - k % n) % n
        : (n - 1 + k) % n;
  }

  bool _isSlotFree(Conveyor conv, int s, int excludeId, {bool forDrop = false}) {
    final isDown   = conv.direction == ConveyorDirection.down;
    final convH    = getCurrentHeight(conv, _lastFrameTime);
    final entrySlot = _currentEntrySlot(conv, convH);
    return !boxes.any((b) {
      if (b.id == excludeId) return false;
      final anim = b.throwAnim;
      if (anim != null && !b.onConveyor && anim.targetConvId == conv.id) {
        return anim.targetSlot == s;
      }
      if (b.conveyorId != conv.id || !b.onConveyor) return false;
      if (b.slotIndex == null) {
        if (forDrop) {
          final onBelt = isDown ? b.y >= conv.y : b.y + b.size <= conv.y + convH;
          return onBelt && s == entrySlot;
        }
        return s == entrySlot;
      }
      if (b.slotIndex == GameController._exitSlot) return false;
      return b.slotIndex == s;
    });
  }

  int _closestSlotIndex(Conveyor conv, double y, double convH, int nSlots) {
    int best = 0;
    double bestDist = double.infinity;
    for (int s = 0; s < nSlots; s++) {
      final dist = (y - _slotYScrolled(conv, s, convH)).abs();
      if (dist < bestDist) { bestDist = dist; best = s; }
    }
    return best.clamp(0, nSlots - 1);
  }

  // ---- Spawn ----
  double _spawnInterval() {
    final base = max(GameConfig.spawnIntervalMin,
        GameConfig.spawnIntervalBase - (level - 1) * 200.0);
    return base * (GameConfig.spawnIntervalJitterMin +
        _random.nextDouble() *
            (GameConfig.spawnIntervalJitterMax - GameConfig.spawnIntervalJitterMin));
  }

  void _spawnBoxes(double now) {
    if (conveyors.isEmpty) return;
    final bs = GameController.boxSize;
    final bossConvId = bossState?.conqueredConvId;
    // Exclude the conquered belt's color from the spawn pool during boss stage.
    final colorPool = bossConvId != null
        ? conveyors.where((c) => c.id != bossConvId).toList()
        : conveyors;
    final effectivePool = colorPool.isEmpty ? conveyors : colorPool;
    for (final conv in conveyors) {
      if (conv.maintenance || conv.frozen) continue;
      if (conv.id == bossConvId) continue; // Boss owns this gate — bombs only.
      if (now < (_nextSpawnTime[conv.id] ?? 0)) continue;
      final convH = getCurrentHeight(conv, now);
      if (!_isSlotFree(conv, _currentEntrySlot(conv, convH), -1)) continue;
      boxes.add(Box(
        id: _boxIdCounter++,
        x: conv.x + (conv.width - bs) / 2,
        y: conv.direction == ConveyorDirection.down
            ? conv.y - bs : conv.y + convH,
        conveyorId: conv.id,
        color: effectivePool[_random.nextInt(effectivePool.length)].color,
        size: bs,
        onConveyor: true,
        entering: true,
      ));
      _nextSpawnTime[conv.id] = now + _spawnInterval();
    }
  }

  // ---- Move ----
  void _moveBoxes(double now, double dt) {
    int wrongHits = 0;
    _pendingBoxes.clear();
    _pendingRemovals.clear();
    final List<Box> keep = [];

    for (final box in boxes) {
      if (box.id == draggedBoxId)  { keep.add(box); continue; }
      if (!box.onConveyor)         { keep.add(box); continue; }

      final conv = _findConveyor(box.conveyorId);
      if (conv == null)                        { keep.add(box); continue; }
      if (conv.maintenance || conv.frozen)     { keep.add(box); continue; }

      final convH      = getCurrentHeight(conv, now);
      final nSlots     = GameController._numSlots(convH);
      final moveAmount = conv.speed * dt * 0.1;
      final isDown     = conv.direction == ConveyorDirection.down;

      if (box.slotIndex == GameController._exitSlot) {
        final newY = box.y + (isDown ? moveAmount : -moveAmount);
        final gateY = isDown ? conv.y + convH : conv.y;
        if (isDown ? newY + box.size >= gateY : newY <= gateY) {
          wrongHits += _processGateHit(box, conv, convH, isDown);
          continue;
        }
        box.y = newY;
        keep.add(box);
        continue;
      }

      final entryRow   = isDown ? 0 : nSlots - 1;
      final entryLabel = _currentEntrySlot(conv, convH);

      if (box.slotIndex == null) {
        final targetY = _slotY(conv, entryRow);
        final dist    = (box.y - targetY).abs();
        if (dist <= moveAmount + 0.5) {
          if (_isSlotFree(conv, entryLabel, box.id)) {
            box.y = _slotYScrolled(conv, entryLabel, convH);
            box.slotIndex = entryLabel;
            box.entering = false;
          }
        } else {
          box.y += (isDown ? 1.0 : -1.0) * moveAmount;
        }
        keep.add(box);
        continue;
      }

      box.y += (isDown ? 1.0 : -1.0) * moveAmount;
      if (isDown ? box.y + box.size >= conv.y + convH : box.y <= conv.y) {
        box.slotIndex = GameController._exitSlot;
      }
      keep.add(box);
    }

    if (_pendingRemovals.isNotEmpty) {
      keep.removeWhere((b) => _pendingRemovals.contains(b.id));
    }
    _resolveOverlaps(keep, now);
    boxes = keep;

    if (_pendingBoxes.isNotEmpty) {
      boxes.addAll(_pendingBoxes);
      _pendingBoxes.clear();
    }

    if (wrongHits > 0) {
      _shakeUntil = _lastFrameTime + 280;
      if (lives <= 0) {
        lives = 0;
        gameState = GameState.gameover;
        if (score > highScore) highScore = score;
        GameAudio.instance.play(SoundEffect.gameOver);
      }
    }
  }

  void _resolveOverlaps(List<Box> boxList, double now) {
    for (final conv in conveyors) {
      final isDown = conv.direction == ConveyorDirection.down;
      final beltBoxes = boxList
          .where((b) =>
              b.conveyorId == conv.id &&
              b.onConveyor &&
              b.slotIndex != null &&
              b.slotIndex != GameController._exitSlot &&
              b.id != draggedBoxId)
          .toList();
      beltBoxes.sort((a, b) => isDown ? b.y.compareTo(a.y) : a.y.compareTo(b.y));
      for (int i = 1; i < beltBoxes.length; i++) {
        final ahead = beltBoxes[i - 1];
        final curr  = beltBoxes[i];
        if (isDown) {
          if (curr.y + curr.size > ahead.y) curr.y = ahead.y - curr.size;
        } else {
          if (curr.y < ahead.y + ahead.size) curr.y = ahead.y + ahead.size;
        }
        final convH = getCurrentHeight(conv, now);
        final ns    = GameController._numSlots(convH);
        if (curr.slotIndex! >= ns ||
            (isDown ? curr.y + curr.size >= conv.y + convH : curr.y <= conv.y)) {
          curr.slotIndex = GameController._exitSlot;
        }
      }
    }
  }

  int _processGateHit(Box box, Conveyor conv, double convH, bool isDown) {
    final gateY  = isDown ? conv.y + convH : conv.y;
    final popupY = isDown ? gateY - 10 : gateY + 10;
    final go     = GameController.gateOffset;
    final gh     = GameController.gateHeight;

    if (box.specialType != null) {
      _triggerSpecial(box.specialType!, conv, isDown, gateY, popupY);
      fallingBoxes.add(FallingBox(
        x: box.x,
        y: isDown ? gateY - box.size : gateY,
        vy: isDown ? 0.4 : -0.4,
        size: box.size,
        color: box.color,
        startY: isDown ? gateY - box.size : gateY,
        disappearY: isDown ? gateY + go + gh : gateY - go - gh,
      ));
      return 0;
    }

    // Boss gate: any non-bomb box feeds the boss (heals it); lives are NOT lost.
    final boss = bossState;
    if (boss != null &&
        boss.phase == BossPhase.conquered &&
        conv.id == boss.conqueredConvId) {
      boss.health = min(boss.health + 1, boss.maxHealth);
      _addPopup(conv.x + conv.width / 2, boss.y - 70,
          '🍖 +HP', const Color(0xFF22C55E), size: 20);
      fallingBoxes.add(FallingBox(
        x: box.x,
        y: isDown ? gateY - box.size : gateY,
        vy: isDown ? 0.4 : -0.4,
        size: box.size,
        color: box.color,
        startY: isDown ? gateY - box.size : gateY,
        disappearY: isDown ? gateY + go + gh : gateY - go - gh,
      ));
      return 0;
    }

    int wrong = 0;
    if (box.color.id == conv.color.id) {
      if (_comboColorId == box.color.id) {
        _comboCount++;
      } else {
        _comboCount = 1;
        _comboColorId = box.color.id;
      }
      final mult = min(_comboCount, 4);
      score += mult;
      _addPopup(conv.x + conv.width / 2, popupY,
          _comboCount >= 2 ? '+$mult  x$_comboCount' : '+1',
          const Color(0xFF22C55E),
          size: _comboCount >= 2 ? 26 : 22);
      GameAudio.instance.play(
          _comboCount >= 2 ? SoundEffect.combo : SoundEffect.correct);
      _hapticMedium();
      _advanceCombo(box.color, _lastFrameTime);
    } else {
      wrong = 1;
      _comboCount = 0;
      _comboColorId = null;
      _addPopup(conv.x + conv.width / 2, popupY, '✗', const Color(0xFFEF4444));
      GameAudio.instance.play(SoundEffect.wrong);
      _hapticHeavy();
    }

    fallingBoxes.add(FallingBox(
      x: box.x,
      y: isDown ? gateY - box.size : gateY,
      vy: isDown ? 0.4 : -0.4,
      size: box.size,
      color: box.color,
      startY: isDown ? gateY - box.size : gateY,
      disappearY: isDown ? gateY + go + gh : gateY - go - gh,
    ));
    return wrong;
  }

  void _updateFallingBoxes(double dt) {
    fallingBoxes.removeWhere((fb) => fb.disappearY >= fb.startY
        ? fb.y >= fb.disappearY : fb.y <= fb.disappearY);
    for (final fb in fallingBoxes) {
      fb.vy += 0.001 * dt;
      fb.y  += fb.vy * dt;
    }
  }
}
