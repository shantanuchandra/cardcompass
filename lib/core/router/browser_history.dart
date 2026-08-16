import 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart'
    as impl;

/// Updates the browser fragment when a shell tab changes.
void replaceBrowserHistory(String location) =>
    impl.replaceBrowserHistory(location);
