import 'package:web/web.dart' as web;

void replaceBrowserHistory(String location) {
  web.window.history.replaceState(null, '', location);
}
