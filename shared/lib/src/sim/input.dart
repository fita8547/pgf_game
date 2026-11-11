import '../math.dart';

/// Button bitmask used in [PlayerInput.buttons].
abstract final class Btn {
  static const fire = 1 << 0;
  static const ads = 1 << 1;
  static const jump = 1 << 2;
  static const crouch = 1 << 3;
  static const walk = 1 << 4;
  static const reload = 1 << 5;
  static const skillQ = 1 << 6;
  static const skillE = 1 << 7;
  static const skillShift = 1 << 8;
  static const ult = 1 << 9;
  static const slotPrimary = 1 << 10;
  static const slotSecondary = 1 << 11;
}

/// One frame of player intent. Sent client -> server and replayed for
/// client-side prediction.
class PlayerInput {
  int seq;
  double dt;

  /// Strafe (-1 left .. 1 right) and forward (-1 back .. 1 forward).
  double moveX, moveZ;
  double yaw, pitch;
  int buttons;

  /// Server tick the client was rendering (lag compensation), or -1.
  double renderTick;

  PlayerInput({
    this.seq = 0,
    this.dt = 0,
    this.moveX = 0,
    this.moveZ = 0,
    this.yaw = 0,
    this.pitch = 0,
    this.buttons = 0,
    this.renderTick = -1,
  });

  bool has(int b) => buttons & b != 0;

  List toNet() => [seq, r(dt, 4), r(moveX, 2), r(moveZ, 2), r(yaw, 4), r(pitch, 4), buttons, r(renderTick, 2)];

  static PlayerInput fromNet(List l) => PlayerInput(
        seq: (l[0] as num).toInt(),
        dt: (l[1] as num).toDouble(),
        moveX: (l[2] as num).toDouble(),
        moveZ: (l[3] as num).toDouble(),
        yaw: (l[4] as num).toDouble(),
        pitch: (l[5] as num).toDouble(),
        buttons: (l[6] as num).toInt(),
        renderTick: (l[7] as num).toDouble(),
      );
}
