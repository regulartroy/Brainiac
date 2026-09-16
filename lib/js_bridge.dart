class JsContext {
  final Map<String, dynamic> _values = <String, dynamic>{};

  dynamic operator [](String key) => _values[key];

  void operator []=(String key, dynamic value) {
    _values[key] = value;
  }
}

final JsContext context = JsContext();

dynamic allowInterop<T>(T Function(T) callback) => callback;
