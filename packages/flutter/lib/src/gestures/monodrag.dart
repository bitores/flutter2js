// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'arena.dart';
import 'constants.dart';
import 'drag_details.dart';
import 'events.dart';
import 'recognizer.dart';
import 'velocity_tracker.dart';

enum _DragState {
  ready,
  possible,
  accepted,
}

/// Signature for when a pointer that was previously in contact with the screen
/// and moving is no longer in contact with the screen.
///
/// The velocity at which the pointer was moving when it stopped contacting
/// the screen is available in the `details`.
///
/// See [DragGestureRecognizer.onEnd].
typedef void GestureDragEndCallback(DragEndDetails details);

/// Signature for when the pointer that previously triggered a
/// [GestureDragDownCallback] did not complete.
///
/// See [DragGestureRecognizer.onCancel].
typedef void GestureDragCancelCallback();

/// Recognizes movement.
///
/// In contrast to [MultiDragGestureRecognizer], [DragGestureRecognizer]
/// recognizes a single gesture sequence for all the pointers it watches, which
/// means that the recognizer has at most one drag sequence active at any given
/// time regardless of how many pointers are in contact with the screen.
///
/// [DragGestureRecognizer] is not intended to be used directly. Instead,
/// consider using one of its subclasses to recognize specific types for drag
/// gestures.
///
/// See also:
///
///  * [HorizontalDragGestureRecognizer], for left and right drags.
///  * [VerticalDragGestureRecognizer], for up and down drags.
///  * [PanGestureRecognizer], for drags that are not locked to a single axis.
abstract class DragGestureRecognizer extends OneSequenceGestureRecognizer {
  /// Initialize the object.
  DragGestureRecognizer({Object debugOwner}) : super(debugOwner: debugOwner);

  /// A pointer has contacted the screen and might begin to move.
  ///
  /// The position of the pointer is provided in the callback's `details`
  /// argument, which is a [DragDownDetails] object.
  GestureDragDownCallback onDown;

  /// A pointer has contacted the screen and has begun to move.
  ///
  /// The position of the pointer is provided in the callback's `details`
  /// argument, which is a [DragStartDetails] object.
  GestureDragStartCallback onStart;

  /// A pointer that is in contact with the screen and moving has moved again.
  ///
  /// The distance travelled by the pointer since the last update is provided in
  /// the callback's `details` argument, which is a [DragUpdateDetails] object.
  GestureDragUpdateCallback onUpdate;

  /// A pointer that was previously in contact with the screen and moving is no
  /// longer in contact with the screen and was moving at a specific velocity
  /// when it stopped contacting the screen.
  ///
  /// The velocity is provided in the callback's `details` argument, which is a
  /// [DragEndDetails] object.
  GestureDragEndCallback onEnd;

  /// The pointer that previously triggered [onDown] did not complete.
  GestureDragCancelCallback onCancel;

  /// The minimum distance an input pointer drag must have moved to
  /// to be considered a fling gesture.
  ///
  /// This value is typically compared with the distance traveled along the
  /// scrolling axis. If null then [kTouchSlop] is used.
  double minFlingDistance;

  /// The minimum velocity for an input pointer drag to be considered fling.
  ///
  /// This value is typically compared with the magnitude of fling gesture's
  /// velocity along the scrolling axis. If null then [kMinFlingVelocity]
  /// is used.
  double minFlingVelocity;

  /// Fling velocity magnitudes will be clamped to this value.
  ///
  /// If null then [kMaxFlingVelocity] is used.
  double maxFlingVelocity;

  _DragState _state = _DragState.ready;
  Offset _initialPosition;
  Offset _pendingDragOffset;
  Duration _lastPendingEventTimestamp;

  bool _isFlingGesture(VelocityEstimate estimate);

  Offset _getDeltaForDetails(Offset delta);

  double _getPrimaryValueFromOffset(Offset value);

  bool get _hasSufficientPendingDragDeltaToAccept;

  final Map<int, VelocityTracker> _velocityTrackers = <int, VelocityTracker>{};

