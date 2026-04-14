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
    _ = c.kill(data.child_pid, c.SIGHUP);
    _ = c.close(data.master_fd);
    _ = c.waitpid(data.child_pid, null, c.WNOHANG);
}

fn get_errno() c_int {
    if (comptime builtin.os.tag == .macos)
        return c.__error().*
    else
        return c.__errno_location().*;
}

fn is_would_block(errno: c_int) bool {
    return errno == c.EAGAIN or errno == c.EWOULDBLOCK;
}

fn wait_for_fd(fd: c_int, events: c_short, timeout_ms: c_int) c_short {
    var pfd: c.struct_pollfd = .{
        .fd = fd,
        .events = events,
        .revents = 0,
    };

    while (true) {
        const rc = c.poll(&pfd, 1, timeout_ms);

        if (rc > 0) return pfd.revents;
        if (rc == 0) return 0;
        if (get_errno() == c.EINTR) continue;
        return 0;
    }
}

fn send_exit_and_wait(child_pid: c.pid_t, closed: *std.atomic.Value(bool), owner: beam.pid) void {
    var status: c_int = 0;
    _ = c.waitpid(child_pid, &status, 0);

    if (!closed.load(.acquire)) {
        const exit_status: i32 = if (c.WIFEXITED(status)) c.WEXITSTATUS(status) else 0;
        const env = beam.alloc_env();
        beam.send(owner, .{ .exit, exit_status }, .{ .env = env }) catch {};
        beam.free_env(env);
    }
}

fn reader_loop(master_fd: c_int, child_pid: c.pid_t, owner: beam.pid, closed: *std.atomic.Value(bool)) void {
    var buf: [4096]u8 = undefined;

    while (!closed.load(.acquire)) {
        const revents = wait_for_fd(master_fd, c.POLLIN | c.POLLHUP | c.POLLERR, 100);
        if (revents == 0) continue;

        if (revents & c.POLLIN != 0) {
            while (!closed.load(.acquire)) {
                const n = c.read(master_fd, &buf, buf.len);

                if (n > 0) {
                    const slice = buf[0..@intCast(n)];
                    const env = beam.alloc_env();
                    beam.send(owner, .{ .data, beam.make(slice, .{ .env = env }) }, .{ .env = env }) catch {};
                    beam.free_env(env);
                    continue;
                }

                if (n < 0) {
                    const errno = get_errno();
                    if (errno == c.EINTR) continue;
                    if (is_would_block(errno)) break;
                    return;
                }

                // n == 0: EOF
                send_exit_and_wait(child_pid, closed, owner);
                return;
            }
        }

        if (revents & (c.POLLHUP | c.POLLERR) != 0 and revents & c.POLLIN == 0) {
            send_exit_and_wait(child_pid, closed, owner);
            return;
        }
    }
}

pub fn nif_pty_open(cmd: []const u8, args: []const []const u8, cols: u16, rows: u16, owner: beam.pid) !PtyResource {

    var ws: c.struct_winsize = .{
        .ws_col = cols,
        .ws_row = rows,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    // SAFETY: initialized by forkpty below
    var master_fd: c_int = undefined;
    const pid = c.forkpty(&master_fd, null, null, &ws);
    if (pid < 0) return error.forkpty_failed;

    if (pid == 0) {
        _ = c.setenv("TERM", "xterm-256color", 1);

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const cmd_z = try allocator.dupeZ(u8, cmd);
        const argv = try allocator.alloc(?[*:0]u8, args.len + 2);
        argv[0] = @ptrCast(cmd_z.ptr);

        for (args, 0..) |arg, i| {
            const arg_z = try allocator.dupeZ(u8, arg);
            argv[i + 1] = @ptrCast(arg_z.ptr);
        }

        argv[args.len + 1] = null;

        _ = c.execvp(@ptrCast(cmd_z.ptr), @ptrCast(argv.ptr));
        c._exit(127);
    }

    const flags = c.fcntl(master_fd, c.F_GETFL);
    _ = c.fcntl(master_fd, c.F_SETFL, flags | @as(c_int, c.O_NONBLOCK));

    const res = try PtyResource.create(.{
        .master_fd = master_fd,
        .child_pid = pid,
        .owner_pid = owner,
        .closed = std.atomic.Value(bool).init(false),
    }, .{});

    const data = res.unpack();
    const closed_ptr = @constCast(&data.closed);
    const thread = std.Thread.spawn(.{}, reader_loop, .{ master_fd, pid, owner, closed_ptr }) catch
        return error.thread_spawn_failed;
    thread.detach();

    return res;
}

pub fn nif_pty_write(res: PtyResource, data: []const u8) void {
    const pty = res.unpack();
    if (pty.closed.load(.acquire)) return;

    var off: usize = 0;
    while (off < data.len and !pty.closed.load(.acquire)) {
        const n = c.write(pty.master_fd, data.ptr + off, data.len - off);

        if (n > 0) {
            off += @intCast(n);
            continue;
        }

        if (n < 0) {
            const errno = get_errno();
            if (errno == c.EINTR) continue;

            if (is_would_block(errno)) {
                _ = wait_for_fd(pty.master_fd, c.POLLOUT, 100);
                continue;
            }
        }

        break;
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
    _ = c.kill(pty.child_pid, c.SIGWINCH);
}

pub fn nif_pty_close(res: PtyResource) void {
    do_close(res.unpack());
}
