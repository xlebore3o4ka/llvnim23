# llvnim

[![CI](https://github.com/xlebore3o4ka/llvnim23/actions/workflows/ci.yml/badge.svg)](https://github.com/xlebore3o4ka/llvnim23/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Nim](https://img.shields.io/badge/Nim-%E2%89%A52.2.10-orange.svg)](https://nim-lang.org/)
[![LLVM](https://img.shields.io/badge/LLVM-23.1.x-6b4fbb.svg)](https://llvm.org/)
[![Status](https://img.shields.io/badge/status-v1.0.0-brightgreen.svg)](https://github.com/xlebore3o4ka/llvnim23/releases/tag/v1.0.0)

Hand-written Nim bindings for the LLVM-C API, version 23.1.x. You call LLVM directly from Nim to build IR, run the verifier, optimize with the new PassBuilder, and execute code via LLJIT or MCJIT.

### Why use it

Nim has no maintained bindings for modern LLVM-C. This package gives you the parts you need to write a compiler backend, a small language frontend, or a JIT in Nim, without leaving the language.

### Requirements

- Nim >= 2.2.10.
- LLVM 23.1.x. `checkVersion` raises `ValueError` on a different major.minor.

The library is loaded at runtime from:

| OS      | Default library      |
|---------|----------------------|
| Windows | `LLVM-C.dll`         |
| macOS   | `libLLVM.dylib`      |
| Linux   | `libLLVM.so.23.1`    |

Override with `-d:LlvmLib=<name>`.

Install LLVM:

```sh
# Ubuntu / Debian
sudo apt install llvm-23-dev

# Fedora
sudo dnf install llvm23-devel

# Arch
sudo pacman -S llvm

# macOS (Homebrew)
brew install llvm@23
```

Windows: use the official LLVM 23.1.x build from llvm.org. It ships `LLVM-C.dll`.

## Static linking

Dynamic loading remains the default. To link LLVM's static archives instead, build with:

```sh
nim c -r -d:staticLlvm tests/tests.nim
```

Static mode uses `llvm-config --link-static --libs --system-libs` to pass LLVM and its platform dependencies to the linker. Ensure `llvm-config` is on `PATH` and belongs to the LLVM 23.1.x installation whose static archives you want to use.

Arch Linux's packaged LLVM may omit core static archives. Build LLVM yourself with `-DLLVM_BUILD_STATIC=ON` and put that build's `llvm-config` on `PATH`. The regular dynamic build and `-d:LlvmLib=...` override are unchanged.

## Install

```sh
nimble install llvnim
```

Package page: <https://nimble.directory/pkg/llvnim>

Or vendor `src/llvnim.nim` and `import llvnim`.

## Nimoscope

`nimoscope` is a complete example of a compiler written with `llvnim`. It demonstrates how to build a frontend, generate LLVM IR, and JIT compile it.

Features:
- Lexer and parser for a small C-like language.
- AST generation.
- IR generation using `llvnim` and `llvnim/[dx, idiomatic]` helpers.
- JIT execution using `createLLJIT`.

Try it out:

```sh
cd examples/nimoscope
nim c -r main.nim
```

Example usage:
```
  >>> 
  ... def fib(a)
  ...   if a < 2 a;
  ...   else     fib(a - 1) + fib(a - 2);
  ...
  >>> fib(10);
55.0
  >>> extern sin(a);
  >>> 
  ... for i = 0; i < 7; i = i + 1; {
  ...   print(sin(i));
  ... }
  ...
0.000000
0.841471
0.909297
0.141120
-0.756802
-0.958924
-0.279415
```

## Quickstart

Build an `add` function, verify it, print the IR.

```nim
import llvnim

checkVersion()

let ctx = LLVMContextCreate()
defer: LLVMContextDispose(ctx)

let m = LLVMModuleCreateWithNameInContext("hello", ctx)
defer: LLVMDisposeModule(m)

let i32t = LLVMInt32TypeInContext(ctx)
var params = [i32t, i32t]
let fnTy = LLVMFunctionType(i32t, addr params[0], 2, LLVMFalse)
let fn = LLVMAddFunction(m, "add", fnTy)

let bb = LLVMAppendBasicBlockInContext(ctx, fn, "entry")
let b = LLVMCreateBuilderInContext(ctx)
defer: LLVMDisposeBuilder(b)
LLVMPositionBuilderAtEnd(b, bb)

let sum = LLVMBuildAdd(b, LLVMGetParam(fn, 0), LLVMGetParam(fn, 1), "sum")
discard LLVMBuildRet(b, sum)

let (ok, msg) = verifyModule(m)
doAssert ok, msg

let s = LLVMPrintModuleToString(m)
echo s
LLVMDisposeMessage(s)
```

Run it through LLJIT:

```nim
discard LLVMInitializeNativeTarget()
discard LLVMInitializeNativeAsmPrinter()

let (jit, jitErr) = createLLJIT()
doAssert jitErr.len == 0
doAssert addModule(jit, m).len == 0

let (addr, lookupErr) = lookup(jit, "add")
doAssert lookupErr.len == 0

type AddFn = proc(a, b: int64): int64 {.cdecl.}
echo cast[AddFn](addr)(20'i64, 22'i64)  # 42
```

### Developer Experience (DX) Helpers

If you are writing a compiler and want to reduce boilerplate, check out the `llvnim/dx` module. It contains helpers to create functions, iterate over basic blocks, and manage SSA values more idiomatically. See [docs/dx.md](docs/dx.md) for examples.

### C++ shim

Some LLJIT operations are only available in the C++ API: linking static libraries, loading platform dynamic libraries, creating and looking up symbols in arbitrary JITDylibs, mangling, initialize/deinitialize. `src/llvnim/shim.cc` bridges them to C symbols callable from Nim.

Requirements:

- A C++ compiler (`g++` or `clang++`) on PATH.
- LLVM C++ headers (`llvm/ExecutionEngine/Orc/LLJIT.h`).

Import `llvnim/dx` to use the shim wrappers. They are not part of the core `llvnim` module because they need the C++ toolchain.

### Idiomatic API

If you prefer a more Nim-friendly interface, import the `idiomatic` module. It automatically generates `camelCase` wrappers for all `LLVM*` functions (e.g., `contextCreate()` instead of `LLVMContextCreate()`) and provides RAII templates for safe memory management.

```nim
import llvnim/idiomatic

withContext(ctx):
  withModule(ctx, "hello", m):
    withBuilder(ctx, b):
      let i32t = int32TypeInContext(ctx)
      var params = [i32t, i32t]
      let fnTy = functionType(i32t, addr params[0], 2, LLVMFalse)
      let fn = addFunction(m, "add", fnTy)
      
      let bb = appendBasicBlockInContext(ctx, fn, "entry")
      positionBuilderAtEnd(b, bb)
      
      let sum = buildAdd(b, getParam(fn, 0), getParam(fn, 1), "sum")
      discard buildRet(b, sum)
      
      doAssert verifyModule(m).ok
```

## Examples

See the `examples/` directory for fully working scripts:
- `jit_calculator.nim`: Optimizing and executing code in memory via LLJIT.
- `aot_compiler.nim`: Compiling to an object file and inspecting it via `Object.h`.
- `di_compiler.nim`: Generating DWARF debug info for a function and emitting an object file.

## What it covers

- **Core IR**: Types (int, float, void, pointer, structs, arrays, vectors), Builder (arithmetic, casts, control flow, aggregates), Constants, Metadata, function/global/basic-block iterators.
- **Advanced Features**: PassBuilder (`LLVMRunPasses`), TargetMachine (AOT compilation to `.o` and `.s`), TargetData (layout, sizes, alignments), MCJIT, LLJIT (with a C++ shim for JITDylibs and dynamic libraries), Exceptions (`landingpad`), Atomics (`atomicrmw`, `cmpxchg`).
- **DebugInfo (DI)**: Complete DWARF generation support, including `DICompileUnit`, `DISubprogram`, local/global variables, function parameters, structs, pointers, arrays, and lexical blocks.
- **Utilities**: `IRReader` (parsing `.ll`), `BitReader`/`BitWriter` (reading/writing `.bc`), `Linker` (merging modules), `Object.h` (reading symbols/sections from `.o` files), `Disassembler`, Comdat.

The binding deliberately focuses on the API surface a compiler backend and JIT need in practice. The best way to check coverage is to look inside `src/llvnim.nim`: it is one readable file with plain declarations. Anything not there yet is easy to add by following the same pattern.

## Gotchas

- Version is fixed to LLVM 23.1.x. Different major.minor fails `checkVersion`. Future LLVM releases (24+) are planned to be supported. The old versions are not.
- `LLVMDisposeExecutionEngine` frees the module. Do not dispose it separately. `addModule` in LLJIT transfers ownership; on error it does not. Use `addModuleSafe` / `createJITSafe` to prevent double-free.
- Free strings from `LLVMPrint*ToString` with `LLVMDisposeMessage`.
- A context is not thread-safe. Use one context per thread.
- `LLVMInitializeNative*` supports amd64, i386, arm64. Other CPUs fail at compile time.
- `LLVMBuildUnwind` was removed from the C API in LLVM 23 and is not bound.
- `LLVMOrcCreateNewThreadSafeContextFromLLVMContext` takes ownership of the `LLVMContextRef`. Do not call `LLVMContextDispose` on it afterwards.
- The C++ shim in `src/llvnim/shim.cc` requires a C++17 compiler. If you only use the core `llvnim` module, the shim is not compiled.

## Limitations

- Not an exhaustive binding of the whole LLVM-C API. The focus is on the parts you need for a compiler backend and JIT, so the binding stays lean and easy to maintain.
- Dynamic loading via `dynlib` is the default; opt-in static linking is available with `-d:staticLlvm`.
- Tests (AOT emit, bitcode, Object.h) write to `/tmp` and assume a Unix-like system.
- `LLJIT::getTargetMachine()` is not exposed: it does not exist in LLVM 23's public `LLJIT` API. Use `targetDataFromJit` (DataLayout-based) instead.  

## License

MIT Copyright (c) 2026 https://github.com/xlebore3o4ka
