# Copyright (c) 2026 https://github.com/xlebore3o4ka
#
# Bindings for the LLVM-C API, version 23.1.1.
#
# Target/JIT initialization functions (LLVMInitialize*) are declared at the
# bottom of this file. Call them before creating an ExecutionEngine.

import std/hashes
import std/macros

when defined(staticLlvm):
  # Resolve the static archives and their platform dependencies at compile time.
  # llvm-config must point to the matching LLVM 23.1.x installation.
  const LlvmStaticLinkArgs = staticExec("llvm-config --link-static --libs --system-libs")
  {.passL: LlvmStaticLinkArgs.}
  {.pragma: llvmImport, cdecl, importc.}
else:
  when defined(windows):
    # Official LLVM 23.x Windows builds ship LLVM-C.dll.
    const LlvmLib {.strdefine.} = "LLVM-C.dll"
  elif defined(macosx):
    # Homebrew: /opt/homebrew/opt/llvm/lib/libLLVM.dylib (or libLLVM-23.dylib).
    # Locate via `llvm-config --libdir`. Override with -d:LlvmLib=...
    const LlvmLib {.strdefine.} = "libLLVM.dylib"
  else:
    # Fedora/Ubuntu/Debian: libLLVM-23.so.1; Arch: libLLVM.so;
    # upstream tarball: libLLVM.so.23.1. Override with -d:LlvmLib=...
    const LlvmLib {.strdefine.} = "libLLVM.so.23.1"

  {.pragma: llvmImport, cdecl, importc, dynlib: LlvmLib.}

proc LLVMGetVersion*(Major, Minor, Patch: var cuint) {.llvmImport.}

const
  ExpectedMajor* = 23
  ExpectedMinor* = 1

proc checkVersion*() =
  ## Raises ValueError if the loaded LLVM library version does not match
  ## ExpectedMajor.ExpectedMinor.
  var major, minor, patch: cuint
  LLVMGetVersion(major, minor, patch)
  if major != ExpectedMajor or minor != ExpectedMinor:
    raise newException(
      ValueError,
      "LLVM version mismatch: expected " &
        $ExpectedMajor & "." & $ExpectedMinor & ".x" & 
        ", got " & $major & "." & $minor & "." & $patch
    )

type
  LLVMContextRef*    = distinct pointer
  LLVMModuleRef*     = distinct pointer
  LLVMTypeRef*       = distinct pointer
  LLVMValueRef*      = distinct pointer
  LLVMBasicBlockRef* = distinct pointer
  LLVMBuilderRef*    = distinct pointer

  LLVMBool* = cint
  LLVMVerifierFailureAction* = cint

const
  LLVMFalse*: LLVMBool = 0
  LLVMTrue*:  LLVMBool = 1

  LLVMAbortProcessAction*:  LLVMVerifierFailureAction = 0
  LLVMPrintMessageAction*:  LLVMVerifierFailureAction = 1
  LLVMReturnStatusAction*:  LLVMVerifierFailureAction = 2

template definePointerOps(T: typedesc) =
  proc `==`*(a, b: T): bool {.inline.} =
    cast[pointer](a) == cast[pointer](b)
  proc isNil*(a: T): bool {.inline.} =
    cast[pointer](a).isNil
  proc `==`*(a: T; b: typeof(nil)): bool {.inline.} = a.isNil
  proc `==`*(a: typeof(nil); b: T): bool {.inline.} = b.isNil
  proc `$`*(a: T): string {.inline.} = $cast[uint](a)
  proc hash*(a: T): Hash {.inline.} = hash(cast[uint](a))

definePointerOps(LLVMContextRef)
definePointerOps(LLVMModuleRef)
definePointerOps(LLVMTypeRef)
definePointerOps(LLVMValueRef)
definePointerOps(LLVMBasicBlockRef)
definePointerOps(LLVMBuilderRef)

proc LLVMContextCreate*(): LLVMContextRef {.llvmImport.}
  ## A single context is not thread-safe; use one context per thread.

proc LLVMContextDisposeImpl(C: LLVMContextRef) {.llvmImport, importc: "LLVMContextDispose".}
proc LLVMContextDispose*(C: LLVMContextRef) {.inline.} =
  ## Do not call while modules/values created in C are still alive.
  doAssert not C.isNil, "LLVMContextDispose: nil context"
  LLVMContextDisposeImpl(C)

proc LLVMModuleCreateWithNameInContext*(
  ModuleID: cstring,
  C: LLVMContextRef
): LLVMModuleRef {.llvmImport.}
  ## Module is bound to C; C must outlive the module.

proc LLVMDisposeModuleImpl(M: LLVMModuleRef) {.llvmImport, importc: "LLVMDisposeModule".}
proc LLVMDisposeModule*(M: LLVMModuleRef) {.inline.} =
  doAssert not M.isNil, "LLVMDisposeModule: nil module"
  LLVMDisposeModuleImpl(M)

proc LLVMPrintModuleToString*(M: LLVMModuleRef): cstring {.llvmImport.}
  ## Free the result with LLVMDisposeMessage.

proc LLVMDisposeMessage*(Message: cstring) {.llvmImport.}

proc LLVMVerifyModule*(
  M: LLVMModuleRef,
  Action: LLVMVerifierFailureAction,
  OutMessage: var cstring
): LLVMBool {.llvmImport.}
  ## If OutMessage is non-nil after the call, free it with LLVMDisposeMessage.

proc verifyModule*(
  M: LLVMModuleRef,
  Action: LLVMVerifierFailureAction = LLVMReturnStatusAction
): tuple[ok: bool, msg: string] =
  ## Safe wrapper around LLVMVerifyModule: frees OutMessage automatically.
  ## `ok` is true when the module verifies; `msg` is empty on success.
  var outMsg: cstring
  defer:
    if not outMsg.isNil:
      LLVMDisposeMessage(outMsg)
  let rc = LLVMVerifyModule(M, Action, outMsg)
  result.ok = rc == LLVMFalse
  result.msg = if outMsg.isNil: "" else: $outMsg

proc LLVMInt32TypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}

proc LLVMFunctionType*(
  ReturnType: LLVMTypeRef,
  ParamTypes: ptr LLVMTypeRef,
  ParamCount: cuint,
  IsVarArg: LLVMBool
): LLVMTypeRef {.llvmImport.}

proc LLVMAddFunction*(
  M: LLVMModuleRef,
  Name: cstring,
  FunctionTy: LLVMTypeRef
): LLVMValueRef {.llvmImport.}

proc LLVMAppendBasicBlockInContext*(
  C: LLVMContextRef,
  Fn: LLVMValueRef,
  Name: cstring
): LLVMBasicBlockRef {.llvmImport.}

proc LLVMCreateBuilderInContext*(C: LLVMContextRef): LLVMBuilderRef {.llvmImport.}

proc LLVMDisposeBuilderImpl(B: LLVMBuilderRef) {.llvmImport, importc: "LLVMDisposeBuilder".}
proc LLVMDisposeBuilder*(B: LLVMBuilderRef) {.inline.} =
  doAssert not B.isNil, "LLVMDisposeBuilder: nil builder"
  LLVMDisposeBuilderImpl(B)

proc LLVMPositionBuilderAtEnd*(
  Builder: LLVMBuilderRef,
  BB: LLVMBasicBlockRef
) {.llvmImport.}

proc LLVMBuildAdd*(
  Builder: LLVMBuilderRef,
  LHS: LLVMValueRef,
  RHS: LLVMValueRef,
  Name: cstring
): LLVMValueRef {.llvmImport.}

proc LLVMBuildRet*(
  Builder: LLVMBuilderRef,
  V: LLVMValueRef
): LLVMValueRef {.llvmImport.}

# LLVMBuildUnwind was removed from the C API in LLVM 23.

proc LLVMConstInt*(
  IntTy: LLVMTypeRef,
  N: culonglong,
  SignExtend: LLVMBool
): LLVMValueRef {.llvmImport.}

proc LLVMGetParam*(
  Fn: LLVMValueRef,
  Index: cuint
): LLVMValueRef {.llvmImport.}

# LLVMInitializeAll* and LLVMInitializeNative* are `static inline` in
# llvm-c/Target.h and are not exported from libLLVM.so; reimplemented here
# via the per-architecture initializers, which are exported.
# NVPTX and SPIRV have no AsmParser/Disassembler backends in LLVM 23.1.1.

macro defineArchInit(arch: static string): untyped =
  result = newStmtList()
  for suffix in ["TargetInfo", "Target", "TargetMC",
                 "AsmParser", "AsmPrinter", "Disassembler"]:
    let name = ident("LLVMInitialize" & arch & suffix)
    result.add quote do:
      proc `name`*() {.llvmImport.}

macro defineArchInitNoAsm(arch: static string): untyped =
  result = newStmtList()
  for suffix in ["TargetInfo", "Target", "TargetMC", "AsmPrinter"]:
    let name = ident("LLVMInitialize" & arch & suffix)
    result.add quote do:
      proc `name`*() {.llvmImport.}

macro defineArchInitNoParser(arch: static string): untyped =
  result = newStmtList()
  for suffix in ["TargetInfo", "Target", "TargetMC",
                 "AsmPrinter", "Disassembler"]:
    let name = ident("LLVMInitialize" & arch & suffix)
    result.add quote do:
      proc `name`*() {.llvmImport.}

defineArchInit("AArch64")
defineArchInit("AMDGPU")
defineArchInit("ARM")
defineArchInit("AVR")
defineArchInit("BPF")
defineArchInit("Hexagon")
defineArchInit("Lanai")
defineArchInit("LoongArch")
defineArchInit("Mips")
defineArchInit("MSP430")
defineArchInitNoAsm("NVPTX")
defineArchInit("PowerPC")
defineArchInit("RISCV")
defineArchInit("Sparc")
defineArchInitNoAsm("SPIRV")
defineArchInit("SystemZ")
defineArchInit("VE")
defineArchInit("WebAssembly")
defineArchInit("X86")
defineArchInitNoParser("XCore")

