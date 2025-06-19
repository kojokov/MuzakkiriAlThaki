import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(MuzakkiriAlThakiApp());
}

class MuzakkiriAlThakiApp extends StatefulWidget {
  @override
  _MuzakkiriAlThakiAppState createState() => _MuzakkiriAlThakiAppState();
}

class _MuzakkiriAlThakiAppState extends State<MuzakkiriAlThakiApp> {
  final TextEditingController _taskController = TextEditingController();
  final List<Task> _tasks = [];
  final OpenAIService _openAIService = OpenAIService();

  @override
  void initState() {
    super.initState();
    // إضافة المهام الأساسية تلقائياً
    _addTask('ذكرني بشرب الماء كل ساعتين');
    _addTask('استيقظ ليوم الصلاة الساعة 4 صباحاً');
    _addTask('اذهب إلى العمل الساعة 6 صباحاً');
  }

  Future<void> _addTask(String input) async {
    if (input.trim().isEmpty) return;

    setState(() {
      _tasks.add(Task(rawText: input, parsed: 'جاري المعالجة...'));
    });

    final Task task = await _openAIService.parseTask(input);

    setState(() {
      _tasks[_tasks.length - 1] = task;
    });

    await NotificationService().scheduleTaskNotification(task);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مذكّري الذكي',
      home: Scaffold(
        appBar: AppBar(
          title: Text('مذكّري الذكي'),
          backgroundColor: Colors.blueGrey,
        ),
        body: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _taskController,
                decoration: InputDecoration(
                  labelText: 'أدخل مهمة جديدة',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) async {
                  await _addTask(value);
                  _taskController.clear();
                },
              ),
              SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    return ListTile(
                      title: Text(task.rawText),
                      subtitle: Text(task.parsed),
                      leading: Icon(Icons.notifications),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Task {
  final String rawText;
  final String parsed;
  final DateTime? scheduledTime;
  final bool isRecurring;
  final Duration? recurringInterval;

  Task({
    required this.rawText,
    required this.parsed,
    this.scheduledTime,
    this.isRecurring = false,
    this.recurringInterval,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      rawText: json['rawText'],
      parsed: json['parsed'],
      scheduledTime: json['scheduledTime'] != null ? DateTime.parse(json['scheduledTime']) : null,
      isRecurring: json['isRecurring'] ?? false,
      recurringInterval: json['recurringInterval'] != null ? Duration(seconds: json['recurringInterval']) : null,
    );
  }
}

class OpenAIService {
  final String apiKey = 'YOUR_OPENAI_API_KEY_HERE'; // أدخل مفتاح API الخاص بك هنا

  Future<Task> parseTask(String input) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    final body = jsonEncode({
      'model': 'gpt-4o-mini',
      'messages': [
        {
          'role': 'system',
          'content':
              'أنت مساعد ذكي يساعد في تحليل نصوص المهام وتحويلها إلى وقت جدولة وتنبيهات.'
        },
        {
          'role': 'user',
          'content': 'حلل المهمة التالية مع استخراج الوقت، التكرار، وأي تفاصيل مهمة: "$input"'
        }
      ],
      'temperature': 0.2,
      'max_tokens': 150,
    });

    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'] as String;

      // تفترض أن النموذج يرجع JSON منسق مثل:
      /*
      {
        "parsed": "تذكير بشرب الماء كل ساعتين",
        "scheduledTime": "2025-06-19T10:00:00",
        "isRecurring": true,
        "recurringInterval": 7200
      }
      */

      try {
        final parsedJson = jsonDecode(content);
        return Task.fromJson(parsedJson);
      } catch (e) {
        return Task(rawText: input, parsed: content);
      }
    } else {
      return Task(rawText: input, parsed: 'فشل في تحليل المهمة.');
    }
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    final androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = IOSInitializationSettings();
    final initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

    await flutterLocalNotificationsPlugin.initialize(initSettings);
  }

  Future<void> scheduleTaskNotification(Task task) async {
    if (task.scheduledTime == null) return;

    final androidDetails = AndroidNotificationDetails(
      'task_channel_id',
      'تذكير المهام',
      channelDescription: 'قناة لتذكير المهام اليومية',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    final iosDetails = IOSNotificationDetails();

    final notificationDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      task.rawText.hashCode,
      'تذكير: ${task.rawText}',
      'الوقت المحدد للتنبيه',
      tz.TZDateTime.from(task.scheduledTime!, tz.local),
      notificationDetails,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: task.isRecurring
          ? DateTimeComponents.time
          : null,
    );
  }
}
