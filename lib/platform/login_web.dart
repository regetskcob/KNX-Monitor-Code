import 'package:web/web.dart' as web;

/// The box's session ran out (HTTP 401): the box's own login page asks for
/// the password and then brings the browser back to the current page. Only
/// the KNX box and Docker answer 401; the add-on behind Ingress never does.
void loginIfExpired(int status) {
  if (status != 401) return;
  final location = web.window.location;
  final here = '${location.pathname}${location.search}';
  final login = Uri.parse(web.document.baseURI).removeFragment().resolve('login');
  location.assign(login.replace(queryParameters: {'next': here}).toString());
}
