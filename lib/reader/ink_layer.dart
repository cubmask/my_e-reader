import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../notes/ink_store.dart';

enum InkTool { pen, highlighter, eraser }

const inkPenColors = [0xFF212121, 0xFF1E5BD8, 0xFFD32F2F, 0xFF2E7D32];
const inkHighlighterColors = [0xFFFFEB3B, 0xFF69F0AE, 0xFF80D8FF, 0xFFFF80AB];

/// Pen mode state shared by every page of a PDF: whether drawing is on, the
/// tool and colour, and an undo history for this reading session.
class InkController extends ChangeNotifier {
  bool _enabled = false;
  InkTool _tool = InkTool.pen;
  int _penColor = inkPenColors.first;
  int _highlighterColor = inkHighlighterColors.first;
  final _undo = <_InkAction>[];

  bool get enabled => _enabled;
  InkTool get tool => _tool;
  int get color => _tool == InkTool.highlighter ? _highlighterColor : _penColor;
  bool get canUndo => _undo.isNotEmpty;

  set enabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  set tool(InkTool value) {
    _tool = value;
    notifyListeners();
  }

  set color(int value) {
    if (_tool == InkTool.highlighter) {
      _highlighterColor = value;
    } else {
      _penColor = value;
      if (_tool == InkTool.eraser) _tool = InkTool.pen;
    }
    notifyListeners();
  }

  /// The S Pen, Apple Pencil and Surface pen draw in pen mode; on desktop the
  /// mouse does too. Fingers always scroll and zoom.
  Set<PointerDeviceKind> get devices => {
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    if (Platform.isWindows || Platform.isMacOS) PointerDeviceKind.mouse,
  };

  void _record(_InkAction action) {
    _undo.add(action);
    notifyListeners();
  }

  Future<void> undo(InkStore store) async {
    if (_undo.isEmpty) return;
    final action = _undo.removeLast();
    notifyListeners();
    if (action.erased) {
      await store.restore(action.strokes);
    } else {
      await store.remove(action.strokes);
    }
  }
}

class _InkAction {
  _InkAction.drew(InkStroke stroke) : strokes = [stroke], erased = false;
  _InkAction.erased(this.strokes) : erased = true;

  final List<InkStroke> strokes;
  final bool erased;
}

/// Draws a page's strokes and, in pen mode, takes stylus input on it.
///
/// Placed over the page by pdfrx's page overlays. It never claims finger
/// touches, so the viewer still scrolls and zooms underneath.
class InkPageLayer extends StatefulWidget {
  const InkPageLayer({
    super.key,
    required this.bookId,
    required this.page,
    required this.store,
    required this.controller,
  });

  final String bookId;
  final int page;
  final InkStore store;
  final InkController controller;

  @override
  State<InkPageLayer> createState() => _InkPageLayerState();
}

class _InkPageLayerState extends State<InkPageLayer> {
  List<Offset>? _live;
  bool _erasing = false;
  final _erased = <InkStroke>[];
  double _pageWidth = 1;

  InkController get _ink => widget.controller;

  Offset _toPage(Offset local) => local / _pageWidth;

  bool _isEraser(PointerEvent e) =>
      _ink.tool == InkTool.eraser ||
      e.kind == PointerDeviceKind.invertedStylus ||
      e.buttons & kSecondaryStylusButton != 0;

  void _down(PointerEvent e) {
    _erasing = _isEraser(e);
    if (_erasing) {
      _erased.clear();
      _erase(e.localPosition);
    } else {
      setState(() => _live = [_toPage(e.localPosition)]);
    }
  }

  void _move(PointerEvent e) {
    if (_erasing) {
      _erase(e.localPosition);
    } else if (_live != null) {
      setState(() => _live = [..._live!, _toPage(e.localPosition)]);
    }
  }

  void _erase(Offset local) {
    final p = _toPage(local);
    final hit = [
      for (final s in widget.store.forPage(widget.bookId, widget.page))
        if (s.hits(p, 0.01)) s,
    ];
    if (hit.isEmpty) return;
    _erased.addAll(hit);
    widget.store.remove(hit);
  }

