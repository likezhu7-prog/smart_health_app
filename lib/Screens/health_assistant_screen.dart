import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../Services/e_hospital_service.dart';
import '../config/api_config.dart';
import '../ui/app_theme.dart';

class HealthAssistantScreen extends StatefulWidget {
  const HealthAssistantScreen({Key? key}) : super(key: key);

  @override
  State<HealthAssistantScreen> createState() => _HealthAssistantScreenState();
}

class _HealthAssistantScreenState extends State<HealthAssistantScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;

  static const String _baseUrl = "https://aetab8pjmb.us-east-1.awsapprunner.com/table";

  Future<String> _buildSystemPrompt(int patientId) async {
    final allWearable = await EHospitalService.fetchVitals();
    final wearable = allWearable
        .where((e) => e["patient_id"].toString() == patientId.toString())
        .toList();
    wearable.sort((a, b) => (b["timestamp"] ?? "").compareTo(a["timestamp"] ?? ""));
    final latestWearable = wearable.take(5).toList();

    Future<List<dynamic>> fetchTable(String table) async {
      try {
        final res = await http.get(Uri.parse("$_baseUrl/$table?patient_id=$patientId"));
        if (res.statusCode != 200) return [];
        final body = jsonDecode(res.body);
        final raw = body["data"] as List<dynamic>? ?? [];
        return raw.where((e) {
          final id = e["patient_id"];
          if (id == null) return true;
          return id is int ? id == patientId : id.toString() == patientId.toString();
        }).toList();
      } catch (_) {
        return [];
      }
    }

    final results = await Future.wait([
      fetchTable("ecg"),
      fetchTable("diabetes_analysis"),
      fetchTable("heart_disease_analysis"),
    ]);

    final ecgList = results[0];
    final diabetes = results[1];
    final heartDisease = results[2];

    Map<String, dynamic>? latestEcg;
    if (ecgList.isNotEmpty) {
      ecgList.sort((a, b) => (b["recorded_on"] ?? "").compareTo(a["recorded_on"] ?? ""));
      latestEcg = Map<String, dynamic>.from(ecgList.first);
    }

    Map<String, dynamic>? latestDiabetes;
    if (diabetes.isNotEmpty) {
      latestDiabetes = Map<String, dynamic>.from(diabetes.last);
    }

    Map<String, dynamic>? latestHeart;
    if (heartDisease.isNotEmpty) {
      heartDisease.sort((a, b) => (b["analyzed_on"] ?? "").compareTo(a["analyzed_on"] ?? ""));
      latestHeart = Map<String, dynamic>.from(heartDisease.first);
    }

    final summary = {
      "patient_id": patientId,
      "latest_wearable": latestWearable,
      "latest_ecg": latestEcg,
      "latest_diabetes_analysis": latestDiabetes,
      "latest_heart_disease_analysis": latestHeart,
    };

    return """You are a helpful AI health assistant integrated into a smart health monitoring app.
You have access to the following patient health data:

${jsonEncode(summary)}

Use this data to provide personalized, accurate health insights. Always:
- Refer to the patient's actual data when answering
- Explain medical terms in simple language
- Recommend consulting a doctor for diagnosis or treatment
- Be concise and friendly""";
  }

  Future<void> _sendMessage() async {
    final question = _inputController.text.trim();
    if (question.isEmpty || _isLoading) return;

    _inputController.clear();
    setState(() {
      _messages.add(_ChatMessage(role: "user", content: question));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getInt("patient_id") ?? 20;
      final systemPrompt = await _buildSystemPrompt(patientId);

      final model = GenerativeModel(
        model: 'gemini-2.0-flash-lite',
        apiKey: ApiConfig.geminiApiKey,
        systemInstruction: Content.system(systemPrompt),
      );

      final response = await model.generateContent([Content.text(question)]);
      final reply = response.text ?? "No response received.";

      setState(() {
        _messages.add(_ChatMessage(role: "assistant", content: reply.trim()));
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(role: "assistant", content: "Error: ${e.toString()}"));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Health Assistant"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: "Clear chat",
            onPressed: () => setState(() => _messages.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Gradient banner ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: Color(0x336A1B9A), blurRadius: 8, offset: Offset(0, 4)),
              ],
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.smart_toy, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("AI Health Assistant",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text("Powered by Gemini AI · Ask about your health data",
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ]),
          ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: AppColors.primarySoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.health_and_safety, size: 40, color: AppColors.primary),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Ask me anything about your health",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '"Why is my heart rate increasing?"',
                          style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '"What does my ECG result mean?"',
                          style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoading && index == _messages.length) {
                        return _buildTypingIndicator();
                      }
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),

          // Input area
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: InputDecoration(
                        hintText: "Ask about your health...",
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _isLoading ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    final isUser = msg.role == "user";
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Text(
          msg.content,
          style: TextStyle(
            fontSize: 14,
            color: isUser ? Colors.white : const Color(0xFF222222),
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Text("Thinking...", style: TextStyle(fontSize: 13, color: Colors.grey[500], fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  final String content;
  const _ChatMessage({required this.role, required this.content});
}
