import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

bool validAttempt(Map<String, dynamic> data) {
  if (data['schemaVersion'] is! int || data['schemaVersion'] != 1) {
    return false;
  }

  if (data['variant'] != 'B') return false;

  if (data['categoryId'] is! int || data['categoryId'] != 17) {
    return false;
  }

  if (data['questionCount'] is! int || data['questionCount'] != 5) {
    return false;
  }

  if (data['correctCount'] is! int) return false;

  if (data['correctCount'] < 0 || data['correctCount'] > 5) {
    return false;
  }

  return true;
}

Future<void> saveAttempt(String uid, String roundId, int score) async {
  if (FirebaseAuth.instance.currentUser?.uid != uid) {
    throw FirebaseAuthException(code: 'unauthenticated');
  }

  final ref = FirebaseFirestore.instance.doc(
    'users/$uid/attempts/$roundId',
  );

  final data = {
    'schemaVersion': 1,
    'variant': 'B',
    'categoryId': 17,
    'questionCount': 5,
    'correctCount': score,
    'submittedAt': FieldValue.serverTimestamp(),
  };

  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final document = await transaction.get(ref);

    if (!document.exists) {
      transaction.set(ref, data);
    } else {
      final saved = document.data();

      if (saved == null ||
          !validAttempt(saved) ||
          saved['correctCount'] != score) {
        throw StateError('Collision: this round has a different result.');
      }
    }
  });
}

Future<Map<String, dynamic>?> readAttempt(
  String uid,
  String roundId, {
  int? expectedScore,
}) async {
  if (FirebaseAuth.instance.currentUser?.uid != uid) {
    throw FirebaseAuthException(code: 'unauthenticated');
  }

  final document = await FirebaseFirestore.instance
      .doc('users/$uid/attempts/$roundId')
      .get(const GetOptions(source: Source.server));

  if (document.metadata.isFromCache || document.metadata.hasPendingWrites) {
    throw StateError('Server verification is unavailable.');
  }

  if (!document.exists) return null;

  final data = document.data();

  if (data == null ||
      data.length != 6 ||
      !validAttempt(data) ||
      data['submittedAt'] is! Timestamp) {
    throw StateError('The server record has invalid fields.');
  }

  if (expectedScore != null && data['correctCount'] != expectedScore) {
    throw StateError('Collision: the server score does not match.');
  }

  return data;
}