  void _end() {
    if (_erasing) {
      if (_erased.isNotEmpty) _ink._record(_InkAction.erased([..._erased]));
      _erased.clear();
      return;
    }
    final points = _live;
    if (points == null) return;
    final highlighter = _ink.tool == InkTool.highlighter;
    final stroke = widget.store.add(
      bookId: widget.bookId,
      page: widget.page,
      color: _ink.color,
      width: highlighter ? 0.02 : 0.003,
      points: points,
      highlighter: highlighter,
    );
    _ink._record(_InkAction.drew(stroke));
    setState(() => _live = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, _ink]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          _pageWidth = box.maxWidth;
          final highlighter = _ink.tool == InkTool.highlighter;
          final paint = IgnorePointer(
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _InkPainter(
                strokes: widget.store.forPage(widget.bookId, widget.page),
                live: _live,
                liveColor: _ink.color,
                liveWidth: highlighter ? 0.02 : 0.003,
                liveHighlighter: highlighter,
                scale: box.maxWidth,
              ),
            ),
          );
          if (!_ink.enabled) return paint;
          return RawGestureDetector(
            // Translucent: fingers fall through to the viewer below.
            behavior: HitTestBehavior.translucent,
            gestures: {
              _InkRecognizer:
                  GestureRecognizerFactoryWithHandlers<_InkRecognizer>(
                    () => _InkRecognizer(supportedDevices: _ink.devices),
                    (r) {
                      r
                        ..onDown = _down
                        ..onMove = _move
                        ..onEnd = _end;
                    },
                  ),
            },
            child: paint,
          );
        },
      ),
    );
  }
}

/// Claims a stylus pointer the moment it touches down, so the viewer does
/// not pan while you write.
class _InkRecognizer extends OneSequenceGestureRecognizer {
  _InkRecognizer({super.supportedDevices});

  void Function(PointerEvent)? onDown;
  void Function(PointerEvent)? onMove;
  VoidCallback? onEnd;
  int? _pointer;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _pointer == null && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    resolve(GestureDisposition.accepted);
    onDown?.call(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      onMove?.call(event);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _finish();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    super.rejectGesture(pointer);
    _finish();
  }

  void _finish() {
    if (_pointer == null) return;
    _pointer = null;
    onEnd?.call();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'ink';
}

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.strokes,
    required this.live,
    required this.liveColor,
    required this.liveWidth,
    required this.liveHighlighter,
    required this.scale,
  });

  final List<InkStroke> strokes;
  final List<Offset>? live;
  final int liveColor;
  final double liveWidth;
  final bool liveHighlighter;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _draw(canvas, s.points, s.color, s.width, s.highlighter);
    }
    final live = this.live;
    if (live != null) {
      _draw(canvas, live, liveColor, liveWidth, liveHighlighter);
    }
  }

  void _draw(
    Canvas canvas,
    List<Offset> points,
    int color,
    double width,
    bool highlighter,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = highlighter ? Color(color).withValues(alpha: 0.4) : Color(color)
      ..strokeWidth = width * scale
      ..strokeCap = highlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = highlighter ? BlendMode.multiply : BlendMode.srcOver;
    if (points.length == 1) {
      canvas.drawCircle(
        points.first * scale,
        width * scale / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(points[0].dx * scale, points[0].dy * scale);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * scale, p.dy * scale);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_InkPainter old) =>
      !identical(strokes, old.strokes) ||
      !identical(live, old.live) ||
      liveColor != old.liveColor ||
      liveWidth != old.liveWidth ||
      liveHighlighter != old.liveHighlighter ||
      scale != old.scale;
}

/// Tools shown while pen mode is on.
class InkToolbar extends StatelessWidget {
  const InkToolbar({super.key, required this.controller, required this.store});

  final InkController controller;
  final InkStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final colors = controller.tool == InkTool.highlighter
            ? inkHighlighterColors
            : inkPenColors;
        return Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<InkTool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: InkTool.pen,
                      icon: Icon(Icons.edit),
                      tooltip: 'Pen',
                    ),
                    ButtonSegment(
                      value: InkTool.highlighter,
                      icon: Icon(Icons.border_color),
                      tooltip: 'Highlighter',
                    ),
                    ButtonSegment(
                      value: InkTool.eraser,
                      icon: Icon(Icons.auto_fix_normal),
                      tooltip: 'Eraser',
                    ),
                  ],
                  selected: {controller.tool},
                  onSelectionChanged: (s) => controller.tool = s.first,
                ),
                const SizedBox(width: 8),
                for (final c in colors)
                  IconButton(
                    tooltip: 'Colour',
                    onPressed: () => controller.color = c,
                    icon: Icon(
                      controller.color == c && controller.tool != InkTool.eraser
                          ? Icons.radio_button_checked
                          : Icons.circle,
                      color: Color(c),
                    ),
                  ),
                IconButton(
                  tooltip: 'Undo',
                  onPressed: controller.canUndo
                      ? () => controller.undo(store)
                      : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Done',
                  onPressed: () => controller.enabled = false,
                  icon: const Icon(Icons.check),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
