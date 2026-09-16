import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ReviewItem {
  const ReviewItem({required this.id, required this.label, required this.type});

  final String id;
  final String label;
  final String type;

  factory ReviewItem.fromMap(Map<String, dynamic> map) {
    return ReviewItem(
      id: map['id']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      type: map['type']?.toString() ?? 'unknown',
    );
  }
}

class TaskExtractionResult {
  const TaskExtractionResult({
    required this.tasks,
    required this.needsContext,
    required this.reviewItems,
  });

  final List<String> tasks;
  final bool needsContext;
  final List<ReviewItem> reviewItems;

  factory TaskExtractionResult.fromResult(dynamic result) {
    if (result is List) {
      return TaskExtractionResult(
        tasks: result.map((task) => task.toString()).toList(),
        needsContext: false,
        reviewItems: const [],
      );
    }

    if (result is Map) {
      final map = <String, dynamic>{};
      for (final entry in result.entries) {
        map[entry.key.toString()] = entry.value;
      }

      final tasks = map['tasks'];
      final reviewItems = map['review_items'];

      return TaskExtractionResult(
        tasks: tasks is List
            ? tasks.map((task) => task.toString()).toList()
            : const [],
        needsContext: map['needs_context'] == true,
        reviewItems: reviewItems is List
            ? reviewItems
                  .whereType<Map>()
                  .map(
                    (item) => ReviewItem.fromMap(
                      Map<String, dynamic>.from(
                        item.map(
                          (key, value) => MapEntry(key.toString(), value),
                        ),
                      ),
                    ),
                  )
                  .toList()
            : const [],
      );
    }

    return const TaskExtractionResult(
      tasks: [],
      needsContext: false,
      reviewItems: [],
    );
  }
}

class BrainAgentService {
  BrainAgentService({
    Future<dynamic> Function(Map<String, dynamic> payload)? functionCaller,
  }) : _functionCaller = functionCaller ?? _defaultFunctionCaller;

  final Future<dynamic> Function(Map<String, dynamic> payload) _functionCaller;

  static Future<dynamic> _defaultFunctionCaller(
    Map<String, dynamic> payload,
  ) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('extractTasks');

      const useLocalFunctions = bool.fromEnvironment('USE_LOCAL_FUNCTIONS');
      if (kIsWeb && (kDebugMode || useLocalFunctions)) {
        final projectId = Firebase.app().options.projectId;
        final host = Uri.base.host;
        final response = await http.post(
          Uri.parse('http://$host:5001/$projectId/us-central1/extractTasks'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'data': payload}),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }

        final body = jsonDecode(response.body);
        if (body is Map && body.containsKey('result')) {
          return body['result'];
        }
        return body;
      }

      final result = await callable.call(payload);
      return result.data;
    } catch (e) {
      print('Function caller fallback failed: $e');
      final callable = FirebaseFunctions.instance.httpsCallable('extractTasks');
      final result = await callable.call(payload);
      return result.data;
    }
  }

  Future<TaskExtractionResult> extractTasksForReview(String rawNote) async {
    try {
      final result = await _functionCaller(<String, dynamic>{
        'text': rawNote,
        'review_mode': true,
      });
      return TaskExtractionResult.fromResult(result);
    } catch (e) {
      print('Failed to review tasks from note: $e');
      rethrow;
    }
  }

  /// Sends raw note text to the Second Brain agent and returns extracted tasks.
  Future<List<String>> extractTasksFromNote(
    String rawNote, {
    List<ReviewItem> selectedReviewItems = const [],
  }) async {
    try {
      final payload = <String, dynamic>{'text': rawNote, 'review_mode': false};

      if (selectedReviewItems.isNotEmpty) {
        payload['review_items'] = selectedReviewItems
            .map(
              (item) => <String, dynamic>{
                'id': item.id,
                'label': item.label,
                'type': item.type,
              },
            )
            .toList();
      }

      final result = await _functionCaller(payload);
      return TaskExtractionResult.fromResult(result).tasks;
    } catch (e) {
      print('Failed to extract tasks from note: $e');
      rethrow;
    }
  }
}
