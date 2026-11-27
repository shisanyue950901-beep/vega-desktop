// Vega：让本进程的 Flutter 窗口在 Windows 上透出系统亚克力（毛玻璃）背景。
// Modified for Vega (AGPL-3.0). 新文件，不含上游代码。
//
// 用 SetWindowCompositionAttribute(ACCENT_ENABLE_ACRYLICBLURBEHIND)，
// Windows 10 1803（17134）起可用。失败时什么都不做，界面退回实色。

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../native/win32.dart';

final class _AccentPolicy extends Struct {
  @Int32()
  external int accentState;
  @Int32()
  external int accentFlags;
  @Uint32()
  external int gradientColor;
  @Int32()
  external int animationId;
}

final class _CompAttrData extends Struct {
  @Int32()
  external int attrib;
  external Pointer<Void> pvData;
  @IntPtr()
  external int cbData;
}

final class _Margins extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int right;
  @Int32()
  external int top;
  @Int32()
  external int bottom;
}

class VegaGlass {
  VegaGlass._();

  /// 成功开启后为 true，界面据此把背景和卡片改成半透明。
  static bool active = false;

  static const _kAccentAcrylic = 4;
  static const _kWcaAccentPolicy = 19;

  /// 找到本进程的 Flutter 主窗口。
  static int _ownWindow() {
    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final findWindowEx = user32.lookupFunction<
        IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
        int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
    final getPid = user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
    final curPid = kernel32
        .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId')();
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final pid = calloc<Uint32>();
    var hwnd = 0;
    try {
      for (var i = 0; i < 64; i++) {
        hwnd = findWindowEx(0, hwnd, cls, nullptr);
        if (hwnd == 0) break;
        getPid(hwnd, pid);
        if (pid.value == curPid) return hwnd;
      }
      return 0;
    } finally {
      calloc.free(cls);
      calloc.free(pid);
    }
  }

  /// 读 HKCU\\...\\Themes\\Personalize\\EnableTransparency，读不到按关闭处理。
  static bool _transparencyEnabled() {
    final advapi = DynamicLibrary.open('advapi32.dll');
    final regGetValue = advapi.lookupFunction<
        Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32,
            Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>),
        int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>,
            Pointer<Uint32>, Pointer<Uint32>)>('RegGetValueW');
    const hkcu = -0x7FFFFFFF; // (HKEY)(LONG)0x80000001，按符号扩展
    final key = r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        .toNativeUtf16();
    final name = 'EnableTransparency'.toNativeUtf16();
    final value = calloc<Uint32>();
    final size = calloc<Uint32>()..value = 4;
    try {
      // RRF_RT_REG_DWORD = 0x10
      final rc = regGetValue(hkcu, key, name, 0x10, nullptr, value, size);
      return rc == 0 && value.value != 0;
    } finally {
      calloc.free(key);
      calloc.free(name);
      calloc.free(value);
      calloc.free(size);
    }
  }

  /// 开启亚克力。[dark] 决定底色。返回是否成功。
  static bool apply({required bool dark}) {
    if (!Platform.isWindows) return false;
    try {
      if (getWindowsTargetBuildNumber_() < 17134) return false;
      // 用户关了「透明效果」时系统不会画模糊，窗口会变成全透明看不清，直接不开。
      if (!_transparencyEnabled()) return false;
      final hwnd = _ownWindow();
      if (hwnd == 0) return false;

      final dwm = DynamicLibrary.open('dwmapi.dll');
      final extend = dwm.lookupFunction<Int32 Function(IntPtr, Pointer<_Margins>),
          int Function(int, Pointer<_Margins>)>('DwmExtendFrameIntoClientArea');
      final margins = calloc<_Margins>();
      margins.ref
        ..left = -1
        ..right = -1
        ..top = -1
        ..bottom = -1;
      extend(hwnd, margins);
      calloc.free(margins);

      final user32 = DynamicLibrary.open('user32.dll');
      final setAttr = user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<_CompAttrData>),
          int Function(int, Pointer<_CompAttrData>)>('SetWindowCompositionAttribute');
      final accent = calloc<_AccentPolicy>();
      accent.ref
        ..accentState = _kAccentAcrylic
        ..accentFlags = 2
        // ABGR。浅色：#F7F5FF，40% 不透明；深色：#1C1B26，60% 不透明。
        ..gradientColor = dark ? 0x99261B1C : 0x66FFF5F7
        ..animationId = 0;
      final data = calloc<_CompAttrData>();
      data.ref
        ..attrib = _kWcaAccentPolicy
        ..pvData = accent.cast()
        ..cbData = sizeOf<_AccentPolicy>();
      final ok = setAttr(hwnd, data) != 0;
      calloc.free(data);
      calloc.free(accent);
      active = ok;
      return ok;
    } catch (_) {
      active = false;
      return false;
    }
  }
}
