// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'feedback.dart';
import 'theme.dart';
import 'theme_data.dart';

const Duration _kFadeDuration = const Duration(milliseconds: 200);
const Duration _kShowDuration = const Duration(milliseconds: 1500);

/// A material design tooltip.
///
/// Tooltips provide text labels that help explain the function of a button or
/// other user interface action. Wrap the button in a [Tooltip] widget to
/// show a label when the widget long pressed (or when the user takes some
/// other appropriate action).
///
/// Many widgets, such as [IconButton], [FloatingActionButton], and
/// [PopupMenuButton] have a `tooltip` property that, when non-null, causes the
/// widget to include a [Tooltip] in its build.
///
/// Tooltips improve the accessibility of visual widgets by proving a textual
/// representation of the widget, which, for example, can be vocalized by a
/// screen reader.
///
/// See also:
///
///  * <https://material.google.com/components/tooltips.html>
class Tooltip extends StatefulWidget {
  /// Creates a tooltip.
  ///
  /// By default, tooltips prefer to appear below the [child] widget when the
  /// user long presses on the widget.
  ///
  /// The [message] argument must not be null.
  const Tooltip({
    Key key,
    @required this.message,
    this.height: 32.0,
    this.padding: const EdgeInsets.symmetric(horizontal: 16.0),
    this.verticalOffset: 24.0,
    this.preferBelow: true,
    this.child,
  })
      : super(key: key);

  /// The text to display in the tooltip.
  final String message;

  /// The amount of vertical space the tooltip should occupy (inside its padding).
  final double height;

  /// The amount of space by which to inset the child.
  ///
  /// Defaults to 16.0 logical pixels in each direction.
  final EdgeInsetsGeometry padding;

  /// The amount of vertical distance between the widget and the displayed tooltip.
  final double verticalOffset;

  /// Whether the tooltip defaults to being displayed below the widget.
  ///
  /// Defaults to true. If there is insufficient space to display the tooltip in
  /// the preferred direction, the tooltip will be displayed in the opposite
  /// direction.
  final bool preferBelow;

  /// The widget below this widget in the tree.
  ///
  /// {@macro flutter.widgets.child}
  final Widget child;

  @override
  _TooltipState createState() => new _TooltipState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(new StringProperty('message', message, showName: false));
    description.add(new DoubleProperty('vertical offset', verticalOffset));
    description.add(new FlagProperty('position',
        value: preferBelow, ifTrue: 'below', ifFalse: 'above', showName: true));
  }
}

class _TooltipState extends SingleTickerProviderStateMixin<Tooltip> {
  AnimationController _controller;
  OverlayEntry _entry;
  Timer _timer;

  @override
  void initState() {
    super.initState();
    _controller = new AnimationController(duration: _kFadeDuration, vsync: this)
      ..addStatusListener(_handleStatusChanged);
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _removeEntry();
  }

  /// Shows the tooltip if it is not already visible.
  ///
  /// Returns `false` when the tooltip was already visible.
  bool ensureTooltipVisible() {
    if (_entry != null) {
      _timer?.cancel();
      _timer = null;
      _controller.forward();
      return false; // Already visible.
    }
    final RenderBox box = context.findRenderObject();
    final Offset target = box.localToGlobal(box.size.center(Offset.zero));
    // We create this widget outside of the overlay entry's builder to prevent
    // updated values from happening to leak into the overlay when the overlay
    // rebuilds.
    final Widget overlay = new _TooltipOverlay(
        message: widget.message,
        height: widget.height,
        padding: widget.padding,
        animation: new CurvedAnimation(
            parent: _controller, curve: Curves.fastOutSlowIn),
        target: target,
        verticalOffset: widget.verticalOffset,
        preferBelow: widget.preferBelow);
    _entry = new OverlayEntry(builder: (BuildContext context) => overlay);
    Overlay.of(context, debugRequiredFor: widget).insert(_entry);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
    _controller.forward();
    return true;
  }

