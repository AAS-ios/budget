{{flutter_js}}
{{flutter_build_config}}

// Без встроенного service worker Flutter: он устарел и сам себя
// отключает. Работу без интернета обеспечивает sw.js (см. index.html).
_flutter.loader.load({});
