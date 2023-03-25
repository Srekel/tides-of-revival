const std = @import("std");
const websocket = @import("websocket");
const Allocator = std.mem.Allocator;
const Client = websocket.Client;
const Message = websocket.Message;
const Handshake = websocket.Handshake;
const ws_client = websocket.client;
const net = std.net;
const Loop = std.event.Loop;

const IdLocal = @import("../variant.zig").IdLocal;

const DebugServerHandlerCallbackFn = *const fn (data: []const u8, allocator: std.mem.Allocator, ctx: *anyopaque) []const u8;
const DebugServerHandler = struct {
    callbackFn: DebugServerHandlerCallbackFn,
    ctx: *anyopaque,
};

pub const DebugServer = struct {
    active: bool = false,
    port: u16,
    allocator: std.mem.Allocator,
    handlers: std.AutoArrayHashMap(u64, DebugServerHandler),

    pub fn create(port: u16, allocator: std.mem.Allocator) DebugServer {
        var self = DebugServer{
            .active = false,
            .port = port,
            .allocator = allocator,
            .handlers = std.AutoArrayHashMap(u64, DebugServerHandler).init(allocator),
        };
        return self;
    }

    pub fn registerHandler(self: *DebugServer, id: IdLocal, callbackFn: DebugServerHandlerCallbackFn, ctx: *anyopaque) void {
        self.handlers.put(id.hash, .{
            .callbackFn = callbackFn,
            .ctx = ctx,
        }) catch unreachable;
    }

    pub fn run(self: *DebugServer) void {
        @atomicStore(bool, &self.active, true, std.builtin.AtomicOrder.SeqCst);
        const thread_config = .{};
        var thread_args: ThreadContextDebugServer = .{
            .debug_server = self,
        };
        var thread = std.Thread.spawn(thread_config, threadDebugServerListen, .{thread_args}) catch unreachable;
        thread.setName("debug_server") catch {};
    }

    pub fn stop(self: *DebugServer) void {
        @atomicStore(bool, &self.active, false, std.builtin.AtomicOrder.SeqCst);
    }

    pub fn listen(self: *DebugServer) !void {
        const address = "127.0.0.1";
        const path = "/";
        const max_request_size = 1024;
        const buffer_size = 8192;
        const max_size = 8192;

        var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = general_purpose_allocator.allocator();

        var server = net.StreamServer.init(.{ .reuse_address = true });
        defer server.deinit();

        try server.listen(net.Address.parseIp(address, self.port) catch unreachable);
        std.log.info("listening at {}", .{server.listen_address});
        const client_config = ws_client.Config{
            .path = path,
            .max_size = max_size,
            .buffer_size = buffer_size,
            .max_request_size = max_request_size,
        };

        while (true) {
            if (server.accept()) |conn| {
                const args = .{
                    Handler,
                    Handler.Context{ .debug_server = self },
                    conn,
                    client_config,
                    allocator,
                };
                if (comptime std.io.is_async) {
                    try Loop.instance.?.runDetached(allocator, ws_client.handle, args);
                } else {
                    const t = try std.Thread.spawn(.{}, ws_client.handle, args);
                    t.detach();
                }
            } else |err| {
                std.log.err("failed to accept connection {}", .{err});
            }
        }
    }

    pub fn handleMessage(self: *DebugServer, data: []const u8, allocator: std.mem.Allocator) []const u8 {
        // _ = self;
        // _ = data;
        return self.handlers.get(IdLocal.init("wpm").hash).?.callbackFn(data, allocator, self.handlers.get(IdLocal.init("wpm").hash).?.ctx);
    }
};

const Handler = struct {
    const Context = struct {
        debug_server: *DebugServer,
    };

    client: *Client,
    context: Context,

    pub fn init(_: []const u8, _: []const u8, client: *Client, context: Context) !Handler {
        return Handler{
            .client = client,
            .context = context,
        };
    }

    pub fn handle(self: *Handler, message: Message) !void {
        const data = message.data;
        switch (message.type) {
            .binary => {
                unreachable;
                // try self.client.write(data),
            },
            .text => {
                if (std.unicode.utf8ValidateSlice(data)) {
                    var arena_state = std.heap.ArenaAllocator.init(self.context.debug_server.allocator);
                    defer arena_state.deinit();
                    const arena = arena_state.allocator();

                    const output = self.context.debug_server.handleMessage(data, arena);
                    // try self.client.writeText("hello");
                    try self.client.writeText(output);
                } else {
                    self.client.close();
                }
            },
            else => unreachable,
        }
    }

    pub fn close(_: *Handler) void {}
};

const ThreadContextDebugServer = struct {
    debug_server: *DebugServer,
};

fn threadDebugServerListen(ctx: ThreadContextDebugServer) void {
    ctx.debug_server.listen() catch unreachable;
}
