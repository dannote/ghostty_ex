const beam = @import("beam");
const root = @import("root");
const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    if (builtin.os.tag == .macos)
        @cInclude("util.h")
    else
        @cInclude("pty.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("sys/ioctl.h");
    @cInclude("signal.h");
    @cInclude("sys/wait.h");
    @cInclude("poll.h");
    @cInclude("stdlib.h");
    @cInclude("errno.h");
});

const PtyData = struct {
    master_fd: c_int,
    child_pid: c.pid_t,
    owner_pid: beam.pid,
    closed: std.atomic.Value(bool),
};

pub const PtyResource = beam.Resource(PtyData, root, .{
    .Callbacks = PtyCallbacks,
});

pub const PtyCallbacks = struct {
    pub fn dtor(data: *PtyData) void {
        do_close(data);
    }
};

fn do_close(data: anytype) void {
    const closed_ptr = @constCast(&data.closed);
    if (closed_ptr.swap(true, .acq_rel)) return;
    _ = c.close(data.master_fd);
    _ = c.kill(data.child_pid, c.SIGHUP);
    _ = c.waitpid(data.child_pid, null, c.WNOHANG);
}

fn get_errno() c_int {
    if (comptime builtin.os.tag == .macos)
        return c.__error().*
    else
        return c.__errno_location().*;
}

fn reader_loop(master_fd: c_int, owner: beam.pid, closed: *std.atomic.Value(bool)) void {
    var buf: [4096]u8 = undefined;

    while (!closed.load(.acquire)) {
        var pfd = [_]c.struct_pollfd{.{
            .fd = master_fd,
            .events = c.POLLIN,
            .revents = 0,
        }};

        const poll_ret = c.poll(&pfd, 1, 100);
        if (poll_ret <= 0) continue;
        if (pfd[0].revents & c.POLLIN == 0) continue;

        const n = c.read(master_fd, &buf, buf.len);
        if (n <= 0) {
            if (n == 0 or (n < 0 and get_errno() == c.EIO)) {
                if (!closed.load(.acquire)) {
                    const env = beam.alloc_env();
                    beam.send(owner, .{ .exit, @as(i32, 0) }, .{ .env = env }) catch {};
                    beam.free_env(env);
                }
                return;
            }
            continue;
        }

        const slice = buf[0..@intCast(n)];
        const env = beam.alloc_env();
        beam.send(owner, .{ .data, beam.make(slice, .{ .env = env }) }, .{ .env = env }) catch {};
        beam.free_env(env);
    }
}

pub fn nif_pty_open(cmd: []const u8, _args_unused: beam.term, cols: u16, rows: u16, owner: beam.pid) !PtyResource {
    _ = _args_unused;

    var ws: c.struct_winsize = .{
        .ws_col = cols,
        .ws_row = rows,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    var master_fd: c_int = undefined;
    const pid = c.forkpty(&master_fd, null, null, &ws);
    if (pid < 0) return error.forkpty_failed;

    if (pid == 0) {
        _ = c.setenv("TERM", "xterm-256color", 1);

        var cmd_buf: [4096]u8 = undefined;
        const n = @min(cmd.len, cmd_buf.len - 1);
        @memcpy(cmd_buf[0..n], cmd[0..n]);
        cmd_buf[n] = 0;

        const cmd_z: [*:0]const u8 = @ptrCast(&cmd_buf);
        var argv = [_:null]?[*:0]const u8{ "sh", "-c", cmd_z, null };
        _ = c.execvp("/bin/sh", @ptrCast(&argv));
        c._exit(127);
    }

    const flags = c.fcntl(master_fd, c.F_GETFL);
    _ = c.fcntl(master_fd, c.F_SETFL, flags | c.O_NONBLOCK);

    const res = try PtyResource.create(.{
        .master_fd = master_fd,
        .child_pid = pid,
        .owner_pid = owner,
        .closed = std.atomic.Value(bool).init(false),
    }, .{});

    const data = res.unpack();
    const closed_ptr = @constCast(&data.closed);
    _ = std.Thread.spawn(.{}, reader_loop, .{ master_fd, owner, closed_ptr }) catch
        return error.thread_spawn_failed;

    return res;
}

pub fn nif_pty_write(res: PtyResource, data: []const u8) void {
    const pty = res.unpack();
    if (pty.closed.load(.acquire)) return;

    var off: usize = 0;
    while (off < data.len) {
        const n = c.write(pty.master_fd, data.ptr + off, data.len - off);
        if (n > 0) {
            off += @intCast(n);
        } else if (n < 0) {
            if (get_errno() == c.EINTR) continue;
            break;
        }
    }
}

pub fn nif_pty_resize(res: PtyResource, cols: u16, rows: u16) void {
    const pty = res.unpack();
    if (pty.closed.load(.acquire)) return;

    var ws: c.struct_winsize = .{
        .ws_col = cols,
        .ws_row = rows,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    _ = c.ioctl(pty.master_fd, c.TIOCSWINSZ, &ws);
}

pub fn nif_pty_close(res: PtyResource) void {
    do_close(res.unpack());
}
