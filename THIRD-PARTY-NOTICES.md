# Third-party notices

`opencode-mobile` does not reimplement opencode. It runs the real
[anomalyco/opencode](https://github.com/anomalyco/opencode) CLI, cross-compiled to an
Android executable and redistributed inside this app. That upstream project is MIT
licensed, and this file records what we owe it.

## Independence

`opencode-mobile` is an independent project. It is not affiliated with, endorsed by, or
sponsored by the opencode authors or the opencode project, and nothing here should be
read as a statement on their behalf. The opencode name, its source, and its copyright are
theirs; this project only builds and redistributes them under their stated licence.

## What we change

One file, `packages/opencode/script/build.ts`, via `patches/opencode-android-target.patch`:
the Android targets are added to `allTargets`, the `abi` type is widened to accept them,
and two libc defines are mapped to existing values. MIT permits modification and
redistribution provided the copyright notice and permission notice travel with the work.
They do: verbatim below, and as `upstream-LICENSE` next to the binaries in the
`opencode-android-binaries` artifact.

The exact upstream sources this binary was built from are the pinned commit recorded in
`UPSTREAM.md` — a `dev` HEAD that has diverged from the `v1.18.34` tag, so anyone
reproducing this build must use the commit, not the tag.

## Upstream notice

From `LICENSE` at commit `1ddb0873aee50d209d1a8d7f91b89c5daf692d49`
(`git show 1ddb0873aee50d209d1a8d7f91b89c5daf692d49:LICENSE`), reproduced in full:

```
MIT License

Copyright (c) 2025 opencode

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
```

Bun is used to produce the executable and is itself MIT licensed; its notice ships with
Bun's own distributions and is not reproduced here because no Bun code is redistributed
in this artifact.