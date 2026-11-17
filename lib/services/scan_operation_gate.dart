import 'dart:async';

/// Shared by scans and changes to their watched roots.
final libraryScanOperations = ScanOperationGate();

/// Serializes scan streams across callers without reserving work until listen.
class ScanOperationGate {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// Includes queued operations, so automatic callers can avoid adding work.
  bool get isRunning => _pending > 0;

  /// [afterOperation] keeps subsequent work queued after the client stream
  /// closes, without making a client wait for detached scan finalization.
  /// Its errors are ignored because the client has already finished.
  Stream<T> runStream<T>(
    Stream<T> Function() operation, {
    Future<void> Function()? afterOperation,
  }) {
    var cancelled = false;
    var operationStarted = false;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        final previous = _tail;
        final released = Completer<void>();
        _tail = released.future;
        _pending++;
        unawaited(() async {
          try {
            await previous;
            if (!cancelled) {
              operationStarted = true;
              // addStream forwards pause/cancel to the source and waits for
              // its asynchronous cleanup before releasing the next operation.
              await controller.addStream(operation(), cancelOnError: false);
            }
          } catch (error, stack) {
            if (!cancelled && !controller.isClosed) {
              controller.addError(error, stack);
            }
          } finally {
            if (operationStarted && afterOperation != null) {
              try {
                // Deliver done (or finish cancellation) before waiting for
                // detached work, while retaining this operation's queue slot.
                await controller.close();
                await afterOperation();
              } catch (_) {
                // Finalization must not poison the queue after the client
                // stream has closed. Tasks can report their own errors.
              }
            }
            _pending--;
            released.complete();
            if (!controller.isClosed) unawaited(controller.close());
          }
        }());
      },
      onCancel: () {
        cancelled = true;
      },
    );
    return controller.stream;
  }

  Future<void> run(Future<void> Function() operation) =>
      runStream<void>(() async* {
        await operation();
      }).drain<void>();
}
