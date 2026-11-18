import 'dart:convert';

import 'package:http/http.dart' as http;


DateTime? lastRequest;

Future<List<Map<String, String>>> loadQuestions() async {
  final now = DateTime.now();

  if (lastRequest != null && now.difference(lastRequest!).inSeconds < 5) {
    throw Exception('Wait before trying again.');
  }

  lastRequest = now;

  final response = await http
      .get(
        Uri.parse(
          'https://opentdb.com/api.php?amount=5&category=17&difficulty=medium&type=boolean&encode=url3986',
        ),
      )
      .timeout(const Duration(seconds: 10));

  if (response.statusCode != 200) {
    throw Exception('Could not load question try again.');
  }

  return parseQuestions(response.body);
}

List<Map<String, String>> parseQuestions(String body) {
  try {
    final data = jsonDecode(body);
    final results = data['results'];

    if (data['response_code'] != 0 || results is! List || results.length != 5) {
      throw const FormatException();
    }

    final questions = <Map<String, String>>[];

    for (final item in results) {
      final incorrect = item['incorrect_answers'];

      if (item['difficulty'] != 'medium' ||
          item['type'] != 'boolean' ||
          incorrect is! List ||
          incorrect.length != 1) {
        throw const FormatException();
      }

      final question = Uri.decodeComponent(item['question']);
      final category = Uri.decodeComponent(item['category']);
      final correct = Uri.decodeComponent(item['correct_answer']);
      final wrong = Uri.decodeComponent(incorrect[0]);

      final validAnswers =
          (correct == 'True' && wrong == 'False') ||
          (correct == 'False' && wrong == 'True');

      if (question.trim().isEmpty ||
          category != 'Science & Nature' ||
          !validAnswers) {
        throw const FormatException();
      }

      questions.add({
        'encodedQuestion': item['question'],
        'question': question,
        'correctAnswer': correct,
        'incorrectAnswer': wrong,
      });
    }

    return questions;
  } catch (_) {
    throw const FormatException('Invalid quiz data try again.');
  }
}