const AllTargetArchs = [
  "AArch64", "AMDGPU", "ARM", "AVR", "BPF", "Hexagon",
  "Lanai", "LoongArch", "Mips", "MSP430", "NVPTX",
  "PowerPC", "RISCV", "Sparc", "SPIRV", "SystemZ", "VE",
  "WebAssembly", "X86", "XCore"
]

const AllAsmParserArchs = [
  "AArch64", "AMDGPU", "ARM", "AVR", "BPF", "Hexagon",
  "Lanai", "LoongArch", "Mips", "MSP430",
  "PowerPC", "RISCV", "Sparc", "SystemZ", "VE",
  "WebAssembly", "X86"
]

const AllDisassemblerArchs = [
  "AArch64", "AMDGPU", "ARM", "AVR", "BPF", "Hexagon",
  "Lanai", "LoongArch", "Mips", "MSP430",
  "PowerPC", "RISCV", "Sparc", "SystemZ", "VE",
  "WebAssembly", "X86", "XCore"
]

macro defineAllInit(name, suffix: static string, archs: static openArray[string]): untyped =
  let procName = ident(name)
  var body = newStmtList()
  for arch in archs:
    body.add newCall(ident("LLVMInitialize" & arch & suffix))
  result = quote do:
    proc `procName`*() =
      `body`

defineAllInit("LLVMInitializeAllTargetInfos", "TargetInfo", AllTargetArchs)
defineAllInit("LLVMInitializeAllTargets", "Target", AllTargetArchs)
defineAllInit("LLVMInitializeAllTargetMCs", "TargetMC", AllTargetArchs)
defineAllInit("LLVMInitializeAllAsmParsers", "AsmParser", AllAsmParserArchs)
defineAllInit("LLVMInitializeAllAsmPrinters", "AsmPrinter", AllTargetArchs)
defineAllInit("LLVMInitializeAllDisassemblers", "Disassembler", AllDisassemblerArchs)

proc LLVMInitializeNativeTarget*(): LLVMBool =
  when hostCPU == "amd64" or hostCPU == "i386":
    LLVMInitializeX86TargetInfo()
    LLVMInitializeX86Target()
    LLVMInitializeX86TargetMC()
  elif hostCPU == "arm64":
    LLVMInitializeAArch64TargetInfo()
    LLVMInitializeAArch64Target()
    LLVMInitializeAArch64TargetMC()
  else:
    {.error: "unsupported host CPU".}
  LLVMFalse

proc LLVMInitializeNativeAsmParser*(): LLVMBool =
  when hostCPU == "amd64" or hostCPU == "i386":
    LLVMInitializeX86AsmParser()
  elif hostCPU == "arm64":
    LLVMInitializeAArch64AsmParser()
  else:
    {.error: "unsupported host CPU".}
  LLVMFalse

proc LLVMInitializeNativeAsmPrinter*(): LLVMBool =
  when hostCPU == "amd64" or hostCPU == "i386":
    LLVMInitializeX86AsmPrinter()
  elif hostCPU == "arm64":
    LLVMInitializeAArch64AsmPrinter()
  else:
    {.error: "unsupported host CPU".}
  LLVMFalse

proc LLVMInitializeNativeDisassembler*(): LLVMBool =
  when hostCPU == "amd64" or hostCPU == "i386":
    LLVMInitializeX86Disassembler()
  elif hostCPU == "arm64":
    LLVMInitializeAArch64Disassembler()
  else:
    {.error: "unsupported host CPU".}
  LLVMFalse

# JIT (ExecutionEngine). Call LLVMInitializeNative* before createJIT.
# LLVMDisposeExecutionEngine frees the module: do not dispose it separately.

type
  LLVMExecutionEngineRef* = distinct pointer

definePointerOps(LLVMExecutionEngineRef)

proc LLVMCreateJITCompilerForModule*(
  OutJIT: var LLVMExecutionEngineRef,
  M: LLVMModuleRef,
  OptLevel: cuint,
  OutError: var cstring
): LLVMBool {.llvmImport.}

proc LLVMDisposeExecutionEngine*(EE: LLVMExecutionEngineRef) {.llvmImport.}

proc LLVMGetFunctionAddress*(
  EE: LLVMExecutionEngineRef,
  Name: cstring
): uint64 {.llvmImport.}

proc createJIT*(
  M: LLVMModuleRef,
  OptLevel: cuint = 0
): tuple[ee: LLVMExecutionEngineRef, err: string] =
  ## Creates an MCJIT engine for M. Returns ee=nil and a non-empty err on failure.
  ## On success, the engine owns M: do not dispose M separately.
  var ee: LLVMExecutionEngineRef
  var errMsg: cstring
  defer:
    if not errMsg.isNil:
      LLVMDisposeMessage(errMsg)
  let rc = LLVMCreateJITCompilerForModule(ee, M, OptLevel, errMsg)
  result.ee = if rc == LLVMFalse: ee else: default(LLVMExecutionEngineRef)
  result.err = if errMsg.isNil: "" else: $errMsg

# Additional types (iN, float, double, void, pointer) and basic instructions.
proc LLVMInt1TypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}
proc LLVMInt8TypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}
proc LLVMInt16TypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}
proc LLVMInt64TypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}
proc LLVMInt128TypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}
proc LLVMIntTypeInContext*(C: LLVMContextRef, NumBits: cuint): LLVMTypeRef {.llvmImport.}

proc LLVMFloatTypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}
proc LLVMDoubleTypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}
proc LLVMVoidTypeInContext*(C: LLVMContextRef): LLVMTypeRef {.llvmImport.}
proc LLVMPointerType*(ElementType: LLVMTypeRef, AddressSpace: cuint): LLVMTypeRef {.llvmImport.}
proc LLVMPointerTypeInContext*(C: LLVMContextRef, AddressSpace: cuint): LLVMTypeRef {.llvmImport.}

type
  LLVMIntPredicate* {.size: sizeof(cint).} = enum
    LLVMIntEQ = 32
    LLVMIntNE = 33
    LLVMIntUGT = 34
    LLVMIntUGE = 35
    LLVMIntULT = 36
    LLVMIntULE = 37
    LLVMIntSGT = 38
    LLVMIntSGE = 39
    LLVMIntSLT = 40
    LLVMIntSLE = 41

