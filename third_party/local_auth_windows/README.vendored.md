# local_auth_windows (angepasst)

Kopie von pub.dev 2.0.2, zwei Änderungen für Visual Studio 2026 (MSVC 14.5x):

- `local_auth_plugin.cpp`: `co_return` statt `return` in der Coroutine (Fehler C3773).
- `CMakeLists.txt`: `/await` entfernt (Fehler STL1011), das Plugin baut als C++20.

Entfällt, sobald das Plugin das selbst behebt: Override in `pubspec.yaml` und diesen Ordner löschen.
