import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'scienceAPI.dart';
import 'attempted.dart';

class QuizScreen extends StatefulWidget {
  final User user;

  const QuizScreen({super.key, required this.user});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Map<String, String>> questions = [];
  List<String?> answers = List<String?>.filled(5, null);

  int index = 0;
  int score = 0;
  bool loading = false;
  bool finished = false;
  String error = '';
  late String roundId;

  bool cloudBusy = false;
  bool saved = false;
  String cloudState = 'readyToSubmit';
  String cloudMessage = '';
  Map<String, dynamic>? serverResult;
  Timer? cloudTimer;

  @override
  void initState() {
    super.initState();
    startRound();
  }

  @override
  void dispose() {
    cloudTimer?.cancel();
    super.dispose();
  }

  bool sameRound(String uid, String id) {
    if (!mounted) return false;
    if (widget.user.uid != uid) return false;
    if (roundId != id) return false;
    if (FirebaseAuth.instance.currentUser?.uid != uid) return false;

    return true;
  }

  bool cloudLocked() {
    if (cloudBusy) return true;
    if (cloudState == 'readyToSubmit') return false;
    if (cloudState == 'cloudVerified') return false;
    if (cloudState == 'collision') return false;

    return true;
  }

  void startRound() {
    if (loading || cloudLocked()) return;

    cloudTimer?.cancel();
    saved = false;
    serverResult = null;
    cloudState = 'readyToSubmit';
    cloudMessage = '';

    roundId = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('attempts')
        .doc()
        .id;

    index = 0;
    score = 0;
    finished = false;
    questions = [];
    answers = List<String?>.filled(5, null);

    fetchQuestions();
  }

  Future<void> fetchQuestions() async {
    if (loading || cloudLocked()) return;

    final id = roundId;
    final uid = widget.user.uid;

    List<Map<String, String>> result = [];
    String message = '';

    setState(() {
      loading = true;
      error = '';
    });

    try {
      result = await loadQuestions();
    } catch (e) {
      if (e is TimeoutException) {
        message = 'Question request timed out try again.';
      } else if (e is FormatException) {
        message = e.message;
      } else {
        message = e.toString();
      }
    }

    if (!sameRound(uid, id)) return;

    setState(() {
      questions = result;
      error = message;
      loading = false;
    });

    if (result.isNotEmpty) {
      debugPrint('Encoded: ${result[0]['encodedQuestion']}');
      debugPrint('Decoded: ${result[0]['question']}');
    }
  }

  void chooseAnswer(String answer) {
    if (loading ||
        finished ||
        questions.isEmpty ||
        answers[index] != null) {
      return;
    }

    setState(() {
      answers[index] = answer;

      if (answer == questions[index]['correctAnswer']) {
        score++;
      }
    });
  }

  void nextQuestion() {
    if (loading || finished || answers[index] == null) return;

    setState(() {
      if (index == 4) {
        finished = true;
      } else {
        index++;
      }
    });
  }

  void startCloudTimer(String uid, String id) {
    cloudTimer?.cancel();

    cloudTimer = Timer(const Duration(seconds: 10), () {
      if (!sameRound(uid, id) || !cloudBusy) return;

      setState(() {
        if (saved) {
          cloudState = 'verificationUnavailable';
          cloudMessage =
              'Write acknowledged; verification unavailable. '
              'The original request is still running.';
        } else {
          cloudState = 'saveUnknown';
          cloudMessage =
              'Save acknowledgement unknown '
              'The original request is still running';
        }
      });
    });
  }

