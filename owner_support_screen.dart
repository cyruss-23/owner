import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';

import 'api_service.dart';

class OwnerSupportScreen extends StatefulWidget {
  const OwnerSupportScreen({Key? key}) : super(key: key);

  @override
  State<OwnerSupportScreen> createState() => _OwnerSupportScreenState();
}

class _OwnerSupportScreenState extends State<OwnerSupportScreen> {
  bool _isLoading = true;
  List<dynamic> _tickets = [];
  String? _ownerId;
  String? _userId;
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);
    try {
      final session = await ApiService.getUserSession();
      _userEmail = session['email']?.toString() ?? '';
      _userId = session['userId']?.toString();

      final ownerRes = await http.get(Uri.parse('https://parkfro.com//API.php?table=parking_space_owners'));
      if (ownerRes.statusCode == 200) {
        final ownerData = json.decode(ownerRes.body);
        if (ownerData['status'] == true && ownerData['data'] != null) {
          for (var owner in ownerData['data']) {
            if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase() ||
                owner['user_id']?.toString() == session['userId']) {
              _ownerId = owner['id'].toString();
              break;
            }
          }
          _ownerId ??= (ownerData['data'] as List).isNotEmpty ? ownerData['data'][0]['id'].toString() : '1';
        }
      }

      if (_ownerId != null) {
        final ticketRes = await http.get(Uri.parse('https://parkfro.com//API.php?table=support_tickets'));
        if (ticketRes.statusCode == 200) {
          final ticketData = json.decode(ticketRes.body);
          if (ticketData['status'] == true && ticketData['data'] != null) {
            final allTickets = ticketData['data'] as List;
            setState(() {
              _tickets = allTickets.where((t) => t['owner_id'].toString() == _ownerId).toList();
              _tickets.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading tickets: $e');
      _showSnackBar('Failed to load support tickets.', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _closeTicket(Map<String, dynamic> ticket) async {
    if (ticket['status']?.toString().toLowerCase() == 'closed') {
      _showSnackBar('This ticket is already closed.', Colors.orange);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Close Ticket', style: TextStyle(color: Colors.black)),
        content: Text('Are you sure you want to close this support ticket?', style: TextStyle(color: Colors.grey.shade700)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close Ticket', style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.put(
        Uri.parse('https://parkfro.com//API.php?table=support_tickets'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': ticket['id'],
          'status': 'closed',
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar('Ticket closed successfully.', Colors.green);
        _fetchTickets();
      } else {
        _showSnackBar('Failed to close ticket.', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error.', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showChatDialog(Map<String, dynamic> ticket) {
    final TextEditingController msgCtrl = TextEditingController();
    List<dynamic> messages = [];
    bool isLoadingMsgs = true;
    bool isSending = false;
    final ScrollController scrollCtrl = ScrollController();

    String ticketStatus = ticket['status']?.toString().toLowerCase() ?? 'open';
    MaterialColor statusColor = ticketStatus == 'closed' ? Colors.grey : Colors.green;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final isMobile = MediaQuery.of(dialogCtx).size.width < 600;

        return StatefulBuilder(
          builder: (context, setDialogState) {

            Future<void> fetchMessages() async {
              try {
                final res = await http.get(Uri.parse('https://parkfro.com//API.php?table=support_messages'));
                if (res.statusCode == 200) {
                  final data = json.decode(res.body);
                  if (data['status'] == true && data['data'] != null) {
                    final allMsgs = data['data'] as List;
                    final ticketMsgs = allMsgs.where((m) => m['ticket_id'].toString() == ticket['id'].toString()).toList();
                    ticketMsgs.sort((a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''));

                    if (mounted) {
                      setDialogState(() {
                        messages = ticketMsgs;
                        isLoadingMsgs = false;
                      });
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (scrollCtrl.hasClients) {
                          scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        }
                      });
                    }
                  }
                }
              } catch (e) {
                if (mounted) setDialogState(() => isLoadingMsgs = false);
              }
            }

            Future<void> sendMessage() async {
              if (msgCtrl.text.trim().isEmpty) return;

              setDialogState(() => isSending = true);
              try {
                final response = await http.post(
                  Uri.parse('https://parkfro.com//API.php?table=support_messages'),
                  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                  body: {
                    'ticket_id': ticket['id'].toString(),
                    'sender_id': _userId ?? _ownerId ?? '1',
                    'sender_type': 'owner',
                    'message': msgCtrl.text.trim(),
                    'is_read': '0',
                  },
                );

                if (response.statusCode == 200) {
                  msgCtrl.clear();
                  await fetchMessages();
                } else {
                  _showSnackBar('Failed to send message.', Colors.red);
                }
              } catch (e) {
                _showSnackBar('Network error.', Colors.red);
              } finally {
                if (mounted) setDialogState(() => isSending = false);
              }
            }

            if (isLoadingMsgs && messages.isEmpty) {
              fetchMessages();
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: EdgeInsets.all(isMobile ? 10 : 20),
              child: SizedBox(
                width: isMobile ? double.infinity : 600,
                height: MediaQuery.of(dialogCtx).size.height * 0.8,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // --- FIX: Wrapped the Ticket text in Flexible to prevent 0.869px overflow ---
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'Ticket #${ticket['ticket_number']}',
                                        style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('|', style: TextStyle(color: Colors.grey.shade400)),
                                    const SizedBox(width: 8),
                                    Icon(Icons.circle, color: statusColor, size: 10),
                                    const SizedBox(width: 4),
                                    Text(ticketStatus[0].toUpperCase() + ticketStatus.substring(1), style: TextStyle(color: statusColor.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(ticket['subject'] ?? 'No Subject', style: TextStyle(color: Colors.grey.shade600, fontSize: 13), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(dialogCtx)),
                        ],
                      ),
                    ),

                    Expanded(
                      child: isLoadingMsgs
                          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                          : messages.isEmpty
                          ? Center(child: Text('No messages yet. Say hello!', style: TextStyle(color: Colors.grey.shade600)))
                          : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(20),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final bool isMe = msg['sender_type']?.toString().toLowerCase() == 'owner';

                          String timeString = msg['created_at'] ?? '';
                          try {
                            DateTime dt = DateTime.parse(timeString);
                            timeString = DateFormat('M/d/yyyy, h:mm:ss a').format(dt);
                          } catch (_) {}

                          return _buildChatBubble(msg['message'] ?? '', timeString, isMe);
                        },
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.grey.shade300)),
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: msgCtrl,
                              style: const TextStyle(color: Colors.black),
                              enabled: ticketStatus != 'closed',
                              decoration: InputDecoration(
                                hintText: ticketStatus == 'closed' ? 'Ticket closed. Cannot send messages.' : 'Type your message...',
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                filled: true, fillColor: Colors.grey.shade100,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                              onSubmitted: (_) => sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: (ticketStatus == 'closed' || isSending) ? null : sendMessage,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: isSending
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Send', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChatBubble(String text, String time, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(isMe ? 'You' : 'Support Team', style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isMe ? Colors.blue.shade100 : Colors.grey.shade300),
            ),
            child: Text(text, style: const TextStyle(color: Colors.black87, fontSize: 14)),
          ),
          const SizedBox(height: 6),
          Text(time, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
        ],
      ),
    );
  }

  void _showCreateTicketDialog() {
    final subjectCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    String category = 'Select Category';
    final categoryOptions = ['Select Category', 'Technical Issue', 'Billing & Payments', 'Parking Issue', 'Account Related', 'General Inquiry', 'Other'];
    String priority = 'Medium';
    final priorityOptions = ['Low', 'Medium', 'High', 'Urgent'];

    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final isMobile = MediaQuery.of(dialogCtx).size.width < 600;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                width: isMobile ? double.infinity : 600,
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- FIX: Wrapped Title in Expanded to prevent overflow ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text('Create New Support Ticket', style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          ),
                          IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(dialogCtx)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      _buildDialogInput('Subject *', subjectCtrl, 'Brief summary of your issue'),
                      const SizedBox(height: 16),

                      if (isMobile) ...[
                        _buildDialogDropdown('Category *', category, categoryOptions, (val) => setDialogState(() => category = val!)),
                        const SizedBox(height: 16),
                        _buildDialogDropdown('Priority', priority, priorityOptions, (val) => setDialogState(() => priority = val!)),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(child: _buildDialogDropdown('Category *', category, categoryOptions, (val) => setDialogState(() => category = val!))),
                            const SizedBox(width: 16),
                            Expanded(child: _buildDialogDropdown('Priority', priority, priorityOptions, (val) => setDialogState(() => priority = val!))),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      _buildDialogInput('Describe the Issue *', descCtrl, 'Please provide detailed information about your issue...', maxLines: 4),
                      const SizedBox(height: 4),
                      Text('Minimum 10 characters', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),

                      const SizedBox(height: 32),
                      Wrap(
                        spacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isSaving ? null : () async {
                              if (subjectCtrl.text.isEmpty || category == 'Select Category' || descCtrl.text.trim().length < 10) {
                                _showSnackBar('Please fill all required fields correctly.', Colors.orange);
                                return;
                              }

                              setDialogState(() => isSaving = true);
                              try {
                                final uri = Uri.parse('https://parkfro.com//API.php?table=support_tickets');

                                String dbCategory = category.toLowerCase().replaceAll(' & ', '_').replaceAll(' ', '_');
                                final now = DateTime.now();
                                final ticketNum = "PKH${now.year}${now.month.toString().padLeft(2, '0')}${Random().nextInt(9999).toString().padLeft(4, '0')}";

                                final response = await http.post(
                                    uri,
                                    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                                    body: {
                                      'owner_id': _ownerId ?? '1',
                                      'ticket_number': ticketNum,
                                      'subject': subjectCtrl.text,
                                      'category': dbCategory,
                                      'description': descCtrl.text,
                                      'priority': priority.toLowerCase(),
                                      'status': 'open',
                                    }
                                );

                                if (response.statusCode == 200) {
                                  Navigator.pop(dialogCtx);
                                  _showSnackBar('Ticket submitted successfully!', Colors.green);
                                  _fetchTickets();
                                } else {
                                  _showSnackBar('Server Error.', Colors.red);
                                }
                              } catch (e) {
                                _showSnackBar('Network Error.', Colors.red);
                              } finally {
                                if (mounted) setDialogState(() => isSaving = false);
                              }
                            },
                            icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file, color: Colors.white, size: 20),
                            label: Text(isSaving ? 'Submitting...' : 'Submit Ticket', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('Cancel', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDialogInput(String label, TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade500),
            filled: true, fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade400)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildDialogDropdown(String label, String value, List<String> options, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value, isExpanded: true, dropdownColor: Colors.white,
              style: const TextStyle(color: Colors.black, fontSize: 14),
              items: options.map((String opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: const [
                          Icon(Icons.chat_bubble, color: Colors.blue, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text('Support & Complaints', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _showCreateTicketDialog,
                      icon: const Icon(Icons.add, color: Colors.white, size: 18),
                      label: const Text('Create New Ticket', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Get help with your parking business', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 24),

                _isLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.blue)))
                    : _tickets.isEmpty
                    ? Container(width: double.infinity, padding: const EdgeInsets.all(40), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)), child: Center(child: Text('No support tickets found.', style: TextStyle(color: Colors.grey.shade600))))
                    : _buildTicketsTable(),

                const SizedBox(height: 30),
              ],
            ),
          ),
          if (_isLoading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.blue, minHeight: 3)),
        ],
      ),
    );
  }

  Widget _buildTicketsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  _buildHeaderCell('TICKET #', 140),
                  _buildHeaderCell('SUBJECT', 200),
                  _buildHeaderCell('CATEGORY', 140),
                  _buildHeaderCell('PRIORITY', 100),
                  _buildHeaderCell('STATUS', 100),
                  _buildHeaderCell('CREATED', 100),
                  _buildHeaderCell('ACTIONS', 100),
                ],
              ),
            ),
            ..._tickets.map((ticket) => _buildTicketRow(ticket)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String title, double width) {
    return SizedBox(width: width, child: Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold)));
  }

  Widget _buildTicketRow(Map<String, dynamic> ticket) {
    final String subject = ticket['subject'] ?? 'No Subject';

    String category = ticket['category']?.toString() ?? 'Other';
    category = category.replaceAll('_', ' ');
    category = category.isNotEmpty ? category[0].toUpperCase() + category.substring(1) : category;

    String dateStr = ticket['created_at'] ?? '';
    if (dateStr.length > 10) {
      try {
        final parts = dateStr.split(' ')[0].split('-');
        final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        dateStr = "${parts[2]} ${months[int.parse(parts[1]) - 1]} ${parts[0]}";
      } catch (_) {}
    }

    final String priority = ticket['priority']?.toString().toUpperCase() ?? 'MEDIUM';
    MaterialColor pColor = Colors.orange;
    if (priority == 'LOW') pColor = Colors.blue;
    if (priority == 'HIGH' || priority == 'URGENT') pColor = Colors.red;

    final String status = ticket['status']?.toString().toUpperCase() ?? 'OPEN';
    MaterialColor sColor = Colors.green;
    if (status == 'CLOSED' || status == 'RESOLVED') sColor = Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(ticket['ticket_number'] ?? 'N/A', style: TextStyle(color: Colors.blue.shade700, fontSize: 13, fontWeight: FontWeight.bold))),
          SizedBox(width: 200, child: Text(subject, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          SizedBox(width: 140, child: Text(category, style: const TextStyle(color: Colors.black, fontSize: 13))),

          SizedBox(
            width: 100,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: pColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Text(priority.substring(0,1).toUpperCase() + priority.substring(1).toLowerCase(), style: TextStyle(color: pColor.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ),

          SizedBox(
            width: 100,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: sColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: sColor.withOpacity(0.5))),
                child: Text(status.substring(0,1).toUpperCase() + status.substring(1).toLowerCase(), style: TextStyle(color: sColor.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ),

          SizedBox(width: 100, child: Text(dateStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),

          SizedBox(
            width: 100,
            child: Row(
              children: [
                InkWell(
                  onTap: () => _showChatDialog(ticket),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.chat_bubble_outline, color: Colors.blue, size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _closeTicket(ticket),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: status == 'CLOSED' ? Colors.grey.shade100 : Colors.orange.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Icon(status == 'CLOSED' ? Icons.lock : Icons.lock_outline, color: status == 'CLOSED' ? Colors.grey.shade600 : Colors.orange, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}