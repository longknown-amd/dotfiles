#!/usr/bin/env python3
# Copyright (c) Advanced Micro Devices, Inc., or its affiliates.
# SPDX-License-Identifier: MIT
"""
bench_kernel_map.py -- convert between hipMicroBench *bench test-case names*
(e.g. `Atomic_Add_fp32_All_Global`, what -bench_filter / -list_bench use) and
*kernel names* in three forms:

  1. demangled  : hip_bench::kentry<2, hip_bench::AtomicKernel<...>>(...)   (rocprof view)
  2. mangled    : _ZN9hip_bench6kentryILi2ENS_12AtomicKernelI...EEEEvDpT1_  (device symbol)
  3. impl       : AtomicKernel<hip_bench::AtomicAdd, float, ...>            (KernelImpl type)

How the map is built (see SKILL.md for the full decision tree):

  * KERNEL SIDE (always offline, exact): read the host ELF with `llvm-nm`, take every
    `__device_stub__kentry<...>` symbol, demangle with `llvm-cxxfilt`, and derive the real
    *device* symbol by the verified rename  `__device_stub__kentry` -> `kentry`
    (`_ZN9hip_bench21__device_stub__kentry...` -> `_ZN9hip_bench6kentry...`).

  * BENCH-NAME SIDE: joined to the kernel side on the (normalized) KernelImpl type via
    one of two sources --
      - AUTHORITATIVE (recommended): a benchmark run with -enable_json_output=true emits
        `kernel_name` + `kernel_entry.kernel_impl_type` (see include/metadata.hpp). Exact for
        every category, zero re-implementation. Needs the Docker/GPU env once.
      - OFFLINE RECONSTRUCT (no GPU, best-effort): re-derive the bench name from the demangled
        KernelImpl type, mirroring each GetTestName(). Reliable for plain-typed kernels; the
        host demangler renders some exotic types (fp8/bf8) ambiguously, so reconstruction is
        cross-checked against an authoritative name list (-list_bench / result JSON) and any
        mismatch/unresolved entry is reported, not hidden.

Subcommands:
  build-map  --binary B [--from-json J ...] [--names N ...] [--arch A] [--out M]
  to-kernel  NAME            [--form demangled|mangled|impl|all] [--map M]
  to-bench   SYMBOL_OR_IMPL  [--map M]
  search     REGEX           [--side bench|kernel] [--map M]
  dump       [--map M]       # print the whole map as a table

The map is cached as JSON next to the binary by default:
  <build-dir>/bench_kernel_map.<arch>.json
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

# --------------------------------------------------------------------------------------
# tool discovery
# --------------------------------------------------------------------------------------
def _find_tool(names):
    rocm_bin = [os.path.join("/opt/rocm/llvm/bin", n) for n in names]
    for cand in rocm_bin + names:
        p = shutil.which(cand) if not os.path.isabs(cand) else (cand if os.path.exists(cand) else None)
        if p:
            return p
    return None

LLVM_NM = _find_tool(["llvm-nm", "nm"])
CXXFILT = _find_tool(["llvm-cxxfilt", "c++filt"])


def _die(msg):
    sys.stderr.write("error: " + msg + "\n")
    sys.exit(1)


# --------------------------------------------------------------------------------------
# naming dictionaries (mirror the C++ *::name members / helpers; see SKILL.md table)
# --------------------------------------------------------------------------------------
# demangled C++ type token -> bench display name (DataTypeTraits<T>::name)
TYPE_NAME = {
    "float": "fp32", "double": "fp64", "_Float16": "fp16",
    "int": "i32", "unsigned int": "u32", "unsigned long": "u64",
    "long": "i64", "short": "i16", "unsigned short": "u16",
    "signed char": "i8", "char": "i8", "unsigned char": "u8",
    "hip_bench::fp16_t": "fp16", "hip_bench::bf16_t": "bf16",
    "__hip_bfloat16": "bf16", "__bf16": "bf16",
    "hip_bench::fp8_t": "fp8", "hip_bench::bf8_t": "bf8",
    "hip_bench::f8f6f4_t": "f8f6f4_t",
    "hip_bench::f8f6f4_fp8_t": "mx_fp8", "hip_bench::f8f6f4_bf8_t": "mx_bf8",
    "hip_bench::f8f6f4_fp6_t": "mx_fp6", "hip_bench::f8f6f4_bf6_t": "mx_bf6",
    "hip_bench::f8f6f4_fp4_t": "mx_fp4",
    "hip_bench::scale_e8m0_t": "e8m0", "hip_bench::scale_e5m3_t": "e5m3",
    "hip_bench::scale_e4m3_t": "e4m3",
    "hip_bench::pk_int4_t": "i4", "hip_bench::pk_fp4_t": "fp4",
}
ATOMIC_OP = {"AtomicAdd": "Add", "AtomicCAS": "CAS", "AtomicExch": "Exch",
             "AtomicMin": "Min", "AtomicMax": "Max"}
CONTENTION = {"ContentionAll": "All", "ContentionBlock": "Block", "ContentionWarp": "Warp",
              "ContentionNone": "None", "ContentionXcc": "Xcc", "ContentionShared": "Shared"}
MEMTARGET = {"MemGlobal": "Global", "MemLDS": "LDS", "MemBuffer": "Buffer",
             "MemGlobalSys": "GlobalSys", "MemRemote": "Remote", "MemHost": "Host"}
SCHEDULE = {0: "Interwave", 1: "Intrawave", 2: "Wavegroup"}
CVT_ACT = {0: "none", 1: "relu"}
SBA_MODE = {0: "uscale", 1: "uscale_bias", 2: "scale_bias"}
SBA_ACT = {0: "none", 1: "relu", 2: "hardtanh"}


def _strip_ns(tok):
    return tok.split("::")[-1] if "::" in tok else tok


def _type_name(tok, vec=1):
    base = TYPE_NAME.get(tok) or TYPE_NAME.get(_strip_ns(tok)) or _strip_ns(tok)
    return base + ("x%d" % vec if vec and vec > 1 else "")


def _op_name(tok):
    # base ops (Add/Mul/Mad/Dot/Sub/Sin/Cos/...) carry name == identifier
    return _strip_ns(tok)


# --------------------------------------------------------------------------------------
# top-level template-argument splitter
# --------------------------------------------------------------------------------------
def split_args(s):
    """split `a, b<c, d>, e` on top-level commas -> ['a','b<c, d>','e']"""
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in "<([":
            depth += 1
        elif ch in ">)]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if cur:
        out.append("".join(cur).strip())
    return out


def parse_impl(impl):
    """`hip_bench::AtomicKernel<a, b<x>, c>` -> ('AtomicKernel', ['a','b<x>','c'])"""
    m = re.match(r"(?:hip_bench::)?([A-Za-z0-9_]+)<(.*)>\s*$", impl.strip())
    if not m:
        return None, []
    return m.group(1), split_args(m.group(2))


def _int(tok):
    m = re.match(r"-?\d+", tok.strip())
    return int(m.group(0)) if m else None


def _uint(tok):  # `32u` / `1u`
    return _int(tok)


def _enum_val(tok):
    # `(hip_bench::CoexecScheduleType)1` / `(signed char)0`
    m = re.search(r"\)\s*(-?\d+)", tok)
    return int(m.group(1)) if m else _int(tok)


def _bool(tok):
    return tok.strip() == "true"


# --------------------------------------------------------------------------------------
# per-category bench-name reconstruction (offline, best-effort)
# args = template args of KernelImpl, trailing UnrollSize (e.g. 32u) dropped where noted
# --------------------------------------------------------------------------------------
def _tile_op_name(arg):
    cls, a = parse_impl(arg)
    if cls == "WcnnTileFmaConfig" or cls is None and "Fma" in arg:
        return "fma"
    if cls == "WcnnTileCvtConfig":
        act = CVT_ACT.get(_enum_val(a[0]), "?")
        scale = _enum_val(a[1])
        clamp = "clamp" if _bool(a[2]) else "noclamp"
        return "cvt_%s_scaleexp%s_%s" % (act, scale, clamp)
    if cls == "WcnnTileSbaConfig":
        mode = SBA_MODE.get(_enum_val(a[0]), "?")  # note: src puts Mode first in get_name
        act = SBA_ACT.get(_enum_val(a[1]), "?")
        return "sba_%s_%s_" % (mode, act)  # trailing _ matches C++ get_name()
    return _strip_ns(arg)


def _wcnn_shape(H, W, F, Iters, Dil):
    s = "%dx%d_F%d" % (H, W, F)
    s += ("_I%d" % Iters) if F == 1 else ("_Dil%d" % Dil)
    return s


def rc_atomic(a):  # <Op,Type,Cont,Mem,Unroll>
    return "Atomic_%s_%s_%s_%s" % (ATOMIC_OP.get(_strip_ns(a[0]), _strip_ns(a[0])),
                                   _type_name(a[1]), CONTENTION.get(_strip_ns(a[2]), _strip_ns(a[2])),
                                   MEMTARGET.get(_strip_ns(a[3]), _strip_ns(a[3])))


def rc_trans(a):  # <Op,Type,VectorSize,Unroll>
    return "Trans_%s_%s" % (_op_name(a[0]), _type_name(a[1], _uint(a[2])))


def rc_valu(a):  # AluKernel<Op,PrecType,VectorSize,Unroll>; C==A==Prec
    op = _strip_ns(a[0])
    m = re.match(r"ValuOp<\s*Mad\s*,\s*DppRowShare<\s*(-?\d+)\s*>", a[0].replace("hip_bench::", ""))
    if m:
        op = "DppMad_RowShare" + m.group(1)
    vec = _uint(a[2])
    tn = _type_name(a[1], vec)
    return "Valu_%s_C_%s_A_%s" % (op, tn, tn)


def rc_mma(a):  # <M,N,K,TypeC,TypeA,TypeB,Unroll>
    return "Mma_%dx%dx%d_C_%s_A_%s_B_%s" % (_int(a[0]), _int(a[1]), _int(a[2]),
                                            _type_name(a[3]), _type_name(a[4]), _type_name(a[5]))


def rc_mxmma(a):  # <M,N,K,Scale16,TypeA,TypeB,ScaleA,ScaleB,TypeC?,Unroll>
    s16 = "_S16" if _bool(a[3]) else ""
    return "MxMma_%dx%dx%d%s_A_%s_%s_B_%s_%s" % (
        _int(a[0]), _int(a[1]), _int(a[2]), s16,
        _type_name(a[4]), _type_name(a[6]), _type_name(a[5]), _type_name(a[7]))


def rc_wcnn(a):  # <H,W,Data,Weight,Acc,FilterSize,Iters,Dilation,Unroll>
    H, W = _int(a[0]), _int(a[1])
    F, It, Dil = _int(a[5]), _int(a[6]), _int(a[7])
    return "Wcnn_%s_C_%s_D_%s_W_%s" % (_wcnn_shape(H, W, F, It, Dil),
                                       _type_name(a[4]), _type_name(a[2]), _type_name(a[3]))


def rc_wcnn_tile(a):  # <H,W,Data,Acc,TileConfig,Unroll>
    return "WcnnTile_%s_%dx%d_C_%s_D_%s" % (_tile_op_name(a[4]), _int(a[0]), _int(a[1]),
                                            _type_name(a[3]), _type_name(a[2]))


def rc_co_alu_alu(a):  # <Op0,Op1,Prec0,Prec1,Vec0,Vec1,Sched,Unroll>
    return "CoAluAlu_%s_%s_%s_%s_%s" % (
        _op_name(a[0]), _type_name(a[2], _uint(a[4])),
        _op_name(a[1]), _type_name(a[3], _uint(a[5])),
        SCHEDULE.get(_enum_val(a[6]), "?"))


def rc_co_mma_alu(a):  # <M,N,K,TypeC,TypeA,TypeB,AluOp,AluType,AluVec,Sched,Unroll>
    return "CoMmaAlu_%dx%dx%d_C_%s_A_%s_B_%s_%s_%s_%s" % (
        _int(a[0]), _int(a[1]), _int(a[2]),
        _type_name(a[3]), _type_name(a[4]), _type_name(a[5]),
        _op_name(a[6]), _type_name(a[7], _uint(a[8])), SCHEDULE.get(_enum_val(a[9]), "?"))


def rc_co_mxmma_alu(a):  # <M,N,K,Scale16,TypeA,TypeB,ScaleA,ScaleB,TypeC,AluOp,AluType,AluVec,Sched,Unroll>
    s16 = "_S16" if _bool(a[3]) else ""
    return "CoMxMmaAlu_%dx%dx%d%s_A_%s_%s_B_%s_%s_%s_%s_%s" % (
        _int(a[0]), _int(a[1]), _int(a[2]), s16,
        _type_name(a[4]), _type_name(a[6]), _type_name(a[5]), _type_name(a[7]),
        _op_name(a[9]), _type_name(a[10], _uint(a[11])), SCHEDULE.get(_enum_val(a[12]), "?"))


def rc_co_wcnn_alu(a):  # <H,W,Data,Weight,Acc,FilterSize,Iters/Dil...,AluOp,AluType,AluVec,Sched,Dilation?,Unroll>
    H, W = _int(a[0]), _int(a[1])
    F = _int(a[5])
    It = _int(a[6])
    Dil = _int(a[-2])  # dilation sits just before Unroll
    base = "CoWcnnAlu_%s" % _wcnn_shape(H, W, F, It, Dil)
    # alu op/type/sched are the 4 args before the trailing (dilation, unroll)
    aluop, alutype, aluvec, sched = a[-6], a[-5], a[-4], a[-3]
    return "%s_C_%s_D_%s_W_%s_%s_%s_%s" % (
        base, _type_name(a[4]), _type_name(a[2]), _type_name(a[3]),
        _op_name(aluop), _type_name(alutype, _uint(aluvec)), SCHEDULE.get(_enum_val(sched), "?"))


def rc_co_wcnn_wcnntile(a):  # <H,W,Data,Weight,Acc,FilterSize,Iters/Dil,TileConfig,Sched,Dilation?,Unroll>
    H, W = _int(a[0]), _int(a[1])
    F = _int(a[5])
    It = _int(a[6])
    Dil = _int(a[-2])
    tile = _tile_op_name(a[-4])
    sched = a[-3]
    return "CoWcnnWcnnTile_%s_C_%s_D_%s_W_%s_%s%s" % (
        _wcnn_shape(H, W, F, It, Dil), _type_name(a[4]), _type_name(a[2]), _type_name(a[3]),
        tile, SCHEDULE.get(_enum_val(sched), "?"))


RECONSTRUCT = {
    "AtomicKernel": rc_atomic, "TransKernel": rc_trans, "AluKernel": rc_valu,
    "MMaKernel": rc_mma, "MxMmaKernel": rc_mxmma, "WcnnKernel": rc_wcnn,
    "WcnnTileKernel": rc_wcnn_tile, "CoexecAluAluKernel": rc_co_alu_alu,
    "CoexecMmaAluKernel": rc_co_mma_alu, "CoexecMxMmaAluKernel": rc_co_mxmma_alu,
    "CoexecWcnnAluKernel": rc_co_wcnn_alu, "CoexecWcnnWcnnTileKernel": rc_co_wcnn_wcnntile,
}


def reconstruct_bench_name(impl):
    cls, args = parse_impl(impl)
    fn = RECONSTRUCT.get(cls)
    if not fn:
        return None
    try:
        return fn(args)
    except Exception:
        return None


# --------------------------------------------------------------------------------------
# Itanium-subset mangled-symbol parser.
#
# The stock llvm-cxxfilt/c++filt is LOSSY for AMD vendor float types: it renders
# `DF16b` (__bf16 / bf16_t) by failing outright (returns the symbol unmangled), and
# drops `DB<n>_` / `DU<n>_` (_BitInt). Trusting the demangled text therefore (a) silently
# DROPS those kernels and (b) cannot tell fp16 from bf16. So for *type identity* we parse
# the mangled symbol directly -- it is unambiguous -- and emit tokens in the exact shape
# split_args() would have produced from a (correct) demangle, so the rc_* reconstructors
# are reused verbatim. The demangler is used only for the human-readable display string,
# and we synthesize that too when it fails.
# --------------------------------------------------------------------------------------
# single/short builtin <type> codes -> demangle-equivalent token
_BUILTIN = {
    "v": "void", "b": "bool", "c": "char", "a": "signed char", "h": "unsigned char",
    "s": "short", "t": "unsigned short", "i": "int", "j": "unsigned int",
    "l": "long", "m": "unsigned long", "x": "long long", "y": "unsigned long long",
    "n": "__int128", "o": "unsigned __int128", "f": "float", "d": "double",
    "e": "long double", "w": "wchar_t", "Di": "char32_t", "Ds": "char16_t",
    "Du": "char8_t", "Dh": "_Float16", "Dn": "decltype(nullptr)",
}


class _MangleParser:
    """Parses the subset of Itanium mangling emitted by hip_bench kentry symbols."""

    def __init__(self, s):
        self.s = s
        self.i = 0
        self.subs = []  # substitution table (we only need readable text)

    def _num(self):
        j = self.i
        while self.i < len(self.s) and self.s[self.i].isdigit():
            self.i += 1
        return int(self.s[j:self.i])

    def _source_name(self):
        n = self._num()
        name = self.s[self.i:self.i + n]
        self.i += n
        return name

    def parse_type(self):
        s, i = self.s, self.i
        # vendor float / _BitInt forms
        if s.startswith("DF", i):
            m = re.match(r"DF(\d+)(_|b)", s[i:])
            if m:
                self.i += m.end()
                tok = "__bf16" if m.group(2) == "b" else "_Float16"
                self.subs.append(tok)
                return tok
        if re.match(r"D[BU]\d+_", s[i:]):
            m = re.match(r"D([BU])(\d+)_", s[i:])
            self.i += m.end()
            # hip_bench: fp8_t = _BitInt(8), bf8_t = unsigned _BitInt(8)
            if m.group(2) == "8":
                tok = "hip_bench::bf8_t" if m.group(1) == "U" else "hip_bench::fp8_t"
                self.subs.append(tok)
                return tok
            kind = "unsigned _BitInt" if m.group(1) == "U" else "_BitInt"
            return "%s(%s)" % (kind, m.group(2))
        # multi-char builtins (Di/Ds/Du/Dh/Dn)
        if s[i] == "D" and s[i:i + 2] in _BUILTIN:
            self.i += 2
            return _BUILTIN[s[i:i + 2]]
        # single-char builtins
        if s[i] in _BUILTIN and s[i] not in "DLNSI":
            self.i += 1
            return _BUILTIN[s[i]]
        # nested name (class/struct, possibly templated)
        if s[i] == "N":
            return self._nested()
        # substitution reference
        if s[i] == "S":
            return self._sub_ref()
        # pointer/ref/cv qualifiers we don't expect in impl args; best-effort skip
        if s[i] in "PRrKVO":
            self.i += 1
            return self.parse_type()
        raise ValueError("unhandled type at %d: %r" % (i, s[i:i + 12]))

    def _sub_ref(self):
        # S_ , S0_ , S1_ ... -> we return a placeholder readable name
        m = re.match(r"S(\d*)_", self.s[self.i:])
        if not m:
            raise ValueError("bad substitution")
        self.i += m.end()
        idx = 0 if m.group(1) == "" else int(m.group(1), 36) + 1
        if idx < len(self.subs):
            return self.subs[idx]
        return "hip_bench"  # S_ is the first sub = the hip_bench namespace

    def _nested(self):
        assert self.s[self.i] == "N"
        self.i += 1
        comps = []
        targs = None
        while True:
            c = self.s[self.i]
            if c == "E":
                self.i += 1
                break
            if c == "I":  # template-args for the last component
                targs = self._template_args()
                continue
            if c == "S":
                comps.append(self._sub_ref())
                continue
            comps.append(self._source_name())
            self.subs.append("::".join(comps))
        name = "::".join(c for c in comps if c not in ("hip_bench",) or len(comps) == 1)
        full = "::".join(comps)
        if targs is not None:
            base = full
            full = base + "<" + ", ".join(targs) + ">"
        # normalise to a leading hip_bench:: for our types (matches demangle output)
        if not full.startswith("hip_bench") and comps and comps[0] != "hip_bench":
            pass
        return full

    def _template_args(self):
        assert self.s[self.i] == "I"
        self.i += 1
        args = []
        while self.s[self.i] != "E":
            if self.s[self.i] == "L":
                args.append(self._literal())
            else:
                args.append(self.parse_type())
        self.i += 1  # consume E
        return args

    def _literal(self):
        assert self.s[self.i] == "L"
        self.i += 1
        # literal type then value then E
        if self.s[self.i] == "i":
            self.i += 1
            val = self._signed()
            self._expect_E()
            return str(val)
        if self.s[self.i] == "j" or self.s[self.i] == "m":
            self.i += 1
            val = self._signed()
            self._expect_E()
            return "%du" % val
        if self.s[self.i] == "b":
            self.i += 1
            val = self._signed()
            self._expect_E()
            return "true" if val else "false"
        if self.s[self.i] == "a":  # signed char
            self.i += 1
            val = self._signed()
            self._expect_E()
            return "(signed char)%d" % val
        # enum / other named type literal: L <type> <value> E
        ty = self.parse_type()
        val = self._signed()
        self._expect_E()
        return "(%s)%d" % (ty, val)

    def _signed(self):
        neg = False
        if self.i < len(self.s) and self.s[self.i] == "n":
            neg = True
            self.i += 1
        v = self._num()
        return -v if neg else v

    def _expect_E(self):
        if self.s[self.i] == "E":
            self.i += 1


def parse_kentry_mangled(dev_mangled):
    """device kentry symbol -> {min_block_per_cu, impl} parsed from the mangling.
       Returns None if it is not a kentry symbol."""
    m = re.match(r"_ZN9hip_bench6kentryILi(\d+)E", dev_mangled)
    if not m:
        return None
    minblk = int(m.group(1))
    p = _MangleParser(dev_mangled)
    p.i = m.end()          # positioned right after `Li<n>E`
    p.subs = ["hip_bench"]  # S_ -> hip_bench
    try:
        impl = p.parse_type()  # the KernelImpl type (2nd template arg of kentry)
    except Exception:
        return None
    impl = re.sub(r"^hip_bench::", "", impl)
    return {"min_block_per_cu": minblk, "impl": impl}


def synth_demangled(minblk, impl):
    full = impl if impl.startswith("hip_bench::") else "hip_bench::" + impl
    return ("void hip_bench::kentry<%d, %s, %s::KernelArgs>(%s::KernelArgs)"
            % (minblk, full, full, full))


# --------------------------------------------------------------------------------------
# ELF -> kernel-forms table
# --------------------------------------------------------------------------------------
STUB_MANGLED_RE = re.compile(r"_ZN9hip_bench21__device_stub__kentry")


def _run(cmd, stdin=None):
    p = subprocess.run(cmd, input=stdin, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, universal_newlines=True)
    return p.stdout


def extract_kernel_forms(binary):
    """Return list of dicts: mangled (device), demangled, impl, min_block_per_cu."""
    if not LLVM_NM or not CXXFILT:
        _die("need llvm-nm and llvm-cxxfilt (install rocm-llvm or llvm).")
    out = _run([LLVM_NM, binary])
    stub_mangled = []
    for line in out.splitlines():
        parts = line.split()
        if not parts:
            continue
        sym = parts[-1]
        if STUB_MANGLED_RE.search(sym):
            stub_mangled.append(sym)
    stub_mangled = sorted(set(stub_mangled))
    if not stub_mangled:
        _die("no __device_stub__kentry symbols in %s (not a hipMicroBench binary?)" % binary)

    # device symbol = stub symbol with `21__device_stub__kentry` -> `6kentry`
    dev_mangled = [s.replace("9hip_bench21__device_stub__kentry", "9hip_bench6kentry", 1)
                   for s in stub_mangled]
    demangled = _run([CXXFILT], stdin="\n".join(dev_mangled) + "\n").splitlines()

    entries, dropped = [], 0
    for mang, dem in zip(dev_mangled, demangled):
        # type identity comes from the mangling (unambiguous); never trust the lossy
        # demangler for it -- that silently drops bf16/_BitInt kernels.
        rec = parse_kentry_mangled(mang)
        if rec is None:
            dropped += 1
            continue
        dem = dem.strip()
        rec["demangled"] = (dem if dem.startswith("void hip_bench::kentry")
                            else synth_demangled(rec["min_block_per_cu"], rec["impl"]))
        rec["mangled"] = mang
        entries.append(rec)
    if dropped:
        sys.stderr.write("warning: %d kentry symbol(s) in %s could not be parsed\n"
                         % (dropped, os.path.basename(binary)))
    return entries


# --------------------------------------------------------------------------------------
# bench-name sources
# --------------------------------------------------------------------------------------
def _norm_impl(impl):
    """normalize an impl type string for joining: drop hip_bench::, collapse spaces, 'u' suffix."""
    s = impl.strip()
    s = re.sub(r"^hip_bench::", "", s)
    s = s.replace("hip_bench::", "")
    s = re.sub(r"\s+", "", s)
    return s


def load_json_pairs(paths):
    """From benchmark result/run JSON(s) -> {norm_impl: bench_name} using kernel_entry metadata.
       Accepts either a top-level list/obj or the suite's trailing-comma append format."""
    pairs = {}
    for path in paths:
        txt = open(path).read()
        objs = _loads_lenient(txt)
        for o in objs:
            name = o.get("kernel_name")
            ke = o.get("kernel_entry") or {}
            impl_m = ke.get("kernel_impl_type")
            if name and impl_m:
                dem = _run([CXXFILT, "-t"], stdin=impl_m + "\n").strip() if CXXFILT else impl_m
                pairs[_norm_impl(dem)] = name
    return pairs


