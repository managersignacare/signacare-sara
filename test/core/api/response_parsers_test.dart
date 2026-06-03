import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signacare_mobile/core/api/response_parsers.dart';

void main() {
  group('response_parsers', () {
    test('readMapListEnvelope reads top-level list', () {
      final result = readMapListEnvelope([
        {'id': 'a'},
      ]);
      expect(result, hasLength(1));
      expect(result.first['id'], 'a');
    });

    test('readMapListEnvelope reads data envelope', () {
      final result = readMapListEnvelope({
        'data': [
          {'id': 'b'},
        ],
      });
      expect(result, hasLength(1));
      expect(result.first['id'], 'b');
    });

    test('readMapListEnvelope reads preferred key', () {
      final result = readMapListEnvelope(
        {
          'episodes': [
            {'id': 'c'},
          ],
        },
        preferredKeys: const ['episodes'],
      );
      expect(result, hasLength(1));
      expect(result.first['id'], 'c');
    });

    test('readMapListEnvelope throws when list missing', () {
      expect(
        () => readMapListEnvelope({'foo': 'bar'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('readMapEnvelope reads top-level map', () {
      final result = readMapEnvelope({'id': 'p1', 'name': 'Noah'});
      expect(result['id'], 'p1');
      expect(result['name'], 'Noah');
    });

    test('readMapEnvelope reads preferred nested map', () {
      final result = readMapEnvelope(
        {
          'data': {'id': 'p2'},
        },
        preferredKeys: const ['data'],
      );
      expect(result['id'], 'p2');
    });

    test('readApiErrorMessage extracts backend message from DioException', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/episodes/patient/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/episodes/patient/x'),
          statusCode: 403,
          data: {'error': 'Read access denied for module \'episodes\''},
        ),
        type: DioExceptionType.badResponse,
      );

      final message = readApiErrorMessage(err, fallback: 'fallback');
      expect(message, contains('Read access denied'));
    });
  });
}
