import 'dart:math';

import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../../models/boss_state.dart';
import '../../models/conveyor.dart';
import '../../models/special_type.dart';
import 'game_stage.dart';

class BossStage extends GameStage {
  static const double _walkSpeed = 90.0; // game-px per second

  @override
  String get name => 'boss';

  @override
  bool get isBoss => true;

  @override
  SpecialType? overrideComboReward() => SpecialType.bomb;

  @override
  void onActivate(GameController ctrl, int level, double now) {
    if (ctrl.conveyors.isEmpty) return;
    final rng = Random();
    final conv = ctrl.conveyors[rng.nextInt(ctrl.conveyors.length)];

    // Gate must be at the top — flip this belt upward.
    conv.direction = ConveyorDirection.up;
    // Clear regular boxes so the direction switch is seamless.
    ctrl.boxes
        .removeWhere((b) => b.conveyorId == conv.id && b.specialType == null);

    final targetX = conv.x + conv.width / 2;

    // Boss walks in the gap between the combo panel and the belt tops.
    // y = bottom of the boss sprite, just above the belt.
    final bossY = GameController.conveyorTop - 10.0;

    // Approach from the side opposite the target gate.
    final startX = targetX < GameController.gameWidth / 2
        ? GameController.gameWidth + 60.0
        : -60.0;

    final bossLevel = level ~/ 5;
    final health = (2 + bossLevel).clamp(3, 8);

    ctrl.bossState = BossState(
      phase: BossPhase.entering,
      x: startX,
      y: bossY,
      targetX: targetX,
      conqueredConvId: conv.id,
      health: health,
      maxHealth: health,
      phaseStartTime: now,
    );

    // Force the next combo to reward a bomb (not icy).
    ctrl.regenerateComboArea();
  }

  @override
  void onUpdate(GameController ctrl, double now, double dt) {
    final b = ctrl.bossState;
    if (b == null) return;

    switch (b.phase) {
      case BossPhase.entering:
        final dx = b.targetX - b.x;
        final step = _walkSpeed * dt / 1000.0;
        if (dx.abs() <= step + 0.5) {
          b.x = b.targetX;
          b.phase = BossPhase.conquering;
          b.phaseStartTime = now;
          ctrl.addPopup(b.x, b.y - 70, '⚠ BOSS ARRIVING!',
              const Color(0xFFFF3300), size: 20);
        } else {
          b.x += dx.sign * step;
        }

      case BossPhase.conquering:
        if (now - b.phaseStartTime >= 900) {
          b.phase = BossPhase.conquered;
          ctrl.addPopup(b.x, b.y - 70, '💀 GATE CONQUERED!',
              const Color(0xFFFF0000), size: 22);
        }

      case BossPhase.conquered:
        break;

      case BossPhase.dying:
        if (now - b.phaseStartTime >= 1200) {
          ctrl.bossState = null;
          ctrl.currentStage = const NormalStage();
          ctrl.score += 15;
          ctrl.addPopup(
              GameController.gameWidth / 2,
              GameController.conveyorTop - 50,
              '🏆 BOSS DEFEATED! +15',
              const Color(0xFFFFD700),
              size: 26);
        }
    }
  }

  @override
  void onBombHit(GameController ctrl, int conveyorId, double now) {
    final b = ctrl.bossState;
    if (b == null || b.phase != BossPhase.conquered) return;
    if (conveyorId != b.conqueredConvId) return;

    b.health--;
    ctrl.spawnExplosion(b.x, b.y - 30);

    if (b.health <= 0) {
      b.phase = BossPhase.dying;
      b.phaseStartTime = now;
      ctrl.addPopup(b.x, b.y - 70, '💥 BOSS DOWN!',
          const Color(0xFFFF6600), size: 28);
    } else {
      ctrl.addPopup(b.x, b.y - 70, '💥 HIT! ${b.health} HP',
          const Color(0xFFFF8800), size: 22);
    }
  }
}
