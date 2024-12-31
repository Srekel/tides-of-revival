const std = @import("std");
const websocket = @import("websocket");
const Allocator = std.mem.Allocator;
const Conn = websocket.Conn;
const Message = websocket.Message;
const Handshake = websocket.Handshake;
const ws_client = websocket.client;
const net = std.net;
const Loop = std.event.Loop;

const IdLocal = @import("../core/core.zig").IdLocal;

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
        const self = DebugServer{
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
        _ = self;
        // @atomicStore(bool, &self.active, true, std.builtin.AtomicOrder.seq_cst);
        // const thread_config = .{};
        // const thread_args: ThreadContextDebugServer = .{
        //     .debug_server = self,
        // };
        // var thread = std.Thread.spawn(thread_config, threadDebugServerListen, .{thread_args}) catch unreachable;
        // thread.setName("debug_server") catch {};
    }

    pub fn stop(self: *DebugServer) void {
        @atomicStore(bool, &self.active, false, std.builtin.AtomicOrder.seq_cst);
    }

    pub fn listen(self: *DebugServer) !void {
        _ = self;
        // const listen_config = websocket.Config.Server{
        //     .port = self.port,
        //     .address = "127.0.0.1",
        //     .buffer_size = 4096,
        //     .max_size = 65536,
        //     .handshake_max_size = 1024,
        // };

        // var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
        // const allocator = general_purpose_allocator.allocator();

        // var context = Handler.Context{ .debug_server = self };

        // websocket.listen(
        //     Handler,
        //     allocator,
        //     &context,
        //     listen_config,
        // ) catch |err| {
        //     std.log.debug("listen error {}", .{err});
        // };
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

    conn: *websocket.Conn,
    // client: *Client,
    context: *Context,

    pub fn init(h: Handshake, conn: *Conn, context: *Context) !Handler {
        _ = h;
        return Handler{
            .conn = conn,
            .context = context,
        };
    }

    pub fn handle(self: *Handler, message: Message) !void {
        const data = message.data;
        switch (message.type) {
            .binary => {
                unreachable;
                // try self.conn.writeBin(data),
            },
            .text => {
                if (std.unicode.utf8ValidateSlice(data)) {
                    var arena_state = std.heap.ArenaAllocator.init(self.context.debug_server.allocator);
                    defer arena_state.deinit();
                    const arena = arena_state.allocator();

                    const output = self.context.debug_server.handleMessage(data, arena);
                    // try self.conn.write("hello");
                    try self.conn.write(output);
                } else {
                    self.conn.close();
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