  Future<void> submitOrCheck() async {
    if (cloudBusy ||
        !finished ||
        cloudState == 'cloudVerified' ||
        cloudState == 'collision') {
      return;
    }

    final uid = widget.user.uid;
    final id = roundId;
    final roundScore = score;
    final doSave = cloudState == 'readyToSubmit';

    if (!sameRound(uid, id)) return;

    setState(() {
      cloudBusy = true;

      if (doSave) {
        cloudState = 'submitting';
        cloudMessage = 'Saving...';
      } else {
        cloudState = 'verifying';
        cloudMessage = 'Checking server...';
      }
    });

    startCloudTimer(uid, id);

    try {
      if (doSave) {
        await saveAttempt(uid, id, roundScore);
        if (!sameRound(uid, id)) return;

        setState(() {
          saved = true;
          cloudState = 'verifying';
          cloudMessage = 'Write acknowledged. Checking server';
        });

        startCloudTimer(uid, id);
      }

      final data = await readAttempt(
        uid,
        id,
        expectedScore: roundScore,
      );

      if (!sameRound(uid, id)) return;

      setState(() {
        if (data != null) {
          serverResult = data;
          cloudState = 'cloudVerified';
          cloudMessage = 'Cloud verified';
        } else if (saved) {
          cloudState = 'verificationUnavailable';
          cloudMessage =
              'Write acknowledged verification unavailable. '
              'Server record not found.';
        } else {
          cloudState = 'readyToSubmit';
          cloudMessage = 'No server record retry saving this round.';
        }
      });
    } catch (e) {
      if (!sameRound(uid, id)) return;

      String reason = e.toString();

      if (e is FirebaseException) {
        reason = e.code;
      }

      setState(() {
        if (e is StateError &&
            e.message.toString().startsWith('Collision:')) {
          cloudState = 'collision';
          cloudMessage = e.message.toString();
        } else {
          if (e is FirebaseException && e.code == 'permission-denied') {
            cloudState = 'permissionDenied';
          } else {
            if (saved) {
              cloudState = 'verificationUnavailable';
            } else {
              cloudState = 'saveUnknown';
            }
          }

          if (saved) {
            cloudMessage =
                'Write acknowledged verification unavailable: $reason';
          } else {
            cloudMessage =
                'Save not confirmed: $reason. Check the server before retrying.';
          }
        }
      });
    } finally {
      if (sameRound(uid, id)) {
        cloudTimer?.cancel();

        setState(() {
          cloudBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    String buttonText = 'Submit score';
    bool buttonDisabled = false;
    Color messageColor = Colors.orange;

    if (cloudState != 'readyToSubmit') {
      buttonText = 'Check server';
    }

    if (cloudBusy) {
      buttonText = 'Working...';
      buttonDisabled = true;
    }

    if (cloudState == 'cloudVerified') {
      buttonText = 'Cloud verified';
      buttonDisabled = true;
      messageColor = Colors.green;
    }

    if (cloudState == 'collision') {
      buttonDisabled = true;
    }

    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (error.isNotEmpty || questions.isEmpty) {
      String message = error;

      if (message.isEmpty) {
        message = 'No questions loaded. Try again.';
      }

      content = ListView(
        children: [
          Text(message),
          ElevatedButton(
            onPressed: fetchQuestions,
            child: const Text('Try again'),
          ),
        ],
      );
    } else if (finished) {
      content = ListView(
        children: [
          Text('Score: $score/5'),
          for (int i = 0; i < questions.length; i++)
            Text(
              '${i + 1}. ${questions[i]['question']}\n'
              'Your answer ${answers[i]}\n'
              'Correct answer ${questions[i]['correctAnswer']}\n',
            ),
          Text(
            cloudMessage,
            style: TextStyle(color: messageColor),
          ),
          if (serverResult != null)
            Text('Server record:\n$serverResult'),
          if (cloudBusy)
            const LinearProgressIndicator(),
          ElevatedButton(
            onPressed: buttonDisabled ? null : submitOrCheck,
            child: Text(buttonText),
          ),
          ElevatedButton(
            onPressed: cloudLocked() ? null : startRound,
            child: const Text('Replay'),
          ),
        ],
      );
    } else {
      final question = questions[index];
      final selected = answers[index];
      final correct = selected == question['correctAnswer'];

      content = ListView(
        children: [
          const Text('Science & Nature — Medium'),
          Text('Question ${index + 1} of 5'),
          LinearProgressIndicator(value: (index + 1) / 5),
          const SizedBox(height: 16),
          Text(question['question']!),
          ElevatedButton(
            onPressed: selected == null ? () => chooseAnswer('True') : null,
            child: const Text('True'),
          ),
          ElevatedButton(
            onPressed: selected == null ? () => chooseAnswer('False') : null,
            child: const Text('False'),
          ),
          if (selected != null)
            Text(
              correct
                  ? 'Correct'
                  : 'Incorrect. Correct answer: ${question['correctAnswer']}',
              style: TextStyle(
                color: correct ? Colors.green : Colors.red,
              ),
            ),
          Text('Score: $score/5'),
          ElevatedButton(
            onPressed: selected == null ? null : nextQuestion,
            child: const Text('Continue'),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Project: ${Firebase.app().options.projectId}'),
          Text('your mail: ${widget.user.email}'),
          SelectableText('UID: ${widget.user.uid}'),
          Text('Round: ${roundId.substring(roundId.length - 6)}'),
          const SizedBox(height: 16),
          Expanded(child: content),
          TextButton(
            onPressed: loading || cloudLocked()
                ? null
                : () => FirebaseAuth.instance.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}