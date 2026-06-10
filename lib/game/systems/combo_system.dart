part of '../game_controller.dart';

extension ComboSystem on GameController {
  ComboArea _generateComboArea() {
    final bossConvId = bossState?.conqueredConvId;
    final eligible = conveyors
        .where((c) => c.id != bossConvId)
        .map((c) => c.color)
        .toList();
    final colorPool = eligible.isEmpty
        ? conveyors.map((c) => c.color).toList()
        : eligible;
    final recipe = List.generate(
        GameConfig.comboSlotCount,
        (_) => colorPool[_random.nextInt(colorPool.length)]);
    final reward = currentStage.overrideComboReward() ?? _weightedSpecial();
    return ComboArea(recipe: recipe, reward: reward);
  }

  SpecialType _weightedSpecial() {
    const weights = {
      SpecialType.bomb: GameConfig.specialBombWeight,
      SpecialType.icy:  GameConfig.specialIcyWeight,
      SpecialType.time: GameConfig.specialTimeWeight,
    };
    final total = weights.values.fold(0.0, (a, b) => a + b);
    double pick = _random.nextDouble() * total;
    for (final entry in weights.entries) {
      pick -= entry.value;
      if (pick <= 0) return entry.key;
    }
    return weights.keys.last;
  }

  void _advanceCombo(BoxColor scored, double now) {
    final area = comboArea;
    if (area == null || area.completionTime != null) return;
    if (area.currentTarget?.id == scored.id) {
      area.progress++;
      if (area.isComplete) _completeComboArea(area, now);
    } else if (area.progress > 0) {
      area.progress = 0;
    }
  }

  void _completeComboArea(ComboArea area, double now) {
    area.completionTime = now;
    _hapticMedium();
    _spawnSpecialBox(area.reward, now);
    final label = switch (area.reward) {
      SpecialType.bomb => '💣 BOMB INCOMING!',
      SpecialType.icy  => '❄ ICY INCOMING!',
      SpecialType.time => '⏱ SLOW INCOMING!',
    };
    _addPopup(GameController.gameWidth / 2, GameConfig.comboAreaTop + 26,
        label, const Color(0xFFFF6600), size: 20);
  }

  void _checkComboReset(double now) {
    final area = comboArea;
    if (area == null || area.completionTime == null) return;
    if (now - area.completionTime! >= 1500) {
      comboArea = _generateComboArea();
    }
  }

  void _spawnSpecialBox(SpecialType type, double now) {
    final bossConvId = bossState?.conqueredConvId;
    final available = conveyors
        .where((c) => !c.maintenance && !c.frozen && c.id != bossConvId)
        .toList();
    if (available.isEmpty) return;
    final conv  = available[_random.nextInt(available.length)];
    final convH = getCurrentHeight(conv, now);
    final bs    = GameController.boxSize;
    _pendingBoxes.add(Box(
      id: _boxIdCounter++,
      x: conv.x + (conv.width - bs) / 2,
      y: conv.direction == ConveyorDirection.down ? conv.y - bs : conv.y + convH,
      conveyorId: conv.id,
      color: conv.color,
      size: bs,
      onConveyor: true,
      entering: true,
      specialType: type,
    ));
  }

  void _triggerSpecial(
      SpecialType type, Conveyor conv, bool isDown, double gateY, double popupY) {
    final handler = SpecialRegistry.find(type);
    if (handler != null) {
      handler.onScore(this, conv, isDown, gateY, popupY);
      return;
    }
    switch (type) {
      case SpecialType.bomb: _triggerBomb(conv, isDown, gateY, popupY);
      case SpecialType.icy:  _triggerIcy(conv, isDown, gateY, popupY);
      case SpecialType.time: _triggerTime(conv, isDown, gateY, popupY);
    }
  }

  void _triggerBomb(Conveyor conv, bool isDown, double gateY, double popupY) {
    int count = 0;
    for (final b in boxes) {
      if (b.conveyorId == conv.id &&
          b.id != draggedBoxId &&
          b.specialType == null) {
        _pendingRemovals.add(b.id);
        count++;
      }
    }
    if (count > 0) score += count;

    final cx    = conv.x + conv.width / 2;
    final convH = getCurrentHeight(conv, _lastFrameTime);
    _spawnExplosion(cx, gateY);
    _shakeUntil = _lastFrameTime + 500;
    HapticFeedback.heavyImpact();

    beltExplosions.removeWhere((e) => e.conveyorId == conv.id);
    beltExplosions.add(BeltExplosion(
      conveyorId: conv.id,
      startTime: _lastFrameTime,
      duration: (convH * 1.5).clamp(500.0, 900.0),
      fromY: gateY,
      toY: isDown ? conv.y : conv.y + convH,
    ));

    GameAudio.instance.play(SoundEffect.bomb);
    _addPopup(cx, popupY, count > 0 ? '💥 +$count' : '💥 BOOM!',
        const Color(0xFFFF6600), size: 28);
    currentStage.onBombHit(this, conv.id, _lastFrameTime);
  }

  void _triggerIcy(Conveyor conv, bool isDown, double gateY, double popupY) {
    conv.frozen = true;
    conv.frozenUntil = _lastFrameTime + GameController.icyFreezeDuration;
    final cx = conv.x + conv.width / 2;
    _spawnIceEffect(cx, gateY);
    HapticFeedback.lightImpact();
    GameAudio.instance.play(SoundEffect.icy);
    _addPopup(cx, popupY, '❄ FROZEN!', const Color(0xFF7DD3FC), size: 24);
  }

  void _triggerTime(Conveyor conv, bool isDown, double gateY, double popupY) {
    conv.speed = max(GameConfig.conveyorMinSpeed, conv.speed * GameConfig.timeSlowFactor);
    final cx = conv.x + conv.width / 2;
    HapticFeedback.lightImpact();
    _addPopup(cx, popupY, '⏱ SLOW!', const Color(0xFF60A5FA), size: 24);
  }
}
