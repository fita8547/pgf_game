import 'math.dart';
import 'input.dart';

/// Server-side gate in front of [GameSim.processInput], one per connection.
///
/// The sim already enforces game rules (fire rate, ammo, collision). This
/// stops clients from bending *time* and *numbers*:
///  - speedhack: a client may only simulate as much time as really passed
///    (plus a small bank for jitter). Extra frames are dropped.
///  - replay / duplicates: sequence numbers must increase.
///  - flooding: at most [maxPerSecond] input frames per second.
///  - garbage: NaN/Infinity, out-of-range sticks and angles are fixed up.
class InputGuard {
  /// Seconds of input a client may bank ahead to absorb network jitter.
  final double maxBank;
  final double maxFrameDt;
  final int maxPerSecond;

  double _bank;
  int _lastSeq = 0;
  int _frames = 0;
  double _window = 0;

  /// Suspicious-behaviour counters for logging / kicking.
  int droppedForTime = 0, droppedForSeq = 0, droppedForRate = 0;

  InputGuard({this.maxBank = 0.25, this.maxFrameDt = 0.05, this.maxPerSecond = 250}) : _bank = maxBank;

  /// Call once per server tick with the real elapsed time.
  void tick(double dt) {
    _bank = clampD(_bank + dt, 0, maxBank);
    _window += dt;
    if (_window >= 1) {
      _window = 0;
      _frames = 0;
    }
  }

  /// Returns the sanitized input to apply, or null to drop it.
  PlayerInput? accept(PlayerInput i) {
    if (i.seq <= _lastSeq) {
      droppedForSeq++;
      return null;
    }
    if (++_frames > maxPerSecond) {
      droppedForRate++;
      return null;
    }
    final dt = i.dt.isFinite ? clampD(i.dt, 0, maxFrameDt) : 0.0;
    if (dt > _bank + 1e-6) {
      droppedForTime++;
      return null;
    }
    _bank -= dt;
    _lastSeq = i.seq;
    double f(double v) => v.isFinite ? v : 0;
    return i
      ..dt = dt
      ..yaw = wrapAngle(f(i.yaw))
      ..pitch = clampD(f(i.pitch), -1.5, 1.5)
      ..moveX = clampD(f(i.moveX), -1, 1)
      ..moveZ = clampD(f(i.moveZ), -1, 1)
      ..renderTick = f(i.renderTick);
  }

  /// True if this client looks like it is cheating rather than lagging.
  bool get suspicious => droppedForTime > 120 || droppedForRate > 200;
}