  @override
  void addPointer(PointerEvent event) {
    startTrackingPointer(event.pointer);
    _velocityTrackers[event.pointer] = new VelocityTracker();
    if (_state == _DragState.ready) {
      _state = _DragState.possible;
      _initialPosition = event.position;
      _pendingDragOffset = Offset.zero;
      _lastPendingEventTimestamp = event.timeStamp;
      if (onDown != null)
        invokeCallback<Null>('onDown', () {
          onDown(new DragDownDetails(globalPosition: _initialPosition));
        }); // ignore: STRONG_MODE_INVALID_CAST_FUNCTION_EXPR, https://github.com/dart-lang/sdk/issues/27504
    } else if (_state == _DragState.accepted) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    assert(_state != _DragState.ready);
    if (!event.synthesized &&
        (event is PointerDownEvent || event is PointerMoveEvent)) {
      final VelocityTracker tracker = _velocityTrackers[event.pointer];
      assert(tracker != null);
      tracker.addPosition(event.timeStamp, event.position);
    }

    if (event is PointerMoveEvent) {
      final Offset delta = event.delta;
      if (_state == _DragState.accepted) {
        if (onUpdate != null) {
          invokeCallback<Null>('onUpdate', () {
            onUpdate(new DragUpdateDetails(
              // ignore: STRONG_MODE_INVALID_CAST_FUNCTION_EXPR, https://github.com/dart-lang/sdk/issues/27504
              sourceTimeStamp: event.timeStamp,
              delta: _getDeltaForDetails(delta),
              primaryDelta: _getPrimaryValueFromOffset(delta),
              globalPosition: event.position,
            ));
          });
        }
      } else {
        _pendingDragOffset += delta;
        _lastPendingEventTimestamp = event.timeStamp;
        if (_hasSufficientPendingDragDeltaToAccept)
          resolve(GestureDisposition.accepted);
      }
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  @override
  void acceptGesture(int pointer) {
    if (_state != _DragState.accepted) {
      _state = _DragState.accepted;
      final Offset delta = _pendingDragOffset;
      final Duration timestamp = _lastPendingEventTimestamp;
      _pendingDragOffset = Offset.zero;
      _lastPendingEventTimestamp = null;
      if (onStart != null) {
        invokeCallback<Null>('onStart', () {
          onStart(new DragStartDetails(
            // ignore: STRONG_MODE_INVALID_CAST_FUNCTION_EXPR, https://github.com/dart-lang/sdk/issues/27504
            sourceTimeStamp: timestamp,
            globalPosition: _initialPosition,
          ));
        });
      }
      if (delta != Offset.zero && onUpdate != null) {
        invokeCallback<Null>('onUpdate', () {
          onUpdate(new DragUpdateDetails(
            // ignore: STRONG_MODE_INVALID_CAST_FUNCTION_EXPR, https://github.com/dart-lang/sdk/issues/27504
            sourceTimeStamp: timestamp,
            delta: _getDeltaForDetails(delta),
            primaryDelta: _getPrimaryValueFromOffset(delta),
            globalPosition: _initialPosition,
          ));
        });
      }
    }
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (_state == _DragState.possible) {
      resolve(GestureDisposition.rejected);
      _state = _DragState.ready;
      if (onCancel != null)
        invokeCallback<Null>('onCancel',
            onCancel); // ignore: STRONG_MODE_INVALID_CAST_FUNCTION_EXPR, https://github.com/dart-lang/sdk/issues/27504
      return;
    }
    final bool wasAccepted = (_state == _DragState.accepted);
    _state = _DragState.ready;
    if (wasAccepted && onEnd != null) {
      final VelocityTracker tracker = _velocityTrackers[pointer];
      assert(tracker != null);

      final VelocityEstimate estimate = tracker.getVelocityEstimate();
      if (estimate != null && _isFlingGesture(estimate)) {
        final Velocity velocity =
            new Velocity(pixelsPerSecond: estimate.pixelsPerSecond)
                .clampMagnitude(minFlingVelocity ?? kMinFlingVelocity,
                    maxFlingVelocity ?? kMaxFlingVelocity);
        invokeCallback<Null>('onEnd', () {
          onEnd(new DragEndDetails(
            // ignore: STRONG_MODE_INVALID_CAST_FUNCTION_EXPR, https://github.com/dart-lang/sdk/issues/27504
            velocity: velocity,
            primaryVelocity:
                _getPrimaryValueFromOffset(velocity.pixelsPerSecond),
          ));
        }, debugReport: () {
          return '$estimate; fling at $velocity.';
        });
      } else {
        invokeCallback<Null>('onEnd', () {
          onEnd(new DragEndDetails(
            // ignore: STRONG_MODE_INVALID_CAST_FUNCTION_EXPR, https://github.com/dart-lang/sdk/issues/27504
            velocity: Velocity.zero,
            primaryVelocity: 0.0,
          ));
        }, debugReport: () {
          if (estimate == null) return 'Could not estimate velocity.';
          return '$estimate; judged to not be a fling.';
        });
      }
    }
    _velocityTrackers.clear();
  }

  @override
  void dispose() {
    _velocityTrackers.clear();
    super.dispose();
  }
}

/// Recognizes movement in the vertical direction.
///
/// Used for vertical scrolling.
///
/// See also:
///
///  * [HorizontalDragGestureRecognizer], for a similar recognizer but for
///    horizontal movement.
///  * [MultiDragGestureRecognizer], for a family of gesture recognizers that
///    track each touch point independently.
class VerticalDragGestureRecognizer extends DragGestureRecognizer {
  /// Create a gesture recognizer for interactions in the vertical axis.
  VerticalDragGestureRecognizer({Object debugOwner})
      : super(debugOwner: debugOwner);

  @override
  bool _isFlingGesture(VelocityEstimate estimate) {
    final double minVelocity = minFlingVelocity ?? kMinFlingVelocity;
    final double minDistance = minFlingDistance ?? kTouchSlop;
    return estimate.pixelsPerSecond.dy.abs() > minVelocity &&
        estimate.offset.dy.abs() > minDistance;
  }

  @override
  bool get _hasSufficientPendingDragDeltaToAccept =>
      _pendingDragOffset.dy.abs() > kTouchSlop;

  @override
  Offset _getDeltaForDetails(Offset delta) => new Offset(0.0, delta.dy);

  @override
  double _getPrimaryValueFromOffset(Offset value) => value.dy;

  @override
  String get debugDescription => 'vertical drag';
}

/// Recognizes movement in the horizontal direction.
///
/// Used for horizontal scrolling.
///
/// See also:
///
///  * [VerticalDragGestureRecognizer], for a similar recognizer but for
///    vertical movement.
///  * [MultiDragGestureRecognizer], for a family of gesture recognizers that
///    track each touch point independently.
class HorizontalDragGestureRecognizer extends DragGestureRecognizer {
  /// Create a gesture recognizer for interactions in the horizontal axis.
  HorizontalDragGestureRecognizer({Object debugOwner})
      : super(debugOwner: debugOwner);

  @override
  bool _isFlingGesture(VelocityEstimate estimate) {
    final double minVelocity = minFlingVelocity ?? kMinFlingVelocity;
    final double minDistance = minFlingDistance ?? kTouchSlop;
    return estimate.pixelsPerSecond.dx.abs() > minVelocity &&
        estimate.offset.dx.abs() > minDistance;
  }

  @override
  bool get _hasSufficientPendingDragDeltaToAccept =>
      _pendingDragOffset.dx.abs() > kTouchSlop;

  @override
  Offset _getDeltaForDetails(Offset delta) => new Offset(delta.dx, 0.0);

  @override
  double _getPrimaryValueFromOffset(Offset value) => value.dx;

  @override
  String get debugDescription => 'horizontal drag';
}

/// Recognizes movement both horizontally and vertically.
///
/// See also:
///
///  * [ImmediateMultiDragGestureRecognizer], for a similar recognizer that
///    tracks each touch point independently.
///  * [DelayedMultiDragGestureRecognizer], for a similar recognizer that
///    tracks each touch point independently, but that doesn't start until
///    some time has passed.
class PanGestureRecognizer extends DragGestureRecognizer {
  /// Create a gesture recognizer for tracking movement on a plane.
  PanGestureRecognizer({Object debugOwner}) : super(debugOwner: debugOwner);

  @override
  bool _isFlingGesture(VelocityEstimate estimate) {
    final double minVelocity = minFlingVelocity ?? kMinFlingVelocity;
    final double minDistance = minFlingDistance ?? kTouchSlop;
    return estimate.pixelsPerSecond.distanceSquared >
            minVelocity * minVelocity &&
        estimate.offset.distanceSquared > minDistance * minDistance;
  }

  @override
  bool get _hasSufficientPendingDragDeltaToAccept {
    return _pendingDragOffset.distance > kPanSlop;
  }

  @override
  Offset _getDeltaForDetails(Offset delta) => delta;

  @override
  double _getPrimaryValueFromOffset(Offset value) => null;

  @override
  String get debugDescription => 'pan';
}
