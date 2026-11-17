import 'dart:async';

import 'package:flick/services/scan_operation_gate.dart';
import 'package:test/test.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'breaking at terminal progress returns before detached cleanup',
    () async {
      final gate = ScanOperationGate();
      final cleanupStarted = Completer<void>();
      final finishCleanup = Completer<void>();
      var clientFinished = false;
      final client = () async {
        await for (final event in gate.runStream<int>(
          () async* {
            yield 1;
            yield 2;
          },
          afterOperation: () async {
            cleanupStarted.complete();
            await finishCleanup.future;
          },
        )) {
          if (event == 1) break;
        }
        clientFinished = true;
      }();
      await cleanupStarted.future;
      var nextStarted = false;
      final next = gate.run(() async {
        nextStarted = true;
      });

      await _settle();
      expect(clientFinished, isTrue);
      expect(nextStarted, isFalse);
      expect(gate.isRunning, isTrue);
      finishCleanup.complete();
      await Future.wait([client, next]);
      expect(nextStarted, isTrue);
      expect(gate.isRunning, isFalse);
    },
  );

  test(
    'detached cleanup errors release the next scan without a stream error',
    () async {
      final gate = ScanOperationGate();
      final first = gate
          .runStream<int>(
            () async* {
              yield 1;
            },
            afterOperation: () async {
              throw StateError('finalization failed');
            },
          )
          .toList();
      var nextStarted = false;
      final next = gate.run(() async {
        nextStarted = true;
      });

      expect(await first, [1]);
      await next;
      expect(nextStarted, isTrue);
      expect(gate.isRunning, isFalse);
    },
  );

  test('creating an unlistened stream never reserves the gate', () async {
    final gate = ScanOperationGate();
    var unusedStarted = false;
    gate.runStream<int>(() async* {
      unusedStarted = true;
      yield 1;
    });

    await gate.run(() async {});
    expect(unusedStarted, isFalse);
    expect(gate.isRunning, isFalse);
  });

  test(
    'independent callers cannot overlap stream and future operations',
    () async {
      final gate = ScanOperationGate();
      final finishFirst = Completer<void>();
      final firstStarted = Completer<void>();
      final order = <String>[];
      final first = gate.runStream<int>(() async* {
        order.add('first start');
        firstStarted.complete();
        yield 1;
        await finishFirst.future;
        order.add('first end');
      }).drain<void>();
      await firstStarted.future;
      final second = gate.run(() async {
        order.add('second');
      });
      final third = gate.runStream<int>(() async* {
        order.add('third');
        yield 3;
      }).toList();

      await _settle();
      expect(order, ['first start']);
      expect(gate.isRunning, isTrue);
      finishFirst.complete();
      await Future.wait([first, second, third]);
      expect(order, ['first start', 'first end', 'second', 'third']);
      expect(gate.isRunning, isFalse);
    },
  );

  test('source errors release the next caller', () async {
    final gate = ScanOperationGate();
    final first = gate.runStream<int>(() async* {
      throw StateError('scan failed');
    }).drain<void>();
    final firstError = expectLater(first, throwsStateError);
    var nextStarted = false;
    final next = gate.run(() async {
      nextStarted = true;
    });

    await firstError;
    await next;
    expect(nextStarted, isTrue);
    expect(gate.isRunning, isFalse);
  });

  test(
    'cancelling queued work skips it and does not block later work',
    () async {
      final gate = ScanOperationGate();
      final finishFirst = Completer<void>();
      final firstStarted = Completer<void>();
      final first = gate.run(() async {
        firstStarted.complete();
        await finishFirst.future;
      });
      await firstStarted.future;
      var queuedStarted = false;
      final queued = gate
          .runStream<int>(() async* {
            queuedStarted = true;
            yield 2;
          })
          .listen((_) {});
      await queued.cancel();
      var lastStarted = false;
      final last = gate.run(() async {
        lastStarted = true;
      });

      finishFirst.complete();
      await Future.wait([first, last]);
      expect(queuedStarted, isFalse);
      expect(lastStarted, isTrue);
      expect(gate.isRunning, isFalse);
    },
  );

  test(
    'active cancellation waits for source cleanup before the next scan',
    () async {
      final gate = ScanOperationGate();
      final cleanupStarted = Completer<void>();
      final finishCleanup = Completer<void>();
      final firstEvent = Completer<void>();
      final source = StreamController<int>(
        onListen: () {},
        onCancel: () async {
          cleanupStarted.complete();
          await finishCleanup.future;
        },
      );
      final subscription = gate.runStream(() => source.stream).listen((_) {
        firstEvent.complete();
      });
      source.add(1);
      await firstEvent.future;
      final cancellation = subscription.cancel();
      await cleanupStarted.future;
      var nextStarted = false;
      final next = gate.run(() async {
        nextStarted = true;
      });

      await _settle();
      expect(nextStarted, isFalse);
      expect(gate.isRunning, isTrue);
      finishCleanup.complete();
      await cancellation;
      await next;
      expect(nextStarted, isTrue);
      expect(gate.isRunning, isFalse);
      await source.close();
    },
  );
}
