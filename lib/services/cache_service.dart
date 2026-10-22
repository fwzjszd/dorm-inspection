// 缓存统计与清理：原生端操作应用临时目录，
// Web 端没有临时目录概念，使用空实现（设置页同时隐藏入口）。
export 'cache_service_io.dart'
    if (dart.library.js_interop) 'cache_service_web.dart';
