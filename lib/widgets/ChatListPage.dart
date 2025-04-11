import 'package:flutter/material.dart';

class ChatPage extends StatelessWidget {
  final List<ChatItem> chats = [
    ChatItem(name: 'Stephan Louis', message: 'Hey, how are you', time: '10:30', avatar: Colors.pink, unread: true),
    ChatItem(name: 'Emily Clark', message: 'Okay, see you later', time: '1:24 PM', avatar: Colors.blue, unread: false),
    ChatItem(name: 'Michael Brown', message: 'Sure, I', time: 'Today', avatar: Colors.green, unread: false),
    ChatItem(name: 'Emma Wilson', message: 'Good morning', time: 'Yesterday', avatar: Colors.pink, unread: false),
    ChatItem(name: 'Oliver Taylor', message: 'Hello, long time no see', time: '9:45 AM', avatar: Colors.orange, unread: true),
    ChatItem(name: 'Liam Anderson', message: 'Hello, long time no see', time: 'Yesterday', avatar: Colors.purple, unread: false),
    ChatItem(name: 'Charlotte Martinez', message: 'Hey, are you free this weekend?', time: '3 days ago', avatar: Colors.red, unread: true),
    ChatItem(name: 'Ashley Martinez', message: 'Let\'s catch up soon', time: '5 days ago', avatar: Colors.brown, unread: false),
    ChatItem(name: 'Lauren Taylor', message: 'Project timeline updates', time: '5 days ago', avatar: Colors.yellow, unread: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search chat or something here',
                  prefixIcon: Icon(Icons.search),
                  fillColor: Colors.grey[200],
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  _buildSegmentButton('Personal', true),
                  SizedBox(width: 8),
                  _buildSegmentButton('Group', false),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: chats.length,
                itemBuilder: (context, index) => _buildChatItem(chats[index]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt_outlined), label: 'Status'),
          BottomNavigationBarItem(icon: Icon(Icons.call), label: 'Calls'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
        currentIndex: 0,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
      ),
    );
  }

  Widget _buildSegmentButton(String text, bool isSelected) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue : Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: isSelected ? Colors.white : Colors.black),
      ),
    );
  }

  Widget _buildChatItem(ChatItem chat) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: chat.avatar,
            child: Text(chat.name[0], style: TextStyle(color: Colors.white)),
          ),
          if (chat.unread)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(chat.name, style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(chat.time, style: TextStyle(color: Colors.grey, fontSize: 12)),
          if (chat.unread)
            Container(
              margin: EdgeInsets.only(top: 4),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('1', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
        ],
      ),
    );
  }
}

class ChatItem {
  final String name;
  final String message;
  final String time;
  final Color avatar;
  final bool unread;

  ChatItem({
    required this.name,
    required this.message,
    required this.time,
    required this.avatar,
    this.unread = false,
  });
}