def load_name_list(paths):
    """authoritative bench-name set from -list_bench JSON or result JSON kernel_names."""
    names = set()
    for path in paths:
        txt = open(path).read()
        try:
            doc = json.loads(txt)
            if isinstance(doc, dict) and "benchmarks" in doc:
                names.update(doc["benchmarks"])
                continue
        except Exception:
            pass
        for o in _loads_lenient(txt):
            if isinstance(o, dict) and o.get("kernel_name"):
                names.add(o["kernel_name"])
    return names


def _loads_lenient(txt):
    txt = txt.strip()
    try:
        doc = json.loads(txt)
        return doc if isinstance(doc, list) else [doc]
    except Exception:
        pass
    # suite append format: `{...},\n{...},\n`  -> wrap into an array
    try:
        return json.loads("[" + txt.rstrip().rstrip(",") + "]")
    except Exception:
        return []


# --------------------------------------------------------------------------------------
# build-map
# --------------------------------------------------------------------------------------
def default_map_path(binary, arch):
    return os.path.join(os.path.dirname(os.path.abspath(binary)),
                        "bench_kernel_map.%s.json" % (arch or "unknown"))


def guess_arch(binary):
    m = re.search(r"gfx\d+[a-z]*", os.path.abspath(binary))
    return m.group(0) if m else None


