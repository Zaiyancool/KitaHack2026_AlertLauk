import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/comp_manager/WriteMng/CommentSubmit.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class CommentScreen extends StatefulWidget {
  final String reportId;
  final String title;

  const CommentScreen({
    super.key,
    required this.reportId,
    required this.title,
  });

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController commentCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  Uint8List? _selectedImageBytes;
  String? _selectedFileName;
  bool _isUploading = false;
  String? _previewImagePath;

  @override
  void dispose() {
    commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (kIsWeb) {
        final XFile? pickedFile = await _picker.pickImage(
          source: source,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );

        if (pickedFile != null) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _selectedImageBytes = bytes;
            _selectedFileName = pickedFile.name;
            _previewImagePath = pickedFile.path;
          });
        }
      } else {
        final XFile? pickedFile = await _picker.pickImage(
          source: source,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );

        if (pickedFile != null) {
          setState(() {
            _selectedImage = File(pickedFile.path);
            _selectedFileName = pickedFile.name;
            _previewImagePath = pickedFile.path;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
      _selectedFileName = null;
      _previewImagePath = null;
    });
  }

  Future<void> _handleSubmit() async {
    final text = commentCtrl.text.trim();
    
    if (text.isEmpty && _selectedImage == null && _selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a comment or select an image')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      String? imageUrl;
      
      if (_selectedImage != null) {
        imageUrl = await uploadCommentImage(_selectedImage!, widget.reportId);
      } else if (_selectedImageBytes != null && _selectedFileName != null) {
        imageUrl = await uploadCommentImageWeb(
          _selectedImageBytes!, 
          _selectedFileName!, 
          widget.reportId
        );
      }
      
      if (imageUrl == null && (_selectedImage != null || _selectedImageBytes != null)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload image')),
          );
          setState(() {
            _isUploading = false;
          });
          return;
        }
      }

      await submitComment(
        widget.reportId, 
        text.isEmpty ? 'Shared an image' : text, 
        imageUrl: imageUrl
      );

      commentCtrl.clear();
      setState(() {
        _selectedImage = null;
        _selectedImageBytes = null;
        _selectedFileName = null;
        _previewImagePath = null;
        _isUploading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting comment: $e')),
        );
      }
    }
  }

  Widget _buildImagePreview() {
    if (kIsWeb && _selectedImageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _selectedImageBytes!,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
        ),
      );
    } else if (_selectedImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          _selectedImage!,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // Helper method to parse comment data
  Map<String, dynamic> _parseComment(dynamic comment) {
    if (comment is Map) {
      return Map<String, dynamic>.from(comment);
    }
    if (comment is String) {
      return {
        'text': comment,
        'timestamp': '',
        'imageUrl': null,
      };
    }
    return {
      'text': '',
      'timestamp': '',
      'imageUrl': null,
    };
  }

  // Helper method to compare timestamps for sorting
  int _compareTimestamps(String aTime, String bTime) {
    if (aTime.isEmpty && bTime.isEmpty) return 0;
    if (aTime.isEmpty) return 1;
    if (bTime.isEmpty) return -1;
    return bTime.compareTo(aTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} (${widget.reportId})'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('comments_reports')
                  .doc(widget.reportId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('No additional info yet.'));
                }

                final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final comments = data['Comments'] ?? [];

                if (comments.isEmpty) {
                  return const Center(child: Text('No additional info yet.'));
                }

                // Parse all comments
                final parsedComments = <Map<String, dynamic>>[];
                for (var comment in comments) {
                  parsedComments.add(_parseComment(comment));
                }

                // Sort by timestamp (newest first)
                parsedComments.sort((a, b) {
                  final aTime = a['timestamp']?.toString() ?? '';
                  final bTime = b['timestamp']?.toString() ?? '';
                  return _compareTimestamps(aTime, bTime);
                });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: parsedComments.length,
                  itemBuilder: (context, index) {
                    final comment = parsedComments[index];
                    
                    final commentText = comment['text']?.toString() ?? '';
                    final imageUrl = comment['imageUrl'];
                    final timestamp = comment['timestamp']?.toString() ?? '';

                    return _buildCommentItem(commentText, imageUrl, timestamp);
                  },
                );
              },
            ),
          ),
          
          // Selected image preview
          if (_previewImagePath != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  _buildImagePreview(),
                  const SizedBox(width: 8),
                  const Text('Image selected'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearSelectedImage,
                  ),
                ],
              ),
            ),
          
          // Comment input section
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 55.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate),
                  onPressed: _isUploading ? null : _showImageSourceDialog,
                  tooltip: 'Add Image',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: commentCtrl,
                    enabled: !_isUploading,
                    decoration: const InputDecoration(
                      hintText: 'Write additional information...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                  ),
                ),
                const SizedBox(width: 8),
                _isUploading
                    ? const SizedBox(
                        width: 48,
                        height: 48,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _handleSubmit,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(String commentText, dynamic imageUrl, String timestamp) {
    final String? imageUrlString = imageUrl?.toString();
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.person, size: 20),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            if (commentText.isNotEmpty)
              Text(
                commentText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            
            if (imageUrlString != null && imageUrlString.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrlString,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.grey.shade200,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Error loading image: $error');
                    return Container(
                      height: 100,
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 40),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String timestamp) {
    if (timestamp.isEmpty) return '';
    
    try {
      final DateTime dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dt);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${dt.day}/${dt.month}/${dt.year}';
      }
    } catch (e) {
      return timestamp;
    }
  }
}
