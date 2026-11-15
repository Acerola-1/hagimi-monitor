# Third-party notices

## macmon

The CLPC report identifiers and IOReport descriptor layout in
`HagimiMonitorDirectOnly/CLPCPowerChannels.swift` are adapted from
[macmon](https://github.com/vladkens/macmon), using `src/clpc.rs` at commit
`87c6686b048c97f665d31bc58277845c4f7822c4` in the local implementation.
The M3 contribution in [PR #141](https://github.com/Acerola-1/hagimi-monitor/pull/141)
references `src/clpc.rs` and `src/sources.rs` at commit
`6ebbd71c2930f1b9a25a68eaf857dfd134ade606`; its M3 mapping and descriptor
regression coverage are retained alongside the existing implementation.
The license below is also bundled in Direct builds as `macmon-LICENSE.txt`.

MIT License

Copyright (c) 2024 vladkens

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

## M3 validation contribution

The M3 hardware investigation, validation record and adapted descriptor/layout
regression cases are contributed by [xyy386](https://github.com/xyy386) in
[PR #141](https://github.com/Acerola-1/hagimi-monitor/pull/141), commit
`6405160fb2bf5f65b91c870c2836eb28f1cd24a6`.
See [the preserved validation record](docs/power-topology-m3-macos27.md) for
its original results and the differences in the integrated implementation.
