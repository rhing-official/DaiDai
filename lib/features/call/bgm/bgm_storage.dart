/// BGMの曲の端末内保存。`IndexedDB`はWebにしか無いため条件付きexportで切り替える。
library;

export 'bgm_storage_stub.dart'
    if (dart.library.js_interop) 'bgm_storage_web.dart';