def cmd_build_map(ns):
    binaries = ns.binary if isinstance(ns.binary, list) else [ns.binary]
    arch = ns.arch or guess_arch(binaries[0])

    # aggregate across all binaries, dedup on the device mangled symbol
    seen, entries = set(), []
    for b in binaries:
        for e in extract_kernel_forms(b):
            if e["mangled"] in seen:
                continue
            seen.add(e["mangled"])
            e["binary"] = os.path.basename(b)
            entries.append(e)

    json_pairs = load_json_pairs(ns.from_json) if ns.from_json else {}
    authoritative_names = load_name_list(ns.names) if ns.names else set()

    report = {"json": 0, "reconstruct": 0, "unresolved": 0, "validated": 0, "mismatch": []}
    for e in entries:
        nimpl = _norm_impl(e["impl"])
        bn, by = None, None
        if nimpl in json_pairs:
            bn, by = json_pairs[nimpl], "json"
        else:
            rc = reconstruct_bench_name(e["impl"])
            if rc is not None:
                bn, by = rc, "reconstruct"
        e["bench_name"] = bn
        e["bench_resolved_by"] = by
        if by == "json":
            report["json"] += 1
        elif by == "reconstruct":
            report["reconstruct"] += 1
            if authoritative_names:
                if bn in authoritative_names:
                    report["validated"] += 1
                else:
                    report["mismatch"].append(bn)
        else:
            report["unresolved"] += 1

    out = ns.out or default_map_path(binaries[0], arch)
    mapdoc = {"arch": arch, "binaries": [os.path.basename(b) for b in binaries],
              "count": len(entries), "entries": entries}
    with open(out, "w") as f:
        json.dump(mapdoc, f, indent=1)

    sys.stderr.write(
        "built %d kernels -> %s\n  by json:%d  by reconstruct:%d  unresolved:%d\n"
        % (len(entries), out, report["json"], report["reconstruct"], report["unresolved"]))
    if authoritative_names and report["reconstruct"]:
        sys.stderr.write("  reconstruct vs reference names: confirmed:%d  not-in-reference:%d\n"
                         % (report["validated"], len(report["mismatch"])))
        sys.stderr.write("    (a -list_bench reference is the full set; a filtered result JSON is\n"
                         "     partial, so 'not-in-reference' there just means 'not exercised',\n"
                         "     not a reconstruction error.)\n")
        for mm in report["mismatch"][:10]:
            sys.stderr.write("    not-in-reference: %s\n" % mm)
    if report["unresolved"]:
        sys.stderr.write("  note: run with --from-json <results.json> (from a -enable_json_output "
                         "run) to authoritatively resolve all bench names.\n")
    return 0