proc LLVMBuildSub*(Builder: LLVMBuilderRef, LHS, RHS: LLVMValueRef, Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildMul*(Builder: LLVMBuilderRef, LHS, RHS: LLVMValueRef, Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildUDiv*(Builder: LLVMBuilderRef, LHS, RHS: LLVMValueRef, Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildSDiv*(Builder: LLVMBuilderRef, LHS, RHS: LLVMValueRef, Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildURem*(Builder: LLVMBuilderRef, LHS, RHS: LLVMValueRef, Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildSRem*(Builder: LLVMBuilderRef, LHS, RHS: LLVMValueRef, Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMBuildICmp*(Builder: LLVMBuilderRef, Op: LLVMIntPredicate, LHS, RHS: LLVMValueRef, Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMBuildBr*(Builder: LLVMBuilderRef, Dest: LLVMBasicBlockRef): LLVMValueRef {.llvmImport.}
proc LLVMBuildCondBr*(Builder: LLVMBuilderRef, If: LLVMValueRef, Then, Else: LLVMBasicBlockRef): LLVMValueRef {.llvmImport.}
proc LLVMBuildRetVoid*(Builder: LLVMBuilderRef): LLVMValueRef {.llvmImport.}

proc LLVMBuildAlloca*(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildLoad2*(Builder: LLVMBuilderRef, Ty: LLVMTypeRef, PointerVal: LLVMValueRef, Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildStore*(Builder: LLVMBuilderRef, Val, Ptr: LLVMValueRef): LLVMValueRef {.llvmImport.}

proc LLVMBuildCall2*(
  Builder: LLVMBuilderRef,
  FnTy: LLVMTypeRef,
  Fn: LLVMValueRef,
  Args: ptr LLVMValueRef,
  NumArgs: cuint,
  Name: cstring
): LLVMValueRef {.llvmImport.}

type
  LLVMTypeKind* {.size: sizeof(cint).} = enum
    LLVMVoidTypeKind = 0
    LLVMHalfTypeKind = 1
    LLVMFloatTypeKind = 2
    LLVMDoubleTypeKind = 3
    LLVMX86_FP80TypeKind = 4
    LLVMFP128TypeKind = 5
    LLVMPPC_FP128TypeKind = 6
    LLVMLabelTypeKind = 7
    LLVMIntegerTypeKind = 8
    LLVMFunctionTypeKind = 9
    LLVMStructTypeKind = 10
    LLVMArrayTypeKind = 11
    LLVMPointerTypeKind = 12
    LLVMVectorTypeKind = 13
    LLVMMetadataTypeKind = 14
    LLVMTokenTypeKind = 16
    LLVMScalableVectorTypeKind = 17
    LLVMBFloatTypeKind = 18
    LLVMX86_AMXTypeKind = 19
    LLVMTargetExtTypeKind = 20
    LLVMByteTypeKind = 21

proc LLVMGetTypeKind*(Ty: LLVMTypeRef): LLVMTypeKind {.llvmImport.}

proc LLVMPrintValueToString*(Val: LLVMValueRef): cstring {.llvmImport.}
  ## Free with LLVMDisposeMessage.

proc LLVMDumpModule*(M: LLVMModuleRef) {.llvmImport.}
  ## Dumps to stderr. For quick debugging; prefer LLVMPrintModuleToString.

type
  LLVMOrcThreadSafeContextRef* = distinct pointer
  LLVMOrcThreadSafeModuleRef*  = distinct pointer
  LLVMOrcLLJITRef*             = distinct pointer
  LLVMErrorRef*                = distinct pointer
  LLVMOrcJITDylibRef*          = distinct pointer

definePointerOps(LLVMOrcThreadSafeContextRef)
definePointerOps(LLVMOrcThreadSafeModuleRef)
definePointerOps(LLVMOrcLLJITRef)
definePointerOps(LLVMErrorRef)
definePointerOps(LLVMOrcJITDylibRef)

proc LLVMOrcCreateNewThreadSafeContext*(): LLVMOrcThreadSafeContextRef {.llvmImport.}
proc LLVMOrcDisposeThreadSafeContext*(TSCtx: LLVMOrcThreadSafeContextRef) {.llvmImport.}
proc LLVMOrcCreateNewThreadSafeModule*(
  M: LLVMModuleRef,
  TSCtx: LLVMOrcThreadSafeContextRef
): LLVMOrcThreadSafeModuleRef {.llvmImport.}

proc LLVMOrcCreateLLJIT*(
  Result: var LLVMOrcLLJITRef,
  Builder: pointer = nil
): LLVMErrorRef {.llvmImport.}

proc LLVMOrcDisposeLLJIT*(J: LLVMOrcLLJITRef): LLVMErrorRef {.llvmImport.}

proc LLVMOrcLLJITGetMainJITDylib*(J: LLVMOrcLLJITRef): LLVMOrcJITDylibRef {.llvmImport.}

proc LLVMOrcLLJITAddLLVMIRModule*(
  J: LLVMOrcLLJITRef,
  JD: LLVMOrcJITDylibRef,
  TSM: LLVMOrcThreadSafeModuleRef
): LLVMErrorRef {.llvmImport.}

proc LLVMOrcDisposeThreadSafeModule*(TSM: LLVMOrcThreadSafeModuleRef) {.llvmImport.}

proc LLVMOrcLLJITLookup*(
  J: LLVMOrcLLJITRef,
  Result: var uint64,
  Name: cstring
): LLVMErrorRef {.llvmImport.}

proc LLVMGetErrorMessage*(Err: LLVMErrorRef): cstring {.llvmImport.}
proc LLVMDisposeErrorMessage*(ErrMsg: cstring) {.llvmImport.}

proc createLLJIT*(): tuple[jit: LLVMOrcLLJITRef, err: string] =
  var jit: LLVMOrcLLJITRef
  let errRef = LLVMOrcCreateLLJIT(jit)
  if not errRef.isNil:
    let msg = LLVMGetErrorMessage(errRef)
    result.err = $msg
    LLVMDisposeErrorMessage(msg)
    result.jit = LLVMOrcLLJITRef(nil)
  else:
    result.jit = jit

proc addModule*(jit: LLVMOrcLLJITRef, m: LLVMModuleRef): string =
  ## Transfers ownership of m to the JIT.
  let tsc = LLVMOrcCreateNewThreadSafeContext()
  let tsm = LLVMOrcCreateNewThreadSafeModule(m, tsc)
  LLVMOrcDisposeThreadSafeContext(tsc)
  let jd = LLVMOrcLLJITGetMainJITDylib(jit)
  let errRef = LLVMOrcLLJITAddLLVMIRModule(jit, jd, tsm)
  if not errRef.isNil:
    let msg = LLVMGetErrorMessage(errRef)
    result = $msg
    LLVMDisposeErrorMessage(msg)
    LLVMOrcDisposeThreadSafeModule(tsm)  # ownership not transferred on error

proc lookup*(jit: LLVMOrcLLJITRef, name: cstring): tuple[addrr: uint64, err: string] =
  var addrr: uint64
  let errRef = LLVMOrcLLJITLookup(jit, addrr, name)
  if not errRef.isNil:
    let msg = LLVMGetErrorMessage(errRef)
    result.err = $msg
    LLVMDisposeErrorMessage(msg)
    result.addrr = 0
  else:
    result.addrr = addrr

type
  LLVMLinkage* {.size: sizeof(cint).} = enum
    LLVMExternalLinkage = 0
    LLVMAvailableExternallyLinkage = 1
    LLVMLinkOnceAnyLinkage = 2
    LLVMLinkOnceODRLinkage = 3
    LLVMLinkOnceODRAutoHideLinkage = 4
    LLVMWeakAnyLinkage = 5
    LLVMWeakODRLinkage = 6
    LLVMAppendingLinkage = 7
    LLVMInternalLinkage = 8
    LLVMPrivateLinkage = 9
    LLVMDLLImportLinkage = 10
    LLVMDLLExportLinkage = 11
    LLVMExternalWeakLinkage = 12
    LLVMGhostLinkage = 13
    LLVMCommonLinkage = 14
    LLVMLinkerPrivateLinkage = 15
    LLVMLinkerPrivateWeakLinkage = 16

  LLVMUnnamedAddr* {.size: sizeof(cint).} = enum
    LLVMNoUnnamedAddr = 0
    LLVMLocalUnnamedAddr = 1
    LLVMGlobalUnnamedAddr = 2

proc LLVMConstStringInContext2*(C: LLVMContextRef; Str: cstring; Length: csize_t; DontNullTerminate: LLVMBool): LLVMValueRef {.llvmImport.}
proc LLVMArrayType2*(ElementType: LLVMTypeRef; ElementCount: uint64): LLVMTypeRef {.llvmImport.}

proc LLVMAddGlobal*(M: LLVMModuleRef; Ty: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMAddGlobalInAddressSpace*(M: LLVMModuleRef; Ty: LLVMTypeRef; Name: cstring; AddressSpace: cuint): LLVMValueRef {.llvmImport.}
proc LLVMGetNamedGlobal*(M: LLVMModuleRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMDeleteGlobal*(GlobalVar: LLVMValueRef) {.llvmImport.}
proc LLVMGetInitializer*(GlobalVar: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMSetInitializer*(GlobalVar: LLVMValueRef; ConstantVal: LLVMValueRef) {.llvmImport.}
proc LLVMIsGlobalConstant*(GlobalVar: LLVMValueRef): LLVMBool {.llvmImport.}
proc LLVMSetGlobalConstant*(GlobalVar: LLVMValueRef; IsConstant: LLVMBool) {.llvmImport.}
proc LLVMGetLinkage*(Global: LLVMValueRef): LLVMLinkage {.llvmImport.}
proc LLVMSetLinkage*(Global: LLVMValueRef; Linkage: LLVMLinkage) {.llvmImport.}
proc LLVMGetUnnamedAddress*(Global: LLVMValueRef): LLVMUnnamedAddr {.llvmImport.}
proc LLVMSetUnnamedAddress*(Global: LLVMValueRef; UnnamedAddr: LLVMUnnamedAddr) {.llvmImport.}
proc LLVMSetAlignment*(V: LLVMValueRef; Bytes: cuint) {.llvmImport.}
proc LLVMGlobalGetValueType*(Global: LLVMValueRef): LLVMTypeRef {.llvmImport.}
proc LLVMGetGlobalParent*(Global: LLVMValueRef): LLVMModuleRef {.llvmImport.}

proc addGlobalString*(m: LLVMModuleRef; ctx: LLVMContextRef; name, value: string): LLVMValueRef =
  ## Adds a private constant [N x i8] global with unnamed address, no trailing NUL.
  let arrTy = LLVMArrayType2(LLVMInt8TypeInContext(ctx), uint64(value.len))
  let init = LLVMConstStringInContext2(ctx, value.cstring, csize_t(value.len), LLVMTrue)
  result = LLVMAddGlobal(m, arrTy, name.cstring)
  LLVMSetInitializer(result, init)
  LLVMSetGlobalConstant(result, LLVMTrue)
  LLVMSetLinkage(result, LLVMPrivateLinkage)
  LLVMSetUnnamedAddress(result, LLVMGlobalUnnamedAddr)

proc LLVMBuildArrayAlloca*(Builder: LLVMBuilderRef; Ty: LLVMTypeRef; Val: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildMalloc*(Builder: LLVMBuilderRef; Ty: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildArrayMalloc*(Builder: LLVMBuilderRef; Ty: LLVMTypeRef; Val: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFree*(Builder: LLVMBuilderRef; PointerVal: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMBuildGEP2*(Builder: LLVMBuilderRef; Ty: LLVMTypeRef; Pointer: LLVMValueRef; Indices: ptr LLVMValueRef; NumIndices: cuint; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildInBoundsGEP2*(Builder: LLVMBuilderRef; Ty: LLVMTypeRef; Pointer: LLVMValueRef; Indices: ptr LLVMValueRef; NumIndices: cuint; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildGlobalString*(Builder: LLVMBuilderRef; Str: cstring; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildGlobalStringPtr*(Builder: LLVMBuilderRef; Str: cstring; Name: cstring): LLVMValueRef {.llvmImport.}

proc buildGEP2*(b: LLVMBuilderRef; ty: LLVMTypeRef; base: LLVMValueRef; indices: openArray[LLVMValueRef]; name: cstring = ""): LLVMValueRef =
  ## Convenience wrapper around LLVMBuildGEP2 for Nim openArray indices.
  if indices.len == 0:
    LLVMBuildGEP2(b, ty, base, nil, 0, name)
  else:
    LLVMBuildGEP2(b, ty, base, cast[ptr LLVMValueRef](unsafeAddr indices[0]), cuint(indices.len), name)

proc buildInBoundsGEP2*(b: LLVMBuilderRef; ty: LLVMTypeRef; base: LLVMValueRef; indices: openArray[LLVMValueRef]; name: cstring = ""): LLVMValueRef =
  ## Convenience wrapper around LLVMBuildInBoundsGEP2 for Nim openArray indices.
  if indices.len == 0:
    LLVMBuildInBoundsGEP2(b, ty, base, nil, 0, name)
  else:
    LLVMBuildInBoundsGEP2(b, ty, base, cast[ptr LLVMValueRef](unsafeAddr indices[0]), cuint(indices.len), name)

proc LLVMBuildAnd*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildOr*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildXor*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildShl*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildLShr*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildAShr*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildNeg*(Builder: LLVMBuilderRef; V: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildNot*(Builder: LLVMBuilderRef; V: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildExactSDiv*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildExactUDiv*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMBuildBitCast*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildPtrToInt*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildIntToPtr*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildTrunc*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildZExt*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildSExt*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildIntCast2*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; IsSigned: LLVMBool; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildAddrSpaceCast*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMBuildFAdd*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFSub*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFMul*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFDiv*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFRem*(Builder: LLVMBuilderRef; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFNeg*(Builder: LLVMBuilderRef; V: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMBuildFPExt*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFPTrunc*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFPToSI*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFPToUI*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildSIToFP*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildUIToFP*(Builder: LLVMBuilderRef; V: LLVMValueRef; DestTy: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}

type
  LLVMRealPredicate* {.size: sizeof(cint).} = enum
    LLVMRealPredicateFalse = 0
    LLVMRealOEQ = 1
    LLVMRealOGT = 2
    LLVMRealOGE = 3
    LLVMRealOLT = 4
    LLVMRealOLE = 5
    LLVMRealONE = 6
    LLVMRealORD = 7
    LLVMRealUNO = 8
    LLVMRealUEQ = 9
    LLVMRealUGT = 10
    LLVMRealUGE = 11
    LLVMRealULT = 12
    LLVMRealULE = 13
    LLVMRealUNE = 14
    LLVMRealPredicateTrue = 15

proc LLVMBuildFCmp*(Builder: LLVMBuilderRef; Op: LLVMRealPredicate; LHS: LLVMValueRef; RHS: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMConstReal*(RealTy: LLVMTypeRef; N: cdouble): LLVMValueRef {.llvmImport.}
proc LLVMConstRealOfString*(RealTy: LLVMTypeRef; Text: cstring): LLVMValueRef {.llvmImport.}
proc LLVMConstRealOfStringAndSize*(RealTy: LLVMTypeRef; Text: cstring; TextLen: cuint): LLVMValueRef {.llvmImport.}
proc LLVMConstNull*(Ty: LLVMTypeRef): LLVMValueRef {.llvmImport.}
proc LLVMConstPointerNull*(Ty: LLVMTypeRef): LLVMValueRef {.llvmImport.}

proc LLVMBuildSwitch*(Builder: LLVMBuilderRef; V: LLVMValueRef; Else: LLVMBasicBlockRef; NumCases: cuint): LLVMValueRef {.llvmImport.}
proc LLVMAddCase*(Switch: LLVMValueRef; OnVal: LLVMValueRef; Dest: LLVMBasicBlockRef) {.llvmImport.}
proc LLVMBuildPhi*(Builder: LLVMBuilderRef; Ty: LLVMTypeRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMAddIncoming*(PhiNode: LLVMValueRef; IncomingVals: ptr LLVMValueRef; IncomingBlocks: ptr LLVMBasicBlockRef; Count: cuint) {.llvmImport.}
proc LLVMBuildSelect*(Builder: LLVMBuilderRef; If: LLVMValueRef; Then: LLVMValueRef; Else: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildUnreachable*(Builder: LLVMBuilderRef): LLVMValueRef {.llvmImport.}
proc LLVMBuildIndirectBr*(Builder: LLVMBuilderRef; Addr: LLVMValueRef; NumDests: cuint): LLVMValueRef {.llvmImport.}
proc LLVMAddDestination*(IndirectBr: LLVMValueRef; Dest: LLVMBasicBlockRef) {.llvmImport.}
proc LLVMBuildInvoke2*(Builder: LLVMBuilderRef; Ty: LLVMTypeRef; Fn: LLVMValueRef; Args: ptr LLVMValueRef; NumArgs: cuint; Then: LLVMBasicBlockRef; Catch: LLVMBasicBlockRef; Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMStructTypeInContext*(C: LLVMContextRef; ElementTypes: ptr LLVMTypeRef; ElementCount: cuint; Packed: LLVMBool): LLVMTypeRef {.llvmImport.}
proc LLVMStructCreateNamed*(C: LLVMContextRef; Name: cstring): LLVMTypeRef {.llvmImport.}
proc LLVMStructSetBody*(StructTy: LLVMTypeRef; ElementTypes: ptr LLVMTypeRef; ElementCount: cuint; Packed: LLVMBool) {.llvmImport.}
proc LLVMStructGetTypeAtIndex*(StructTy: LLVMTypeRef; i: cuint): LLVMTypeRef {.llvmImport.}
proc LLVMGetStructName*(StructTy: LLVMTypeRef): cstring {.llvmImport.}
proc LLVMIsPackedStruct*(StructTy: LLVMTypeRef): LLVMBool {.llvmImport.}
proc LLVMIsOpaqueStruct*(StructTy: LLVMTypeRef): LLVMBool {.llvmImport.}
proc LLVMIsLiteralStruct*(StructTy: LLVMTypeRef): LLVMBool {.llvmImport.}

proc LLVMVectorType*(ElementType: LLVMTypeRef; ElementCount: cuint): LLVMTypeRef {.llvmImport.}
proc LLVMScalableVectorType*(ElementType: LLVMTypeRef; ElementCount: cuint): LLVMTypeRef {.llvmImport.}

proc LLVMArrayType*(ElementType: LLVMTypeRef; ElementCount: cuint): LLVMTypeRef {.llvmImport.}
proc LLVMGetElementType*(Ty: LLVMTypeRef): LLVMTypeRef {.llvmImport.}
proc LLVMGetArrayLength2*(ArrayTy: LLVMTypeRef): uint64 {.llvmImport.}
proc LLVMGetVectorSize*(VectorTy: LLVMTypeRef): cuint {.llvmImport.}

proc LLVMBuildExtractValue*(Builder: LLVMBuilderRef; AggVal: LLVMValueRef; Index: cuint; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildInsertValue*(Builder: LLVMBuilderRef; AggVal: LLVMValueRef; ElemVal: LLVMValueRef; Index: cuint; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildExtractElement*(Builder: LLVMBuilderRef; VecVal: LLVMValueRef; Index: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildInsertElement*(Builder: LLVMBuilderRef; VecVal: LLVMValueRef; ElemVal: LLVMValueRef; Index: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildShuffleVector*(Builder: LLVMBuilderRef; V1: LLVMValueRef; V2: LLVMValueRef; Mask: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildFreeze*(Builder: LLVMBuilderRef; Val: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMConstStructInContext*(C: LLVMContextRef; ConstantVals: ptr LLVMValueRef; Count: cuint; Packed: LLVMBool): LLVMValueRef {.llvmImport.}
proc LLVMConstVector*(ScalarConstantVals: ptr LLVMValueRef; Size: cuint): LLVMValueRef {.llvmImport.}
proc LLVMConstArray2*(ElementTy: LLVMTypeRef; ConstantVals: ptr LLVMValueRef; Length: uint64): LLVMValueRef {.llvmImport.}
proc LLVMGetAggregateElement*(C: LLVMValueRef; Idx: cuint): LLVMValueRef {.llvmImport.}
proc LLVMGetUndef*(Ty: LLVMTypeRef): LLVMValueRef {.llvmImport.}

proc LLVMConstNeg*(ConstantVal: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstNot*(ConstantVal: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstAdd*(LHSConstant: LLVMValueRef; RHSConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstSub*(LHSConstant: LLVMValueRef; RHSConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstXor*(LHSConstant: LLVMValueRef; RHSConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstNSWAdd*(LHSConstant: LLVMValueRef; RHSConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstNSWSub*(LHSConstant: LLVMValueRef; RHSConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstNSWNeg*(ConstantVal: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstNUWAdd*(LHSConstant: LLVMValueRef; RHSConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstNUWSub*(LHSConstant: LLVMValueRef; RHSConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}

proc LLVMConstTrunc*(ConstantVal: LLVMValueRef; ToType: LLVMTypeRef): LLVMValueRef {.llvmImport.}
proc LLVMConstPtrToInt*(ConstantVal: LLVMValueRef; ToType: LLVMTypeRef): LLVMValueRef {.llvmImport.}
proc LLVMConstIntToPtr*(ConstantVal: LLVMValueRef; ToType: LLVMTypeRef): LLVMValueRef {.llvmImport.}
proc LLVMConstBitCast*(ConstantVal: LLVMValueRef; ToType: LLVMTypeRef): LLVMValueRef {.llvmImport.}
proc LLVMConstAddrSpaceCast*(ConstantVal: LLVMValueRef; ToType: LLVMTypeRef): LLVMValueRef {.llvmImport.}
proc LLVMConstPointerCast*(ConstantVal: LLVMValueRef; ToType: LLVMTypeRef): LLVMValueRef {.llvmImport.}

proc LLVMConstGEP2*(Ty: LLVMTypeRef; ConstantVal: LLVMValueRef; ConstantIndices: ptr LLVMValueRef; NumIndices: cuint): LLVMValueRef {.llvmImport.}
proc LLVMConstInBoundsGEP2*(Ty: LLVMTypeRef; ConstantVal: LLVMValueRef; ConstantIndices: ptr LLVMValueRef; NumIndices: cuint): LLVMValueRef {.llvmImport.}

proc LLVMConstShuffleVector*(VectorA: LLVMValueRef; VectorB: LLVMValueRef; Mask: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstExtractElement*(VectorConstant: LLVMValueRef; IndexConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMConstInsertElement*(VectorConstant: LLVMValueRef; ElementValueConstant: LLVMValueRef; IndexConstant: LLVMValueRef): LLVMValueRef {.llvmImport.}

proc LLVMConstAllOnes*(Ty: LLVMTypeRef): LLVMValueRef {.llvmImport.}

proc LLVMIsConstant*(Val: LLVMValueRef): LLVMBool {.llvmImport.}
proc LLVMIsNull*(Val: LLVMValueRef): LLVMBool {.llvmImport.}
proc LLVMIsUndef*(Val: LLVMValueRef): LLVMBool {.llvmImport.}

proc LLVMConstIntGetSExtValue*(ConstantVal: LLVMValueRef): clonglong {.llvmImport.}
proc LLVMConstIntGetZExtValue*(ConstantVal: LLVMValueRef): culonglong {.llvmImport.}
proc LLVMConstRealGetDouble*(ConstantVal: LLVMValueRef; Lossy: ptr LLVMBool): cdouble {.llvmImport.}

type
  LLVMAtomicOrdering* {.size: sizeof(cint).} = enum
    LLVMAtomicOrderingNotAtomic = 0
    LLVMAtomicOrderingUnordered = 1
    LLVMAtomicOrderingMonotonic = 2
    LLVMAtomicOrderingAcquire = 4
    LLVMAtomicOrderingRelease = 5
    LLVMAtomicOrderingAcquireRelease = 6
    LLVMAtomicOrderingSequentiallyConsistent = 7

  LLVMAtomicRMWBinOp* {.size: sizeof(cint).} = enum
    LLVMAtomicRMWBinOpXchg = 0
    LLVMAtomicRMWBinOpAdd = 1
    LLVMAtomicRMWBinOpSub = 2
    LLVMAtomicRMWBinOpAnd = 3
    LLVMAtomicRMWBinOpNand = 4
    LLVMAtomicRMWBinOpOr = 5
    LLVMAtomicRMWBinOpXor = 6
    LLVMAtomicRMWBinOpMax = 7
    LLVMAtomicRMWBinOpMin = 8
    LLVMAtomicRMWBinOpUMax = 9
    LLVMAtomicRMWBinOpUMin = 10
    LLVMAtomicRMWBinOpFAdd = 11
    LLVMAtomicRMWBinOpFSub = 12
    LLVMAtomicRMWBinOpFMax = 13
    LLVMAtomicRMWBinOpFMin = 14
    LLVMAtomicRMWBinOpUIncWrap = 15
    LLVMAtomicRMWBinOpUDecWrap = 16
    LLVMAtomicRMWBinOpUSubCond = 17
    LLVMAtomicRMWBinOpUSubSat = 18

proc LLVMBuildAtomicRMW*(Builder: LLVMBuilderRef; Op: LLVMAtomicRMWBinOp; PTR: LLVMValueRef; Val: LLVMValueRef; Ordering: LLVMAtomicOrdering; SingleThread: LLVMBool): LLVMValueRef {.llvmImport.}
proc LLVMBuildAtomicCmpXchg*(Builder: LLVMBuilderRef; PTR: LLVMValueRef; Cmp: LLVMValueRef; New: LLVMValueRef; SuccessOrdering: LLVMAtomicOrdering; FailureOrdering: LLVMAtomicOrdering; SingleThread: LLVMBool): LLVMValueRef {.llvmImport.}
proc LLVMBuildFence*(Builder: LLVMBuilderRef; Ordering: LLVMAtomicOrdering; SingleThread: LLVMBool; Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMBuildResume*(Builder: LLVMBuilderRef; Exn: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMBuildLandingPad*(Builder: LLVMBuilderRef; Ty: LLVMTypeRef; PersFn: LLVMValueRef; NumClauses: cuint; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMAddClause*(LandingPad: LLVMValueRef; ClauseVal: LLVMValueRef) {.llvmImport.}
proc LLVMSetCleanup*(LandingPad: LLVMValueRef; Val: LLVMBool) {.llvmImport.}
proc LLVMBuildCatchSwitch*(Builder: LLVMBuilderRef; ParentPad: LLVMValueRef; UnwindBB: LLVMBasicBlockRef; NumHandlers: cuint; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildCatchPad*(Builder: LLVMBuilderRef; ParentPad: LLVMValueRef; Args: ptr LLVMValueRef; NumArgs: cuint; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildCleanupPad*(Builder: LLVMBuilderRef; ParentPad: LLVMValueRef; Args: ptr LLVMValueRef; NumArgs: cuint; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMBuildCatchRet*(Builder: LLVMBuilderRef; CatchPad: LLVMValueRef; BB: LLVMBasicBlockRef): LLVMValueRef {.llvmImport.}
proc LLVMBuildCleanupRet*(Builder: LLVMBuilderRef; CatchPad: LLVMValueRef; BB: LLVMBasicBlockRef): LLVMValueRef {.llvmImport.}

type
  LLVMTargetMachineRef* = distinct pointer
  LLVMPassBuilderOptionsRef* = distinct pointer

definePointerOps(LLVMTargetMachineRef)
definePointerOps(LLVMPassBuilderOptionsRef)

proc LLVMCreatePassBuilderOptions*(): LLVMPassBuilderOptionsRef {.llvmImport.}
proc LLVMDisposePassBuilderOptions*(Options: LLVMPassBuilderOptionsRef) {.llvmImport.}
proc LLVMRunPasses*(M: LLVMModuleRef; Passes: cstring; TM: LLVMTargetMachineRef; Options: LLVMPassBuilderOptionsRef): LLVMErrorRef {.llvmImport.}
proc LLVMRunPassesOnFunction*(F: LLVMValueRef; Passes: cstring; TM: LLVMTargetMachineRef; Options: LLVMPassBuilderOptionsRef): LLVMErrorRef {.llvmImport.}

type
  LLVMTargetRef* = distinct pointer

  LLVMCodeGenOptLevel* {.size: sizeof(cint).} = enum
    LLVMCodeGenLevelNone = 0
    LLVMCodeGenLevelLess = 1
    LLVMCodeGenLevelDefault = 2
    LLVMCodeGenLevelAggressive = 3

  LLVMRelocMode* {.size: sizeof(cint).} = enum
    LLVMRelocDefault = 0
    LLVMRelocStatic = 1
    LLVMRelocPIC = 2
    LLVMRelocDynamicNoPic = 3
    LLVMRelocROPI = 4
    LLVMRelocRWPI = 5
    LLVMRelocROPI_RWPI = 6

  LLVMCodeModel* {.size: sizeof(cint).} = enum
    LLVMCodeModelDefault = 0
    LLVMCodeModelJITDefault = 1
    LLVMCodeModelTiny = 2
    LLVMCodeModelSmall = 3
    LLVMCodeModelKernel = 4
    LLVMCodeModelMedium = 5
    LLVMCodeModelLarge = 6

  LLVMCodeGenFileType* {.size: sizeof(cint).} = enum
    LLVMAssemblyFile = 0
    LLVMObjectFile = 1

definePointerOps(LLVMTargetRef)

proc LLVMGetDefaultTargetTriple*(): cstring {.llvmImport.}
proc LLVMGetTargetFromTriple*(Triple: cstring; T: var LLVMTargetRef; ErrorMessage: var cstring): LLVMBool {.llvmImport.}
proc LLVMGetTargetName*(T: LLVMTargetRef): cstring {.llvmImport.}

proc LLVMCreateTargetMachine*(T: LLVMTargetRef; Triple: cstring; CPU: cstring; Features: cstring; Level: LLVMCodeGenOptLevel; Reloc: LLVMRelocMode; CodeModel: LLVMCodeModel): LLVMTargetMachineRef {.llvmImport.}
proc LLVMDisposeTargetMachine*(T: LLVMTargetMachineRef) {.llvmImport.}

proc LLVMSetTarget*(M: LLVMModuleRef; Triple: cstring) {.llvmImport.}
proc LLVMSetDataLayout*(M: LLVMModuleRef; DataLayoutStr: cstring) {.llvmImport.}

proc LLVMTargetMachineEmitToFile*(T: LLVMTargetMachineRef; M: LLVMModuleRef; Filename: cstring; codegen: LLVMCodeGenFileType; ErrorMessage: var cstring): LLVMBool {.llvmImport.}

type
  LLVMAttributeRef* = distinct pointer

definePointerOps(LLVMAttributeRef)

const
  LLVMAttributeReturnIndex* = 0.cuint
  LLVMAttributeFunctionIndex* = high(cuint)

proc LLVMCreateEnumAttribute*(C: LLVMContextRef; KindID: cuint; Val: uint64): LLVMAttributeRef {.llvmImport.}
proc LLVMCreateStringAttribute*(C: LLVMContextRef; K: cstring; KLength: cuint; V: cstring; VLength: cuint): LLVMAttributeRef {.llvmImport.}
proc LLVMGetEnumAttributeKindForName*(Name: cstring; SLen: csize_t): cuint {.llvmImport.}
proc LLVMGetEnumAttributeKind*(A: LLVMAttributeRef): cuint {.llvmImport.}
proc LLVMGetEnumAttributeValue*(A: LLVMAttributeRef): uint64 {.llvmImport.}

proc LLVMAddAttributeAtIndex*(F: LLVMValueRef; Idx: cuint; A: LLVMAttributeRef) {.llvmImport.}
proc LLVMRemoveEnumAttributeAtIndex*(F: LLVMValueRef; Idx: cuint; KindID: cuint) {.llvmImport.}
proc LLVMGetEnumAttributeAtIndex*(F: LLVMValueRef; Idx: cuint; KindID: cuint): LLVMAttributeRef {.llvmImport.}

proc LLVMAddTargetDependentFunctionAttr*(Fn: LLVMValueRef; A: cstring; V: cstring) {.llvmImport.}

proc addStringAttribute*(ctx: LLVMContextRef; fn: LLVMValueRef; key, value: string) =
  ## Adds a string attribute (e.g. "target-cpu"="skylake") to a function.
  let attr = LLVMCreateStringAttribute(ctx, key.cstring, cuint(key.len), value.cstring, cuint(value.len))
  LLVMAddAttributeAtIndex(fn, LLVMAttributeFunctionIndex, attr)

type
  LLVMMetadataRef* = distinct pointer

definePointerOps(LLVMMetadataRef)

proc LLVMMDStringInContext2*(C: LLVMContextRef; Str: cstring; SLen: csize_t): LLVMMetadataRef {.llvmImport.}
proc LLVMMDNodeInContext2*(C: LLVMContextRef; MDs: ptr LLVMMetadataRef; Count: csize_t): LLVMMetadataRef {.llvmImport.}
proc LLVMMetadataAsValue*(C: LLVMContextRef; MD: LLVMMetadataRef): LLVMValueRef {.llvmImport.}
proc LLVMValueAsMetadata*(Val: LLVMValueRef): LLVMMetadataRef {.llvmImport.}

proc LLVMGetMDKindIDInContext*(C: LLVMContextRef; Name: cstring; SLen: cuint): cuint {.llvmImport.}
proc LLVMGetMDKindID*(Name: cstring; SLen: cuint): cuint {.llvmImport.}

proc LLVMSetMetadata*(Val: LLVMValueRef; KindID: cuint; Node: LLVMValueRef) {.llvmImport.}
proc LLVMAddNamedMetadataOperand*(M: LLVMModuleRef; Name: cstring; Val: LLVMValueRef) {.llvmImport.}

proc LLVMAddAlias2*(M: LLVMModuleRef; ValueTy: LLVMTypeRef; AddrSpace: cuint; Aliasee: LLVMValueRef; Name: cstring): LLVMValueRef {.llvmImport.}
proc LLVMAliasGetAliasee*(Alias: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMAliasSetAliasee*(Alias: LLVMValueRef; Aliasee: LLVMValueRef) {.llvmImport.}

type
  LLVMMemoryBufferRef* = distinct pointer

definePointerOps(LLVMMemoryBufferRef)

proc LLVMCreateMemoryBufferWithMemoryRangeCopy*(InputData: cstring; InputDataLength: csize_t; BufferName: cstring): LLVMMemoryBufferRef {.llvmImport.}
proc LLVMGetBufferStart*(MemBuf: LLVMMemoryBufferRef): cstring {.llvmImport.}
proc LLVMGetBufferSize*(MemBuf: LLVMMemoryBufferRef): csize_t {.llvmImport.}
proc LLVMDisposeMemoryBuffer*(MemBuf: LLVMMemoryBufferRef) {.llvmImport.}

proc LLVMParseIRInContext2*(ContextRef: LLVMContextRef; MemBuf: LLVMMemoryBufferRef; OutM: var LLVMModuleRef; OutMessage: var cstring): LLVMBool {.llvmImport.}

proc parseIR*(ctx: LLVMContextRef; irText: string; name: string = "ir"): tuple[module: LLVMModuleRef, err: string] =
  ## Parses textual LLVM IR into a module. The memory buffer is consumed.
  let buf = LLVMCreateMemoryBufferWithMemoryRangeCopy(irText.cstring, csize_t(irText.len), name.cstring)
  if buf.isNil:
    return (LLVMModuleRef(nil), "failed to create memory buffer")

  var modd: LLVMModuleRef
  var errMsg: cstring
  let rc = LLVMParseIRInContext2(ctx, buf, modd, errMsg)
  
  if not errMsg.isNil:
    result.err = $errMsg
    LLVMDisposeMessage(errMsg)

  if rc == LLVMFalse:
    result.module = modd
  else:
    result.module = LLVMModuleRef(nil)

type
  JitModule* = object
    ## Wrapper for a module intended for JIT compilation.
    ## Automatically nullifies the module pointer once ownership is transferred to the JIT.
    raw*: LLVMModuleRef

proc initJitModule*(m: LLVMModuleRef): JitModule =
  JitModule(raw: m)

proc addModuleSafe*(jit: LLVMOrcLLJITRef, jm: var JitModule): string =
  ## Transfers ownership of the module to the LLJIT instance.
  ## The JitModule wrapper is nullified to prevent double-free or use-after-transfer.
  doAssert not jm.raw.isNil, "JitModule already transferred or nil"
  let m = jm.raw
  jm.raw = LLVMModuleRef(nil)
  result = addModule(jit, m)

proc createJITSafe*(jm: var JitModule, OptLevel: cuint = 0): tuple[ee: LLVMExecutionEngineRef, err: string] =
  ## Transfers ownership of the module to the MCJIT instance.
  ## The JitModule wrapper is nullified to prevent double-free or use-after-transfer.
  doAssert not jm.raw.isNil, "JitModule already transferred or nil"
  let m = jm.raw
  jm.raw = LLVMModuleRef(nil)
  result = createJIT(m, OptLevel)

type
  LLVMDIBuilderRef* = distinct pointer
  LLVMDbgRecordRef* = distinct pointer

  LLVMDWARFSourceLanguage* {.size: sizeof(cint).} = enum
    LLVMDWARFSourceLanguageC = 0,
    # Note: other values omitted for brevity, C is usually enough for basic tests

  LLVMDWARFEmissionKind* {.size: sizeof(cint).} = enum
    LLVMDWARFEmissionNone = 0,
    LLVMDWARFEmissionFull = 1,
    LLVMDWARFEmissionLineTablesOnly = 2

definePointerOps(LLVMDIBuilderRef)
definePointerOps(LLVMDbgRecordRef)

proc LLVMCreateDIBuilder*(M: LLVMModuleRef): LLVMDIBuilderRef {.llvmImport.}
proc LLVMDisposeDIBuilder*(Builder: LLVMDIBuilderRef) {.llvmImport.}

proc LLVMDIBuilderCreateFile*(Builder: LLVMDIBuilderRef; Filename: cstring; FilenameLen: csize_t; Directory: cstring; DirectoryLen: csize_t): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderCreateCompileUnit*(Builder: LLVMDIBuilderRef; Lang: LLVMDWARFSourceLanguage; FileRef: LLVMMetadataRef; Producer: cstring; ProducerLen: csize_t; isOptimized: LLVMBool; Flags: cstring; FlagsLen: csize_t; RuntimeVer: cuint; SplitName: cstring; SplitNameLen: csize_t; Kind: LLVMDWARFEmissionKind; DWOId: cuint; SplitDebugInlining: LLVMBool; DebugInfoForProfiling: LLVMBool; SysRoot: cstring; SysRootLen: csize_t; SDK: cstring; SDKLen: csize_t): LLVMMetadataRef {.llvmImport.}

proc LLVMDIBuilderCreateFunction*(Builder: LLVMDIBuilderRef; Scope: LLVMMetadataRef; Name: cstring; NameLen: csize_t; LinkageName: cstring; LinkageNameLen: csize_t; File: LLVMMetadataRef; LineNo: cuint; Ty: LLVMMetadataRef; IsLocalToUnit: LLVMBool; IsDefinition: LLVMBool; ScopeLine: cuint; Flags: cint; IsOptimized: LLVMBool): LLVMMetadataRef {.llvmImport.}

proc LLVMSetSubprogram*(Func: LLVMValueRef; SP: LLVMMetadataRef) {.llvmImport.}

proc LLVMDIBuilderCreateDebugLocation*(Ctx: LLVMContextRef; Line: cuint; Column: cuint; Scope: LLVMMetadataRef; InlinedAt: LLVMMetadataRef): LLVMMetadataRef {.llvmImport.}
proc LLVMSetCurrentDebugLocation2*(Builder: LLVMBuilderRef; Loc: LLVMMetadataRef) {.llvmImport.}

proc LLVMDIBuilderCreateBasicType*(Builder: LLVMDIBuilderRef; Name: cstring; NameLen: csize_t; SizeInBits: uint64; Encoding: cuint; Flags: cint): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderCreateSubroutineType*(Builder: LLVMDIBuilderRef; File: LLVMMetadataRef; ParameterTypes: ptr LLVMMetadataRef; NumParameterTypes: cuint; Flags: cint): LLVMMetadataRef {.llvmImport.}

proc LLVMDIBuilderCreateAutoVariable*(Builder: LLVMDIBuilderRef; Scope: LLVMMetadataRef; Name: cstring; NameLen: csize_t; File: LLVMMetadataRef; LineNo: cuint; Ty: LLVMMetadataRef; AlwaysPreserve: LLVMBool; Flags: cint; AlignInBits: cuint): LLVMMetadataRef {.llvmImport.}

proc LLVMDIBuilderInsertDeclareRecordAtEnd*(Builder: LLVMDIBuilderRef; Storage: LLVMValueRef; VarInfo: LLVMMetadataRef; Expr: LLVMMetadataRef; DebugLoc: LLVMMetadataRef; Block: LLVMBasicBlockRef): LLVMDbgRecordRef {.llvmImport.}
proc LLVMDIBuilderCreateExpression*(Builder: LLVMDIBuilderRef; Addr: ptr uint64; Length: csize_t): LLVMMetadataRef {.llvmImport.}

proc LLVMLinkModules2*(Dest: LLVMModuleRef; Src: LLVMModuleRef): LLVMBool {.llvmImport.}
  ## Links Src into Dest. On success, Dest owns Src's contents, and Src is destroyed.
  ## Returns 0 on success, 1 on error (e.g., duplicate symbols).

proc LLVMParseBitcodeInContext2*(ContextRef: LLVMContextRef; MemBuf: LLVMMemoryBufferRef; OutModule: var LLVMModuleRef): LLVMBool {.llvmImport.}
proc LLVMWriteBitcodeToFile*(M: LLVMModuleRef; Path: cstring): cint {.llvmImport.}
proc LLVMWriteBitcodeToMemoryBuffer*(M: LLVMModuleRef): LLVMMemoryBufferRef {.llvmImport.}

proc writeBitcodeToFile*(m: LLVMModuleRef; path: string): bool =
  ## Writes the module to a .bc file. Returns true on success.
  result = LLVMWriteBitcodeToFile(m, path.cstring) == 0

proc parseBitcode*(ctx: LLVMContextRef; buf: LLVMMemoryBufferRef): tuple[module: LLVMModuleRef, err: string] =
  ## Parses a bitcode memory buffer into a module. The buffer is consumed.
  var modd: LLVMModuleRef
  let rc = LLVMParseBitcodeInContext2(ctx, buf, modd)
  if rc == LLVMFalse:
    result.module = modd
  else:
    result.err = "failed to parse bitcode"

proc LLVMCreateMemoryBufferWithContentsOfFile*(Path: cstring; OutMemBuf: var LLVMMemoryBufferRef; OutMessage: var cstring): LLVMBool {.llvmImport.}

type
  LLVMBinaryRef* = distinct pointer
  LLVMSectionIteratorRef* = distinct pointer
  LLVMSymbolIteratorRef* = distinct pointer

definePointerOps(LLVMBinaryRef)
definePointerOps(LLVMSectionIteratorRef)
definePointerOps(LLVMSymbolIteratorRef)

proc LLVMCreateBinary*(MemBuf: LLVMMemoryBufferRef; Context: LLVMContextRef; ErrorMessage: var cstring): LLVMBinaryRef {.llvmImport.}
proc LLVMDisposeBinary*(BR: LLVMBinaryRef) {.llvmImport.}

proc LLVMGetSections*(BR: LLVMBinaryRef): LLVMSectionIteratorRef {.llvmImport.}
proc LLVMObjectFileIsSectionIteratorAtEnd*(BR: LLVMBinaryRef; SI: LLVMSectionIteratorRef): LLVMBool {.llvmImport.}
proc LLVMDisposeSectionIterator*(SI: LLVMSectionIteratorRef) {.llvmImport.}
proc LLVMMoveToNextSection*(SI: LLVMSectionIteratorRef) {.llvmImport.}
proc LLVMGetSectionName*(SI: LLVMSectionIteratorRef): cstring {.llvmImport.}
proc LLVMGetSectionAddress*(SI: LLVMSectionIteratorRef): uint64 {.llvmImport.}
proc LLVMGetSectionSize*(SI: LLVMSectionIteratorRef): uint64 {.llvmImport.}
proc LLVMGetSectionContents*(SI: LLVMSectionIteratorRef): cstring {.llvmImport.}

proc LLVMGetSymbols*(BR: LLVMBinaryRef): LLVMSymbolIteratorRef {.llvmImport.}
proc LLVMObjectFileIsSymbolIteratorAtEnd*(BR: LLVMBinaryRef; SI: LLVMSymbolIteratorRef): LLVMBool {.llvmImport.}
proc LLVMDisposeSymbolIterator*(SI: LLVMSymbolIteratorRef) {.llvmImport.}
proc LLVMMoveToNextSymbol*(SI: LLVMSymbolIteratorRef) {.llvmImport.}
proc LLVMGetSymbolName*(SI: LLVMSymbolIteratorRef): cstring {.llvmImport.}
proc LLVMGetSymbolAddress*(SI: LLVMSymbolIteratorRef): uint64 {.llvmImport.}
proc LLVMGetSymbolSize*(SI: LLVMSymbolIteratorRef): uint64 {.llvmImport.}

proc loadObjectFile*(ctx: LLVMContextRef; path: string): tuple[bin: LLVMBinaryRef, err: string] =
  ## Loads an object file from disk into an LLVMBinaryRef for inspection.
  var buf: LLVMMemoryBufferRef
  var errMsg: cstring
  if LLVMCreateMemoryBufferWithContentsOfFile(path.cstring, buf, errMsg) != LLVMFalse:
    if not errMsg.isNil:
      result.err = $errMsg
      LLVMDisposeMessage(errMsg)
    else:
      result.err = "failed to read file"
    return

  var createErr: cstring
  let br = LLVMCreateBinary(buf, ctx, createErr)
  if not createErr.isNil:
    result.err = $createErr
    LLVMDisposeMessage(createErr)
    result.bin = LLVMBinaryRef(nil)
  else:
    result.bin = br

proc LLVMObjectFileCopySectionIterator*(BR: LLVMBinaryRef): LLVMSectionIteratorRef {.llvmImport.}
proc LLVMObjectFileCopySymbolIterator*(BR: LLVMBinaryRef): LLVMSymbolIteratorRef {.llvmImport.}

type
  LLVMComdatRef* = distinct pointer

  LLVMComdatSelectionKind* {.size: sizeof(cint).} = enum
    LLVMAnyComdatSelectionKind = 0
    LLVMExactMatchComdatSelectionKind = 1
    LLVMLargestComdatSelectionKind = 2
    LLVMNoDuplicatesComdatSelectionKind = 3
    LLVMSameSizeComdatSelectionKind = 4

definePointerOps(LLVMComdatRef)

proc LLVMGetComdat*(V: LLVMValueRef): LLVMComdatRef {.llvmImport.}
proc LLVMSetComdat*(V: LLVMValueRef; C: LLVMComdatRef) {.llvmImport.}
proc LLVMGetComdatSelectionKind*(C: LLVMComdatRef): LLVMComdatSelectionKind {.llvmImport.}
proc LLVMSetComdatSelectionKind*(C: LLVMComdatRef; Kind: LLVMComdatSelectionKind) {.llvmImport.}

proc LLVMVerifyFunction*(Fn: LLVMValueRef; Action: LLVMVerifierFailureAction): LLVMBool {.llvmImport.}
proc LLVMGetNamedFunction*(M: LLVMModuleRef; Name: cstring): LLVMValueRef {.llvmImport.}

proc LLVMDIBuilderCreateLexicalBlock*(Builder: LLVMDIBuilderRef; Scope: LLVMMetadataRef; File: LLVMMetadataRef; Line: cuint; Column: cuint): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderFinalize*(Builder: LLVMDIBuilderRef) {.llvmImport.}

proc LLVMDIBuilderCreateSubrangeType*(Builder: LLVMDIBuilderRef; Scope: LLVMMetadataRef; Name: cstring; NameLen: csize_t; LineNo: cuint; File: LLVMMetadataRef; SizeInBits: uint64; AlignInBits: cuint; Flags: cint; BaseTy: LLVMMetadataRef; LowerBound: LLVMMetadataRef; UpperBound: LLVMMetadataRef; Stride: LLVMMetadataRef; Bias: LLVMMetadataRef): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderCreateArrayType*(Builder: LLVMDIBuilderRef; Size: uint64; AlignInBits: cuint; Ty: LLVMMetadataRef; Subscripts: ptr LLVMMetadataRef; NumSubscripts: cuint): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderCreatePointerType*(Builder: LLVMDIBuilderRef; PointeeTy: LLVMMetadataRef; SizeInBits: uint64; AlignInBits: cuint; AddressSpace: cuint; Name: cstring; NameLen: csize_t): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderCreateStructType*(Builder: LLVMDIBuilderRef; Scope: LLVMMetadataRef; Name: cstring; NameLen: csize_t; File: LLVMMetadataRef; LineNumber: cuint; SizeInBits: uint64; AlignInBits: cuint; Flags: cint; DerivedFrom: LLVMMetadataRef; Elements: ptr LLVMMetadataRef; NumElements: cuint; RunTimeLang: cuint; VTableHolder: LLVMMetadataRef; UniqueId: cstring; UniqueIdLen: csize_t): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderCreateMemberType*(Builder: LLVMDIBuilderRef; Scope: LLVMMetadataRef; Name: cstring; NameLen: csize_t; File: LLVMMetadataRef; LineNo: cuint; SizeInBits: uint64; AlignInBits: cuint; OffsetInBits: uint64; Flags: cint; Ty: LLVMMetadataRef): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderCreateGlobalVariableExpression*(Builder: LLVMDIBuilderRef; Scope: LLVMMetadataRef; Name: cstring; NameLen: csize_t; Linkage: cstring; LinkLen: csize_t; File: LLVMMetadataRef; LineNo: cuint; Ty: LLVMMetadataRef; LocalToUnit: LLVMBool; Expr: LLVMMetadataRef; Decl: LLVMMetadataRef; AlignInBits: cuint): LLVMMetadataRef {.llvmImport.}
proc LLVMDIBuilderCreateParameterVariable*(Builder: LLVMDIBuilderRef; Scope: LLVMMetadataRef; Name: cstring; NameLen: csize_t; ArgNo: cuint; File: LLVMMetadataRef; LineNo: cuint; Ty: LLVMMetadataRef; AlwaysPreserve: LLVMBool; Flags: cint): LLVMMetadataRef {.llvmImport.}

proc LLVMGlobalSetMetadata*(Global: LLVMValueRef; Kind: cuint; MD: LLVMMetadataRef) {.llvmImport.}

type
  LLVMDisasmContextRef* = distinct pointer

  LLVMDisassembler_Option* {.size: sizeof(cuint).} = enum
    LLVMDisassembler_Option_AsmPrinterVariant = 1
    LLVMDisassembler_Option_PrintImmHex = 2
    LLVMDisassembler_Option_UseMarkup = 4
    LLVMDisassembler_Option_PrintLatency = 8

definePointerOps(LLVMDisasmContextRef)

proc LLVMCreateDisasm*(TripleName: cstring; DisInfo: pointer; TagType: cint; GetOpInfo: pointer; SymbolLookUp: pointer): LLVMDisasmContextRef {.llvmImport.}
proc LLVMCreateDisasmCPU*(Triple: cstring; CPU: cstring; DisInfo: pointer; TagType: cint; GetOpInfo: pointer; SymbolLookUp: pointer): LLVMDisasmContextRef {.llvmImport.}
proc LLVMSetDisasmOptions*(DC: LLVMDisasmContextRef; Options: uint64): cint {.llvmImport.}
proc LLVMDisasmDispose*(DC: LLVMDisasmContextRef) {.llvmImport.}
proc LLVMDisasmInstruction*(DC: LLVMDisasmContextRef; Bytes: ptr uint8; BytesSize: uint64; PC: uint64; OutString: cstring; OutStringSize: csize_t): csize_t {.llvmImport.}

proc disassembleBytes*(triple: string; bytes: openArray[uint8]; pc: uint64 = 0; options: uint64 = 0): seq[string] =
  ## Disassembles a sequence of machine code bytes into assembly strings.
  ## Returns an empty sequence if the disassembler context cannot be created.
  let dc = LLVMCreateDisasm(triple.cstring, nil, 0, nil, nil)
  if dc.isNil:
    return
  defer: LLVMDisasmDispose(dc)

  if options != 0:
    discard LLVMSetDisasmOptions(dc, options)

  var pos = 0
  var buffer: array[1024, char]
  while pos < bytes.len:
    let size = LLVMDisasmInstruction(dc, cast[ptr uint8](unsafeAddr bytes[pos]), uint64(bytes.len - pos), pc + uint64(pos), cast[cstring](addr buffer[0]), csize_t(buffer.len))
    if size == 0:
      result.add("<invalid>")
      inc pos
    else:
      result.add($cast[cstring](addr buffer[0]))
      pos += int(size)

proc LLVMGetFirstFunction*(M: LLVMModuleRef): LLVMValueRef {.llvmImport.}
proc LLVMGetLastFunction*(M: LLVMModuleRef): LLVMValueRef {.llvmImport.}
proc LLVMGetNextFunction*(Fn: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMGetPreviousFunction*(Fn: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMCountFunctions*(M: LLVMModuleRef): cuint {.llvmImport.}

proc LLVMGetFirstGlobal*(M: LLVMModuleRef): LLVMValueRef {.llvmImport.}
proc LLVMGetLastGlobal*(M: LLVMModuleRef): LLVMValueRef {.llvmImport.}
proc LLVMGetNextGlobal*(GV: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMGetPreviousGlobal*(GV: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMCountGlobals*(M: LLVMModuleRef): cuint {.llvmImport.}

proc LLVMGetFirstBasicBlock*(Fn: LLVMValueRef): LLVMBasicBlockRef {.llvmImport.}
proc LLVMGetLastBasicBlock*(Fn: LLVMValueRef): LLVMBasicBlockRef {.llvmImport.}
proc LLVMGetNextBasicBlock*(BB: LLVMBasicBlockRef): LLVMBasicBlockRef {.llvmImport.}
proc LLVMGetPreviousBasicBlock*(BB: LLVMBasicBlockRef): LLVMBasicBlockRef {.llvmImport.}
proc LLVMCountBasicBlocks*(Fn: LLVMValueRef): cuint {.llvmImport.}

proc LLVMGetFirstInstruction*(BB: LLVMBasicBlockRef): LLVMValueRef {.llvmImport.}
proc LLVMGetLastInstruction*(BB: LLVMBasicBlockRef): LLVMValueRef {.llvmImport.}
proc LLVMGetNextInstruction*(Inst: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMGetPreviousInstruction*(Inst: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMCountParams*(Fn: LLVMValueRef): cuint {.llvmImport.}

proc LLVMGetValueName2*(Val: LLVMValueRef; Length: var csize_t): cstring {.llvmImport.}
proc LLVMGetBasicBlockName*(BB: LLVMBasicBlockRef): cstring {.llvmImport.}

proc LLVMTypeOf*(Val: LLVMValueRef): LLVMTypeRef {.llvmImport.}
proc LLVMGetAllocatedType*(Alloca: LLVMValueRef): LLVMTypeRef {.llvmImport.}

proc LLVMGetNumOperands*(Val: LLVMValueRef): cint {.llvmImport.}
proc LLVMGetOperand*(Val: LLVMValueRef; Index: cuint): LLVMValueRef {.llvmImport.}
proc LLVMSetOperand*(User: LLVMValueRef; Index: cuint; Val: LLVMValueRef) {.llvmImport.}

proc LLVMGetInstructionOpcode*(Inst: LLVMValueRef): cint {.llvmImport.}
proc LLVMGetBasicBlockTerminator*(BB: LLVMBasicBlockRef): LLVMValueRef {.llvmImport.}
proc LLVMGetEntryBasicBlock*(Fn: LLVMValueRef): LLVMBasicBlockRef {.llvmImport.}

proc LLVMGetNumSuccessors*(Term: LLVMValueRef): cuint {.llvmImport.}
proc LLVMGetSuccessor*(Term: LLVMValueRef; i: cuint): LLVMBasicBlockRef {.llvmImport.}
proc LLVMSetSuccessor*(Term: LLVMValueRef; i: cuint; Block: LLVMBasicBlockRef) {.llvmImport.}

proc LLVMGetCondition*(Branch: LLVMValueRef): LLVMValueRef {.llvmImport.}
proc LLVMSetCondition*(Branch: LLVMValueRef; Cond: LLVMValueRef) {.llvmImport.}

proc LLVMIsDeclaration*(Global: LLVMValueRef): LLVMBool {.llvmImport.}
proc LLVMInstructionEraseFromParent*(Inst: LLVMValueRef) {.llvmImport.}
proc LLVMDeleteInstruction*(Inst: LLVMValueRef) {.llvmImport.}

proc LLVMGetCurrentDebugLocation2*(Builder: LLVMBuilderRef): LLVMMetadataRef {.llvmImport.}
proc LLVMGetMetadata*(Val: LLVMValueRef; KindID: cuint): LLVMValueRef {.llvmImport.}
proc LLVMInstructionGetDebugLoc*(Inst: LLVMValueRef): LLVMMetadataRef {.llvmImport.}
proc LLVMInstructionGetAllMetadataOtherThanDebugLoc*(Inst: LLVMValueRef; MDs: var LLVMValueRef; NumMDs: var cuint) {.llvmImport.}

type
  LLVMTargetDataRef* = distinct pointer
  LLVMByteOrdering* {.size: sizeof(cint).} = enum
    LLVMBigEndian = 0
    LLVMLittleEndian = 1

definePointerOps(LLVMTargetDataRef)

proc LLVMCreateTargetData*(StringRep: cstring): LLVMTargetDataRef {.llvmImport.}
proc LLVMCreateTargetDataLayout*(T: LLVMTargetMachineRef): LLVMTargetDataRef {.llvmImport.}
proc LLVMDisposeTargetData*(TD: LLVMTargetDataRef) {.llvmImport.}
proc LLVMCopyStringRepOfTargetData*(TD: LLVMTargetDataRef): cstring {.llvmImport.}
proc LLVMGetModuleDataLayout*(M: LLVMModuleRef): LLVMTargetDataRef {.llvmImport.}
proc LLVMSetModuleDataLayout*(M: LLVMModuleRef; DL: LLVMTargetDataRef) {.llvmImport.}
proc LLVMByteOrder*(TD: LLVMTargetDataRef): LLVMByteOrdering {.llvmImport.}
proc LLVMPointerSize*(TD: LLVMTargetDataRef): cuint {.llvmImport.}
proc LLVMPointerSizeForAS*(TD: LLVMTargetDataRef; AS: cuint): cuint {.llvmImport.}
proc LLVMIntPtrTypeInContext*(C: LLVMContextRef; TD: LLVMTargetDataRef): LLVMTypeRef {.llvmImport.}
proc LLVMIntPtrTypeForASInContext*(C: LLVMContextRef; TD: LLVMTargetDataRef; AS: cuint): LLVMTypeRef {.llvmImport.}

proc LLVMSizeOfTypeInBits*(TD: LLVMTargetDataRef; Ty: LLVMTypeRef): uint64 {.llvmImport.}
proc LLVMStoreSizeOfType*(TD: LLVMTargetDataRef; Ty: LLVMTypeRef): uint64 {.llvmImport.}
proc LLVMABISizeOfType*(TD: LLVMTargetDataRef; Ty: LLVMTypeRef): uint64 {.llvmImport.}
proc LLVMABIAlignmentOfType*(TD: LLVMTargetDataRef; Ty: LLVMTypeRef): cuint {.llvmImport.}
proc LLVMCallFrameAlignmentOfType*(TD: LLVMTargetDataRef; Ty: LLVMTypeRef): cuint {.llvmImport.}
proc LLVMPreferredAlignmentOfType*(TD: LLVMTargetDataRef; Ty: LLVMTypeRef): cuint {.llvmImport.}
proc LLVMPreferredAlignmentOfGlobal*(TD: LLVMTargetDataRef; GlobalVar: LLVMValueRef): cuint {.llvmImport.}
proc LLVMElementAtOffset*(TD: LLVMTargetDataRef; StructTy: LLVMTypeRef; Offset: uint64): cuint {.llvmImport.}
proc LLVMOffsetOfElement*(TD: LLVMTargetDataRef; StructTy: LLVMTypeRef; Element: cuint): uint64 {.llvmImport.}

proc LLVMOrcLLJITGetDataLayoutStr*(J: LLVMOrcLLJITRef): cstring {.llvmImport.}
proc LLVMOrcCreateNewThreadSafeContextFromLLVMContext*(Ctx: LLVMContextRef): LLVMOrcThreadSafeContextRef {.llvmImport.}
  ## Takes ownership of Ctx. After this call, do NOT dispose Ctx with
  ## LLVMContextDispose: the ThreadSafeContext owns it.

proc LLVMOrcLLJITAddObjectFile*(J: LLVMOrcLLJITRef; JD: LLVMOrcJITDylibRef; ObjBuffer: LLVMMemoryBufferRef): LLVMErrorRef {.llvmImport.}
proc LLVMOrcLLJITEnableDebugSupport*(J: LLVMOrcLLJITRef): LLVMErrorRef {.llvmImport.}

proc LLVMGetInsertBlock*(Builder: LLVMBuilderRef): LLVMBasicBlockRef {.llvmImport.}
proc LLVMDeleteFunction*(Fn: LLVMValueRef) {.llvmImport.}