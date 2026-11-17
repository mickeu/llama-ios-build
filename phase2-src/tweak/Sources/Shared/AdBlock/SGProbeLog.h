// 沙盒日志：Documents/probe.log，一行一条。纯 C 接口，不让字符串转换进 ObjC 派发——
// 这条路径会在注入早期的工作线程和网络回调上跑，碰 Swift 桥接对象会把运行时带崩。
#ifndef SG_PROBE_LOG_H
#define SG_PROBE_LOG_H

#include <stddef.h>

void SGProbeC(const char *fmt, ...);
void SGProbeWrite(const char *text, size_t length);

#endif