  void _removeEntry() {
    assert(_entry != null);
    _timer?.cancel();
    _timer = null;
    _entry.remove();
    _entry = null;
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_handlePointerEvent);
  }

  void _handlePointerEvent(PointerEvent event) {
    assert(_entry != null);
    if (event is PointerUpEvent || event is PointerCancelEvent)
      _timer ??= new Timer(_kShowDuration, _controller.reverse);
    else if (event is PointerDownEvent) _controller.reverse();
  }

  @override
  void deactivate() {
    if (_entry != null) _controller.reverse();
    super.deactivate();
  }

  @override
  void dispose() {
    if (_entry != null) _removeEntry();
    _controller.dispose();
    super.dispose();
  }

  void _handleLongPress() {
    final bool tooltipCreated = ensureTooltipVisible();
    if (tooltipCreated) Feedback.forLongPress(context);
  }

  @override
  Widget build(BuildContext context) {
    assert(Overlay.of(context, debugRequiredFor: widget) != null);
    return new GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _handleLongPress,
      excludeFromSemantics: true,
      child: new Semantics(
        label: widget.message,
        child: widget.child,
      ),
    );
  }
}

/// A delegate for computing the layout of a tooltip to be displayed above or
/// bellow a target specified in the global coordinate system.
class _TooltipPositionDelegate extends SingleChildLayoutDelegate {
  /// Creates a delegate for computing the layout of a tooltip.
  ///
  /// The arguments must not be null.
  _TooltipPositionDelegate({
    @required this.target,
    @required this.verticalOffset,
    @required this.preferBelow,
  });

  /// The offset of the target the tooltip is positioned near in the global
  /// coordinate system.
  final Offset target;

  /// The amount of vertical distance between the target and the displayed
  /// tooltip.
  final double verticalOffset;

  /// Whether the tooltip defaults to being displayed below the widget.
  ///
  /// If there is insufficient space to display the tooltip in the preferred
  /// direction, the tooltip will be displayed in the opposite direction.
  final bool preferBelow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return positionDependentBox(
      size: size,
      childSize: childSize,
      target: target,
      verticalOffset: verticalOffset,
      preferBelow: preferBelow,
    );
  }

  @override
  bool shouldRelayout(_TooltipPositionDelegate oldDelegate) {
    return target != oldDelegate.target ||
        verticalOffset != oldDelegate.verticalOffset ||
        preferBelow != oldDelegate.preferBelow;
  }
}

class _TooltipOverlay extends StatelessWidget {
  const _TooltipOverlay({
    Key key,
    this.message,
    this.height,
    this.padding,
    this.animation,
    this.target,
    this.verticalOffset,
    this.preferBelow,
  })
      : super(key: key);

  final String message;
  final double height;
  final EdgeInsetsGeometry padding;
  final Animation<double> animation;
  final Offset target;
  final double verticalOffset;
  final bool preferBelow;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ThemeData darkTheme = new ThemeData(
      brightness: Brightness.dark,
      textTheme: theme.brightness == Brightness.dark
          ? theme.textTheme
          : theme.primaryTextTheme,
      platform: theme.platform,
    );
    return new Positioned.fill(
      child: new IgnorePointer(
        child: new CustomSingleChildLayout(
          delegate: new _TooltipPositionDelegate(
            target: target,
            verticalOffset: verticalOffset,
            preferBelow: preferBelow,
          ),
          child: new FadeTransition(
            opacity: animation,
            child: new Opacity(
              opacity: 0.9,
              child: new ConstrainedBox(
                constraints: new BoxConstraints(minHeight: height),
                child: new Container(
                  decoration: new BoxDecoration(
                    color: darkTheme.backgroundColor,
                    borderRadius: new BorderRadius.circular(2.0),
                  ),
                  padding: padding,
                  child: new Center(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: new Text(message, style: darkTheme.textTheme.body1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
