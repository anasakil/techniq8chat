// screens/calls_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:techniq8chat/screens/users_list_screen.dart';

class CallsScreen extends StatefulWidget {
  @override
  _CallsScreenState createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<CallLog> _recentCalls = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDummyCallData();
  }

  void _loadDummyCallData() {
    // In a real app, this would load from a service
    setState(() {
      _isLoading = true;
    });

    // Simulate network delay
    Future.delayed(Duration(milliseconds: 500), () {
      setState(() {
        _recentCalls = [];
        _isLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 16,
        centerTitle: false,
        title: Text(
          'Calls',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: Colors.black87),
            onPressed: () {
              // Search functionality placeholder
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF2A64F6),
          labelColor: const Color(0xFF2A64F6),
          unselectedLabelColor: Colors.grey[600],
          tabs: [
            Tab(text: 'Recent'),
            Tab(text: 'Missed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Recent calls tab
          _isLoading
              ? Center(
                  child:
                      CircularProgressIndicator(color: const Color(0xFF2A64F6)))
              : _buildCallsList(_recentCalls),

          // Missed calls tab
          _isLoading
              ? Center(
                  child:
                      CircularProgressIndicator(color: const Color(0xFF2A64F6)))
              : _buildCallsList(
                  _recentCalls.where((call) => call.missed).toList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // New call functionality placeholder
        },
        backgroundColor: const Color(0xFF2A64F6),
        child: Icon(Icons.call, color: Colors.white),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildCallsList(List<CallLog> calls) {
    if (calls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.call_outlined,
              size: 100,
              color: Colors.grey[300],
            ),
            SizedBox(height: 24),
            Text(
              'No call history',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Start a new call by tapping the button below',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 15),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(top: 8),
      itemCount: calls.length,
      itemBuilder: (context, index) {
        return _buildCallItem(calls[index]);
      },
    );
  }

  Widget _buildCallItem(CallLog call) {
    // Call icon based on type and missed status
    IconData callIcon;
    Color iconColor;

    if (call.callType == CallType.incoming) {
      if (call.missed) {
        callIcon = Icons.call_missed;
        iconColor = Colors.red;
      } else {
        callIcon = Icons.call_received;
        iconColor = Colors.green;
      }
    } else {
      callIcon = Icons.call_made;
      iconColor = const Color(0xFF2A64F6);
    }

    return InkWell(
      onTap: () {
        // Call details or callback functionality
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
              backgroundImage: call.profilePicture != null
                  ? NetworkImage(call.profilePicture!)
                  : null,
              child: call.profilePicture == null && call.name.isNotEmpty
                  ? Text(
                      call.name[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2A64F6),
                      ),
                    )
                  : null,
            ),
            SizedBox(width: 16),

            // Call details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name and time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          call.name,
                          style: TextStyle(
                            fontWeight:
                                call.missed ? FontWeight.bold : FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        _formatCallTime(call.callTime),
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 4),

                  // Call info and icon
                  Row(
                    children: [
                      Icon(
                        callIcon,
                        size: 16,
                        color: iconColor,
                      ),
                      SizedBox(width: 8),
                      Text(
                        call.missed
                            ? 'Missed Call'
                            : call.callDuration != null
                                ? _formatDuration(call.callDuration!)
                                : '',
                        style: TextStyle(
                          color: call.missed ? Colors.red : Colors.grey[600],
                          fontWeight:
                              call.missed ? FontWeight.w500 : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Call button
            IconButton(
              icon: Icon(Icons.call, color: const Color(0xFF2A64F6)),
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => UsersListScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatCallTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final dateToCheck = DateTime(time.year, time.month, time.day);

    if (dateToCheck == today) {
      return DateFormat.jm().format(time); // e.g., 5:08 PM
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else if (now.difference(time).inDays < 7) {
      return DateFormat('EEEE').format(time); // e.g., Monday
    } else {
      return DateFormat.MMMd().format(time); // e.g., Jan 20
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    }
  }
}

// Model classes
enum CallType { incoming, outgoing }

class CallLog {
  final String name;
  final String? profilePicture;
  final CallType callType;
  final DateTime callTime;
  final bool missed;
  final Duration? callDuration;

  CallLog({
    required this.name,
    this.profilePicture,
    required this.callType,
    required this.callTime,
    required this.missed,
    this.callDuration,
  });
}
