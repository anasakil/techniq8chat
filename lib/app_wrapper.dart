// app_wrapper.dart
import 'package:flutter/material.dart';
import 'package:techniq8chat/widgets/call_handler.dart';

class AppWrapper extends StatelessWidget {
  final Widget child;

  const AppWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Wrap the entire app with a CallHandler to ensure all screens can show incoming calls
    return CallHandler(
      child: child,
    );
  }
}