# --------------------------------------------------------------------------------------
# converters
# --------------------------------------------------------------------------------------
def load_map(ns):
    path = ns.map
    if not path:
        if getattr(ns, "binary", None):
            path = default_map_path(ns.binary, ns.arch or guess_arch(ns.binary))
        else:
            _die("no --map given and no --binary to derive default path. run build-map first.")
    if not os.path.exists(path):
        _die("map not found: %s  (run: build-map --binary <bin>)" % path)
    return json.load(open(path))


def cmd_to_kernel(ns):
    doc = load_map(ns)
    hits = [e for e in doc["entries"] if e.get("bench_name") == ns.name]
    if not hits:
        # allow regex / case-insensitive convenience
        hits = [e for e in doc["entries"]
                if e.get("bench_name") and re.fullmatch(ns.name, e["bench_name"])]
    if not hits:
        _die("no kernel for bench name: %s" % ns.name)
    for e in hits:
        if ns.form == "all":
            print("bench    : %s" % e["bench_name"])
            print("demangled: %s" % e["demangled"])
            print("mangled  : %s" % e["mangled"])
            print("impl     : %s" % e["impl"])
            print("min_block_per_cu: %s   resolved_by: %s" %
                  (e["min_block_per_cu"], e.get("bench_resolved_by")))
            print("")
        else:
            print(e[{"demangled": "demangled", "mangled": "mangled", "impl": "impl"}[ns.form]])
    return 0


