import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';

/// Signature for a function that builds a widget from a value.
typedef ValueBuilderFn<T> = Widget Function(BuildContext context, T value);

/// Signature for a function that builds a widget from an exception.
typedef ErrorBuilderFn = Widget Function(BuildContext context, Object error, StackTrace stackTrace);

/// Signature for a function that reports a flutter error, e.g. [FlutterError.reportError].
typedef ErrorReporterFn = void Function(FlutterErrorDetails details);

/// A Widget that builds depending on the state of a [Future] or [Stream].
///
/// AsyncBuilder must be given either a [future] or [stream], not both.
///
/// This is similar to [FutureBuilder] and [StreamBuilder] but accepts separate
/// callbacks for each state. Just like the built in builders, the [future] or
/// [stream] must not be started at build time.
///
/// If no data is available this calls [waiting], or [builder] with a null value
/// if it's not provided.
///
/// If [initial] is provided, it is used in place of the value before one
/// is available.
///
/// If the asynchronous operation completes with an error this calls [error],
/// otherwise the error is printed to the console. The error is suppressed if
/// [silent] is true.
///
/// When [stream] closes and [closed] is provided, [closed] is called with the
/// last value emitted.
///
/// If [pause] is true, the [StreamSubscription] used to listen to [stream] is
/// paused.
class AsyncBuilder<T> extends StatefulWidget {
  final WidgetBuilder waiting;
  final ValueBuilderFn<T> builder;
  final ErrorBuilderFn error;
  final ValueBuilderFn<T> closed;
  final Future<T> future;
  final Stream<T> stream;
  final T initial;
  final bool silent;
  final bool pause;
  final ErrorReporterFn reportError;

  AsyncBuilder({
    this.waiting,
    @required this.builder,
    this.error,
    this.closed,
    this.future,
    this.stream,
    this.initial,
    this.pause = false,
    bool silent,
    ErrorReporterFn reportError,
  }) : silent = silent ?? error != null,
       reportError = reportError ?? FlutterError.reportError,
       assert(builder != null),
       assert((future != null) != (stream != null), 'AsyncBuilder should be given either a stream or future'),
       assert(future == null || closed == null, 'AsyncBuilder should not be given both a future and closed builder'),
       assert(pause != null);

  @override
  State<StatefulWidget> createState() => _AsyncBuilderState();
}

class _AsyncBuilderState extends State<AsyncBuilder> {
  Object _lastValue;
  Object _lastError;
  StackTrace _lastStackTrace;
  bool _hasFired = false;
  bool _isClosed = false;
  StreamSubscription _subscription;

  void _cancel() {
    _lastValue = null;
    _lastError = null;
    _lastStackTrace = null;
    _hasFired = false;
    _isClosed = false;
    _subscription?.cancel();
    _subscription = null;
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _lastError = error;
    _lastStackTrace = stackTrace;
    if (widget.error != null) {
      setState(() {});
    }
    if (!widget.silent) {
      widget.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace ?? StackTrace.empty,
        context: ErrorDescription('While updating AsyncBuilder'),
      ));
    }
  }

  void _initFuture() {
    _cancel();
    var future = widget.future;
    future.then((value) {
      if (future != widget.future) return; // Skip if future changed
      setState(() {
        _lastValue = value;
        _hasFired = true;
      });
    }, onError: _handleError);
  }

  void _updateStream() {
    if (_subscription != null) {
      if (widget.pause && !_subscription.isPaused) {
        _subscription.pause();
      } else if (!widget.pause && _subscription.isPaused) {
        _subscription.resume();
      }
    }
  }

  void _initStream() {
    _cancel();
    var stream = widget.stream;
    if (stream != null) {
      var skipFirst = false;
      if (stream is ValueStream && stream.hasValue) {
        skipFirst = true;
        _hasFired = true;
        _lastValue = stream.value;
      }
      _subscription = stream.listen(
        (event) {
          if (skipFirst) {
            skipFirst = false;
            return;
          }
          setState(() {
            _hasFired = true;
            _lastValue = event;
          });
        },
        onDone: () {
          _isClosed = true;
          if (widget.closed != null) {
            setState(() {});
          }
        },
        onError: _handleError,
      );
    }
  }

  @override
  void initState() {
    super.initState();

    if (widget.future != null) {
      _initFuture();
    } else {
      _initStream();
    }

    _updateStream();
  }

  @override
  void didUpdateWidget(AsyncBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.future != null && widget.future != oldWidget.future) {
      _initFuture();
    } else if (widget.stream != oldWidget.stream) {
      _initStream();
    }

    _updateStream();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastError != null && widget.error != null) {
      return widget.error(context, _lastError, _lastStackTrace);
    }

    if (_isClosed && widget.closed != null) {
      return widget.closed(context, _hasFired ? _lastValue : widget.initial);
    }

    if (!_hasFired && widget.waiting != null) {
      return widget.waiting(context);
    }

    return widget.builder(context, _hasFired ? _lastValue : widget.initial);
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}
