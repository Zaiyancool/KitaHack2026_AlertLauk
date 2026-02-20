import 'package:flutter/material.dart';

// class MediaUploadButtons extends StatelessWidget {
//   final VoidCallback onPhotoPressed;
//   final VoidCallback onVideoPressed;
//   final VoidCallback onFilePressed;

//   const MediaUploadButtons({
//     super.key,
//     required this.onPhotoPressed,
//     required this.onVideoPressed,
//     required this.onFilePressed,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 8.0),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//         children: [
//           _HoverButton(
//             icon: Icons.photo,
//             label: "Photo",
//             onPressed: onPhotoPressed,
//           ),
//           _HoverButton(
//             icon: Icons.videocam,
//             label: "Video",
//             onPressed: onVideoPressed,
//           ),
//           _HoverButton(
//             icon: Icons.attach_file,
//             label: "File",
//             onPressed: onFilePressed,
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _HoverButton extends StatefulWidget {
//   final IconData icon;
//   final String label;
//   final VoidCallback onPressed;

//   const _HoverButton({
//     required this.icon,
//     required this.label,
//     required this.onPressed,
//   });

//   @override
//   State<_HoverButton> createState() => _HoverButtonState();
// }

// class _HoverButtonState extends State<_HoverButton> {
//   bool _isHovered = false;
  

//   @override
//   Widget build(BuildContext context) {
//     return MouseRegion(
//       onEnter: (_) {
//         debugPrint("Hovered over ${widget.label}");
//         setState(() => _isHovered = true);
//       },

//       onExit: (_) => setState(() => _isHovered = false),
//       child: ElevatedButton(
//         onPressed: widget.onPressed,
//         style: ElevatedButton.styleFrom(backgroundColor: Colors.white24),
//         child: Row(
//           children: [
//             Icon(widget.icon),
//             AnimatedSwitcher(
//               duration: Duration(milliseconds: 200),
//               child: _isHovered
//                   ? Padding(
//                       padding: const EdgeInsets.only(left: 8.0),
//                       child: Text(widget.label),
//                     )
//                   : SizedBox.shrink(),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }


class MediaUploadButtons extends StatelessWidget {
  final VoidCallback onPhotoPressed;
  final VoidCallback onVideoPressed;
  final VoidCallback onFilePressed;

  const MediaUploadButtons({
    super.key,
    required this.onPhotoPressed,
    required this.onVideoPressed,
    required this.onFilePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed : () {
              debugPrint("Photo button pressed");
              onPhotoPressed();
            },
            icon: Icon(Icons.photo, color: Colors.white),
            tooltip: 'Send Photo',
          ),
          IconButton(
            onPressed: () {
              debugPrint("Video button pressed");
              onVideoPressed();
            },
            icon: Icon(Icons.videocam, color: Colors.white),
            tooltip: 'Send Video',
          ),
          IconButton(
            onPressed: () {
              debugPrint("File button pressed");
              onFilePressed();
            },
            icon: Icon(Icons.attach_file, color: Colors.white),
            tooltip: 'Send File',
          ),
        ],
      ),
    );
  }
}