def cmd_to_bench(ns):
    doc = load_map(ns)
    q = ns.symbol.strip()
    # mangled device symbol -> exact
    by_mangled = {e["mangled"]: e for e in doc["entries"]}
    if q in by_mangled:
        return _print_bench(by_mangled[q])
    # mangled but is the host stub form
    qd = q.replace("9hip_bench21__device_stub__kentry", "9hip_bench6kentry", 1)
    if qd in by_mangled:
        return _print_bench(by_mangled[qd])
    # raw mangled we haven't indexed: demangle then fall through to text match
    if q.startswith("_Z") and CXXFILT:
        q = _run([CXXFILT], stdin=q + "\n").strip()
    qn = re.sub(r"\s+", "", q).replace("hip_bench::", "")
    # match against demangled kentry or impl (normalized, substring-tolerant)
    for e in doc["entries"]:
        dem_n = re.sub(r"\s+", "", e["demangled"]).replace("hip_bench::", "")
        impl_n = _norm_impl(e["impl"])
        if qn == dem_n or qn == impl_n or impl_n in qn or qn in dem_n:
            return _print_bench(e)
    _die("no bench name matched: %s" % ns.symbol)


def _print_bench(e):
    if not e.get("bench_name"):
        sys.stderr.write("matched kernel but bench name UNRESOLVED "
                         "(rebuild map --from-json to resolve)\n  impl: %s\n" % e["impl"])
        return 2
    print(e["bench_name"])
    return 0


