# qmweb-sign

The QQ Music `zzc` / `ag-1` protocol in `src/qq/sign.rs` is based on:
https://github.com/jixunmoe/qmweb-sign/tree/15305a3cc39f80eb1646ab2bae46468231765736

MIT License

Copyright (c) 2024 Jixun Wu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# MNN

Optional Android ARM64 and Windows x64 NAC builds link Alibaba MNN 3.6.2
from its [official release](https://github.com/alibaba/MNN/releases/tag/3.6.2).
The application bundle includes the [Apache 2.0 license](../native/nac/licenses/MNN-LICENSE.txt).
The NAC model is a separate local build input supplied by the builder.

# QMCv2

`src/qq/qmc.rs` adapts the key decoding and offset-based cipher from
[qm-api-rs](https://github.com/YAQMC/qm-api-rs/blob/bab630d44901f80cae47dd0f09314950d0028e23/src/qmc.rs)
(GPL-3.0-or-later), which credits
[QMCDecode](https://github.com/gongjiehong/QMCDecode/tree/aea76301a08678100ec677cb61a8458bc75662ec).

MIT License

Copyright (c) 2019 程序猿老龚 gjh.me

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
