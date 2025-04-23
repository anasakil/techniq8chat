// // lib/widgets/incoming_call_dialog.dart
// import 'package:flutter/material.dart';
// import 'package:techniq8chat/models/user_model.dart';
// import 'package:techniq8chat/screens/calls_screen.dart';
// import 'package:techniq8chat/services/webrtc_service.dart';

// class IncomingCallDialog extends StatelessWidget {
//   final User caller;
//   final CallType callType;
//   final VoidCallback onReject;

//   const IncomingCallDialog({
//     Key? key,
//     required this.caller,
//     required this.callType,
//     required this.onReject,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Dialog(
//       backgroundColor: Colors.transparent,
//       elevation: 0,
//       child: Container(
//         width: double.infinity,
//         padding: EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(16),
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // Call type indicator
//             Container(
//               width: 60,
//               height: 60,
//               decoration: BoxDecoration(
//                 color: const Color(0xFF2A64F6).withOpacity(0.1),
//                 shape: BoxShape.circle,
//               ),
//               child: Icon(
//                 callType == CallType.video ? Icons.videocam : Icons.call,
//                 color: const Color(0xFF2A64F6),
//                 size: 30,
//               ),
//             ),
//             SizedBox(height: 16),
            
//             // Caller info
//             Text(
//               'Incoming ${callType == CallType.video ? 'Video' : 'Audio'} Call',
//               style: TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//             SizedBox(height: 8),
            
//             // Caller name
//             Text(
//               caller.username,
//               style: TextStyle(
//                 fontSize: 22,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.black87,
//               ),
//             ),
//             SizedBox(height: 24),
            
//             // Call actions
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 // Reject button
//                 _buildActionButton(
//                   icon: Icons.call_end,
//                   color: Colors.red,
//                   label: 'Decline',
//                   onPressed: () {
//                     onReject();
//                     Navigator.of(context).pop();
//                   },
//                 ),
                
//                 // Accept button
//                 _buildActionButton(
//                   icon: callType == CallType.video ? Icons.videocam : Icons.call,
//                   color: Colors.green,
//                   label: 'Accept',
//                   onPressed: () {
//                     Navigator.of(context).pop();
//                     Navigator.of(context).push(
//                       MaterialPageRoute(
//                         builder: (context) => CallScreen(
//                           remoteUser: caller,
//                           callType: callType,
//                           isIncoming: true,
//                         ),
//                       ),
//                     );
//                   },
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildActionButton({
//     required IconData icon,
//     required Color color,
//     required String label,
//     required VoidCallback onPressed,
//   }) {
//     return Column(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Container(
//           width: 60,
//           height: 60,
//           decoration: BoxDecoration(
//             color: color,
//             shape: BoxShape.circle,
//           ),
//           child: IconButton(
//             icon: Icon(icon, color: Colors.white, size: 30),
//             onPressed: onPressed,
//           ),
//         ),
//         SizedBox(height: 8),
//         Text(
//           label,
//           style: TextStyle(
//             fontWeight: FontWeight.bold,
//             color: color,
//           ),
//         ),
//       ],
//     );
//   }
// }