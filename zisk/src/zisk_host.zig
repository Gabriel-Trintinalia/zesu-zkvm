/// ZisK host object: satisfies all extern symbol references in zesu.rv64im.o
///
/// Exports:
///   zkvm_log / zkvm_exit             — runtime (UART + ecall)
///   sys_read                         — Rust std stdin stub
///
/// Symbols provided by libziskos_staticlib.a at link time (NOT exported here):
///   read_input / write_output        — zkvm-standards io-interface
///   zkvm_* accelerators              — all circuit-backed implementations (ZisK 1.0.0-alpha)
///   zkvm_init / zkvm_deinit / _start — entrypoint and lifecycle
/// Zisk zkVM UART — byte writes here appear in ziskemu console output
const ZISK_UART: *volatile u8 = @ptrFromInt(0xa0000200);

// ── Runtime ───────────────────────────────────────────────────────────────────

/// Logging sink used by zesu.o's std_options.logFn (src/zkvm/root.zig).
export fn zkvm_log(level: u8, msg_ptr: [*]const u8, msg_len: usize) void {
    _ = level;
    for (msg_ptr[0..msg_len]) |byte| {
        ZISK_UART.* = byte;
    }
    ZISK_UART.* = '\n';
}

/// Halt/exit: Linux syscall 93 (exit) via ecall.
export fn zkvm_exit(code: i32) noreturn {
    asm volatile (
        \\ ecall
        \\ .align 4
        :
        : [code] "{a0}" (code),
          [syscall] "{a7}" (@as(u32, 93)),
        : .{ .memory = true });
    while (true) {
        asm volatile ("wfi");
    }
}

/// Rust std's zkvm Stdin calls this — no stdin in zkVM, return EOF.
export fn sys_read(fd: i32, buf: [*]u8, count: usize) isize {
    _ = fd;
    _ = buf;
    _ = count;
    return 0;
}

// ── zkvm-standards U256 accelerator shim (ZisK substitution) ──────────────────
//
// zesu calls the zkvm-standards `zkvm_u256_*` interface (zkvm_u256.h). ZisK's
// libziskos exposes its native 256-bit routines under different names taking
// 4×u64 little-endian limbs. This object provides the standard symbols by
// forwarding to those routines; since `zkvm_u256` (== zkvm_bytes_32, 32 bytes)
// carries zesu's native little-endian word, the conversion is a zero-cost pointer
// reinterpret (no byte-order swap). When ZisK ships the standard interface
// natively, this shim is dropped and the guest links it directly.
//
// Pointers are 8-byte aligned by the caller (zesu passes a *u256).
const U256 = [32]u8;

extern fn reduce_mod256_c(a: *const [4]u64, m: *const [4]u64, result: *[4]u64) void;
extern fn add_mod256_c(a: *const [4]u64, b: *const [4]u64, m: *const [4]u64, result: *[4]u64) void;
extern fn mul_mod256_c(a: *const [4]u64, b: *const [4]u64, m: *const [4]u64, result: *[4]u64) void;
extern fn checked_div256_c(a: *const [4]u64, b: *const [4]u64, result: *[4]u64) u8;

inline fn limbs(p: *const U256) *const [4]u64 {
    return @ptrCast(@alignCast(p));
}
inline fn limbsMut(p: *U256) *[4]u64 {
    return @ptrCast(@alignCast(p));
}

export fn zkvm_u256_mod(a: *const U256, b: *const U256, remainder: *U256) i32 {
    reduce_mod256_c(limbs(a), limbs(b), limbsMut(remainder));
    return 0;
}

export fn zkvm_u256_addmod(a: *const U256, b: *const U256, n: *const U256, result: *U256) i32 {
    add_mod256_c(limbs(a), limbs(b), limbs(n), limbsMut(result));
    return 0;
}

export fn zkvm_u256_mulmod(a: *const U256, b: *const U256, n: *const U256, result: *U256) i32 {
    mul_mod256_c(limbs(a), limbs(b), limbs(n), limbsMut(result));
    return 0;
}

export fn zkvm_u256_div(a: *const U256, b: *const U256, quotient: *U256) i32 {
    _ = checked_div256_c(limbs(a), limbs(b), limbsMut(quotient));
    return 0;
}
