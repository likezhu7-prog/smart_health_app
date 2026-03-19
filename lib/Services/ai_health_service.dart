import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AIHealthService {
  // ── Replace this with your real OpenAI API key when ready ──
  static String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  static const bool _useMock = false;

  /// Analyze health vitals and return AI-generated advice.
  static Future<String> analyzeVitals({
    required int heartRate,
    required int steps,
    required int calories,
    required int sleep,
    String ecgResult = 'Normal',
    String bloodPressure = '120/80',
  }) async {
    if (_useMock) {
      return _mockAnalysis(
        heartRate: heartRate,
        steps: steps,
        calories: calories,
        sleep: sleep,
        ecgResult: ecgResult,
        bloodPressure: bloodPressure,
      );
    }

    // ── Real OpenAI call (used when _useMock = false) ──
    try {
      final prompt = _buildPrompt(
        heartRate: heartRate,
        steps: steps,
        calories: calories,
        sleep: sleep,
        ecgResult: ecgResult,
        bloodPressure: bloodPressure,
      );

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a health assistant AI. Analyze patient vitals and provide concise, helpful health insights in 3-4 sentences. Be encouraging but flag any concerns.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 200,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      } else {
        return _mockAnalysis(
          heartRate: heartRate,
          steps: steps,
          calories: calories,
          sleep: sleep,
          ecgResult: ecgResult,
          bloodPressure: bloodPressure,
        );
      }
    } catch (e) {
      return _mockAnalysis(
        heartRate: heartRate,
        steps: steps,
        calories: calories,
        sleep: sleep,
        ecgResult: ecgResult,
        bloodPressure: bloodPressure,
      );
    }
  }

  static String _buildPrompt({
    required int heartRate,
    required int steps,
    required int calories,
    required int sleep,
    required String ecgResult,
    required String bloodPressure,
  }) {
    return '''
Patient vitals summary:
- Heart Rate: $heartRate BPM
- Steps today: $steps
- Calories burned: $calories kcal
- Sleep: $sleep hours
- ECG Result: $ecgResult
- Blood Pressure: $bloodPressure

Please analyze these vitals and provide personalized health insights and recommendations.
''';
  }

  /// Mock analysis — generates realistic advice based on actual values
  static String _mockAnalysis({
    required int heartRate,
    required int steps,
    required int calories,
    required int sleep,
    required String ecgResult,
    required String bloodPressure,
  }) {
    final List<String> insights = [];

    // Heart rate analysis
    if (heartRate == 0) {
      insights.add('⚠️ No heart rate data detected. Please ensure your wearable device is properly synced.');
    } else if (heartRate < 60) {
      insights.add('💙 Your resting heart rate of $heartRate BPM is below normal range. This may indicate bradycardia — consider consulting your doctor if you feel dizzy or fatigued.');
    } else if (heartRate <= 100) {
      insights.add('✅ Your heart rate of $heartRate BPM is within the healthy range of 60–100 BPM. Keep up the great work!');
    } else {
      insights.add('⚠️ Your heart rate of $heartRate BPM is elevated. Consider resting and staying hydrated. If this persists, consult a healthcare professional.');
    }

    // Steps analysis
    if (steps == 0) {
      insights.add('🚶 No step data recorded today. Try to aim for at least 7,000–10,000 steps daily for cardiovascular health.');
    } else if (steps < 5000) {
      insights.add('🚶 You\'ve taken $steps steps today. You\'re about halfway to the recommended 10,000 steps — a short walk could help you reach your goal!');
    } else if (steps < 10000) {
      insights.add('👟 Good progress with $steps steps today! You\'re well on your way to the recommended 10,000 daily steps.');
    } else {
      insights.add('🏃 Excellent! You\'ve exceeded 10,000 steps today with $steps steps. Your physical activity level is outstanding!');
    }

    // Sleep analysis
    if (sleep == 0) {
      insights.add('😴 No sleep data recorded. Quality sleep of 7–9 hours is essential for recovery and overall health.');
    } else if (sleep < 6) {
      insights.add('😴 You slept only $sleep hours last night. Adults need 7–9 hours for optimal health — try to improve your sleep schedule.');
    } else if (sleep <= 9) {
      insights.add('😴 Great — you got $sleep hours of sleep, which is within the recommended 7–9 hour range for adults.');
    } else {
      insights.add('😴 You slept $sleep hours. While rest is important, consistently sleeping over 9 hours may indicate fatigue or other health issues worth monitoring.');
    }

    // ECG note
    if (ecgResult.toLowerCase() == 'abnormal') {
      insights.add('🔴 Your ECG result is abnormal. Please consult your cardiologist as soon as possible.');
    } else if (ecgResult.toLowerCase() == 'borderline') {
      insights.add('🟡 Your ECG result is borderline. Monitor your symptoms and follow up with your doctor.');
    }

    return insights.join('\n\n');
  }
}
