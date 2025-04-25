// widgets/floating_call_button.dart
import 'package:flutter/material.dart';
import 'package:techniq8chat/services/call_manager.dart';

class FloatingCallButton extends StatefulWidget {
  final String userId;
  final String username;
  final Function(CallType) onCallInitiated;

  const FloatingCallButton({
    Key? key,
    required this.userId,
    required this.username,
    required this.onCallInitiated,
  }) : super(key: key);

  @override
  _FloatingCallButtonState createState() => _FloatingCallButtonState();
}

class _FloatingCallButtonState extends State<FloatingCallButton> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Video call button - only shown when expanded
        if (_isExpanded)
          SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
            )),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: FloatingActionButton(
                heroTag: 'videoCall',
                onPressed: () {
                  _toggleExpanded();
                  widget.onCallInitiated(CallType.video);
                },
                backgroundColor: Colors.blue,
                mini: true,
                child: Icon(Icons.videocam, color: Colors.white),
              ),
            ),
          ),

        // Audio call button - only shown when expanded
        if (_isExpanded)
          SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            )),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: FloatingActionButton(
                heroTag: 'audioCall',
                onPressed: () {
                  _toggleExpanded();
                  widget.onCallInitiated(CallType.audio);
                },
                backgroundColor: Colors.green,
                mini: true,
                child: Icon(Icons.call, color: Colors.white),
              ),
            ),
          ),

        // Main call button - toggles expanded state
        FloatingActionButton(
          heroTag: 'mainCall',
          onPressed: _toggleExpanded,
          backgroundColor: const Color(0xFF2A64F6),
          child: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _animationController,
          ),
        ),
      ],
    );
  }
}