def cmd_search(ns):
    doc = load_map(ns)
    rx = re.compile(ns.regex)
    for e in doc["entries"]:
        bench = e.get("bench_name") or "<unresolved>"
        hay = bench if ns.side == "bench" else (e["demangled"] + " " + e["mangled"] + " " + e["impl"])
        if rx.search(hay):
            print("%-60s  ->  %s" % (bench, e["impl"]))
    return 0


def cmd_dump(ns):
    doc = load_map(ns)
    print("# arch=%s binaries=%s count=%d" %
          (doc.get("arch"), ",".join(doc.get("binaries", [])), doc.get("count")))
    for e in doc["entries"]:
        print("%-62s | mbpc=%s | %s" %
              (e.get("bench_name") or "<unresolved>", e["min_block_per_cu"], e["impl"]))
    return 0


# --------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build-map", help="build/refresh the cached name<->kernel map")
    b.add_argument("--binary", required=True, nargs="+",
                   help="one or more bench binaries (alu atomic coexec ...) merged into one map")
    b.add_argument("--from-json", nargs="*", default=[],
                   help="result/run JSON(s) with kernel_entry metadata (authoritative)")
    b.add_argument("--names", nargs="*", default=[],
                   help="authoritative bench-name list(s): -list_bench JSON or result JSON")
    b.add_argument("--arch", default=None)
    b.add_argument("--out", default=None)
    b.set_defaults(func=cmd_build_map)

    for name, helptxt in [("to-kernel", "bench name -> kernel name"),
                          ("to-bench", "kernel name/symbol -> bench name"),
                          ("search", "regex over the map"),
                          ("dump", "print the whole map")]:
        p = sub.add_parser(name, help=helptxt)
        p.add_argument("--map", default=None)
        p.add_argument("--binary", default=None, help="derive default map path from this binary")
        p.add_argument("--arch", default=None)
        if name == "to-kernel":
            p.add_argument("name")
            p.add_argument("--form", choices=["demangled", "mangled", "impl", "all"], default="all")
            p.set_defaults(func=cmd_to_kernel)
        elif name == "to-bench":
            p.add_argument("symbol")
            p.set_defaults(func=cmd_to_bench)
        elif name == "search":
            p.add_argument("regex")
            p.add_argument("--side", choices=["bench", "kernel"], default="bench")
            p.set_defaults(func=cmd_search)
        else:
            p.set_defaults(func=cmd_dump)

    ns = ap.parse_args()
    sys.exit(ns.func(ns))


if __name__ == "__main__":
    main()
