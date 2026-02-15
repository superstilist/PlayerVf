import 'package:flutter/material.dart';

class ShowUpControl extends StatefulWidget {
  final bool initialVisibility;
  final Widget child;
  
  const ShowUpControl({
    super.key,
    this.initialVisibility = true,
    required this.child,
  });

  @override
  State<ShowUpControl> createState() => _ShowUpControlState();
}

class _ShowUpControlState extends State<ShowUpControl> {
  late bool _isVisible;

  @override
  void initState() {
    super.initState();
    _isVisible = widget.initialVisibility;
  }

  void _toggleVisibility() {
    setState(() {
      _isVisible = !_isVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_isVisible) widget.child,
        IconButton(
          icon: Icon(
            _isVisible ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: _toggleVisibility,
        ),
      ],
    );
  }
}