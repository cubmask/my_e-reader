import 'package:flutter/material.dart';

/// Builds [builder] with a text controller that lives exactly as long as
/// this widget. A dialog keeps building through its closing animation, so a
/// controller disposed as soon as the dialog returns would still be in use.
class WithTextController extends StatefulWidget {
  const WithTextController({super.key, this.text, required this.builder});

  final String? text;
  final Widget Function(BuildContext context, TextEditingController controller)
  builder;

  @override
  State<WithTextController> createState() => _WithTextControllerState();
}

class _WithTextControllerState extends State<WithTextController> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
