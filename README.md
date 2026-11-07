# llama-ios-build

交叉编译 llama.cpp (`llama-server`) 为 iOS arm64 无签名可执行文件，用于越狱机本地大模型推理（OpenAI 兼容 endpoint）。

产物：`llama-server`（iOS arm64, platform=2, minos 15.0），可直接 `ldid -S` 后放到越狱机 `/var/jb/usr/bin/`。
