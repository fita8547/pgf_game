/// File helpers for build/diagnostic tools; the reader itself lives in lib.
library;

import 'dart:io';

import 'package:rps_shared/src/world/glb.dart';

export 'package:rps_shared/src/world/glb.dart';

Glb readGlb(String path) => Glb.parse(File(path).readAsBytesSync());
