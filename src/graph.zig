const std = @import("std");
const v = @import("variant.zig");

pub const IdLocal = struct {
    str: [191]u8 = .{0} ** 191,
    strlen: u8 = 0,
    hash: u64 = 0,

    pub fn init(id: []const u8) IdLocal {
        var res: IdLocal = undefined;
        res.set(id);
        return res;
    }

    pub fn set(id: *IdLocal, str: []const u8) void {
        if (str[0] == 0) {
            id.*.clear();
            return;
        }
        id.strlen = @intCast(u8, str.len);
        id.hash = std.hash.Wyhash.hash(0, str);
        std.mem.copy(u8, id.str[0..id.str.len], str);
    }

    pub fn toString(self: IdLocal) []const u8 {
        return self.str[0..self.strlen];
    }

    pub fn debugPrint(self: IdLocal) void {
        std.debug.print("id: {s}:{}:{}\n", .{ self.str[0..self.strlen], self.strlen, self.hash });
    }

    pub fn clear(self: *IdLocal) void {
        self.hash = 0;
        self.strlen = 0;
        std.mem.set(u8, &self.str, 0);
    }

    pub fn isUnset(self: IdLocal) bool {
        return self.hash == 0;
    }

    pub fn eql(self: IdLocal, other: IdLocal) bool {
        return self.hash == other.hash;
    }

    pub fn eqlStr(self: IdLocal, other: []const u8) bool {
        // todo memcmp
        const hash = std.hash.Wyhash(0, other);
        return self.hash == hash;
    }
};

pub const Graph = struct {
    nodes: std.ArrayList(Node),

    pub fn connect(self: *Graph) void {
        std.debug.print("Initializing {} nodes...\n", .{self.nodes.items.len});
        for (self.nodes.items) |*node1| {
            node1.init();
        }

        std.debug.print("Connecting {} nodes...\n", .{self.nodes.items.len});
        for (self.nodes.items) |*node1, ni1| {
            std.debug.print("{} n1: {s}\n", .{ ni1, node1.name.toString() });
            for (node1.inputs) |*input1| {
                if (input1.template == null) {
                    break;
                }
                if (input1.reference.isUnset()) {
                    continue;
                }

                std.debug.print("..i1:{s}, ref:{s}\n", .{ input1.template.?.name.toString(), input1.reference.toString() });
                for (self.nodes.items) |*node2, ni2| {
                    if (ni1 == ni2) {
                        continue;
                    }

                    // var outputs2 = ;
                    for (node2.outputs) |*output2| {
                        if (output2.template == null) {
                            break;
                        }
                        if (output2.reference.isUnset()) {
                            continue;
                        }

                        std.debug.print("....n2:{s}, o2:{s}\n", .{ node2.name.toString(), output2.template.?.name.toString() });
                        if (!output2.reference.eql(input1.reference)) {
                            continue;
                        }

                        std.debug.print("....Connected {s}:{s} to {s}:{s}\n", .{ node2.name.toString(), output2.template.?.name.toString(), node1.name.toString(), input1.template.?.name.toString() });
                        input1.source = output2;
                    }
                }
            }
        }
    }

    fn nodeLessThan(context: void, a: Node, b: Node) bool {
        _ = context;
        return a.order < b.order;
    }

    pub fn debugPrint(self: Graph) void {
        std.debug.print("Graph:\n", .{});
        for (self.nodes.items) |node| {
            node.debugPrint();
        }
    }

    pub fn run(self: *Graph, allocator: std.mem.Allocator) void {
        // var nodeQueue = std.PriorityQueue(*Node, void, nodeLessThan).init(allocator, {});
        // for (self.nodes.items) |*node| {
        //     nodeQueue.add(node) catch unreachable;
        // }
        // for (nodeQueue.items) |item| {
        //     item.name.debugPrint();
        // }

        self.debugPrint();
        // std.sort.sort(Node, self.nodes.items, {}, nodeLessThan);
        // self.debugPrint();
        _ = self;
        _ = allocator;

        var allFinished = false;
        std.debug.print("Running graph...\n", .{});
        while (!allFinished) {
            allFinished = true;
            for (self.nodes.items) |*node| {
                for (node.outputs) |*output| {
                    // std.debug.print("Node {s} had output {s} with reference {s}\n", .{ node.name.toString(), output.template.?.name.toString(), output.reference.toString() });
                    if (output.template == null) {
                        break;
                    }
                    if (!output.reference.isUnset()) {
                        std.debug.print("Node {s} had output {s} with reference {s}\n", .{ node.name.toString(), output.template.?.name.toString(), output.reference.toString() });
                        continue;
                    }
                    const res = node.template.func.func.*(node, output, &.{});
                    std.debug.print(".. outputted {}\n", .{res.success});
                }
                // if (!lol) {
                //     // else {
                //     // Node didn't have any outputs leading to other nodes
                //     std.debug.print("Running {s}\n", .{node.name.toString()});
                //     for (node.outputs) |*output2| {
                //         _ = output2;
                //         if (output2.template == null) {
                //             break;
                //         }
                //         const res = node.template.func.func.*(node, output2);
                //         // switch (res) {
                //         //     NodeFuncResult.success => |value| {
                //         //         std.debug.print(".. outputted {}\n", .{value});
                //         //     },

                //         // }
                //         std.debug.print(".. outputted {}\n", .{res.success});
                //         if (res != .success) {
                //             allFinished = false;
                //         }
                //     }
                // }
            }
        }
    }
};

// ███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗
// ████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝
// ██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗
// ██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║
// ██║ ╚████║╚██████╔╝██████╔╝███████╗███████║
// ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝

pub const NodeTemplate = struct {
    name: IdLocal,
    version: u32,
    // input: std.ArrayList(NodeInputTemplate),
    // output: std.ArrayList(NodeOutputTemplate),
    func: NodeFuncTemplate,
};

// pub const NodeFuncTemplate2 = struct {
//     name: IdLocal,
//     version: u32,
//     func: *const NodeFunc,
//     inputs: std.BoundedArray(NodeInputTemplate, 16),
//     outputs: [16]NodeOutputTemplate,
// };

pub const NodeFuncTemplate = struct {
    name: IdLocal,
    version: u32,
    func: *const NodeFunc,
    inputs: [16]NodeInputTemplate,
    outputs: [16]NodeOutputTemplate,
};

pub const NodeInputTemplate = struct {
    name: IdLocal = .{},
    data_type: u8 = 0, // fix
};

pub const NodeOutputTemplate = struct {
    name: IdLocal = .{},
    data_type: u8 = 0, // fix
};

pub const Node = struct {
    name: IdLocal,
    template: NodeTemplate,
    inputs: [16]NodeInput = .{.{}} ** 16,
    outputs: [16]NodeOutput = .{.{}} ** 16,
    order: u32 = 0,
    data: ?*anyopaque = null,
    allocator: ?std.mem.Allocator = null,

    pub fn init(self: *Node) void {
        for (self.template.func.inputs) |*input, ni| {
            if (!input.name.isUnset()) {
                // self.inputs.appendAssumeCapacity(.{});
                self.inputs[ni].template = input;
            }
        }
        for (self.template.func.outputs) |*output, ni| {
            if (!output.name.isUnset()) {
                self.outputs[ni].template = output;
                self.outputs[ni].node = self;
            }
        }
    }

    pub fn getInputByString(self: *Node, name: []const u8) *NodeInput {
        const id = IdLocal.init(name);
        return self.getInput(id);
    }

    pub fn getInput(self: *Node, name: IdLocal) *NodeInput {
        for (self.*.template.func.inputs) |*input, ni| {
            if (input.name.eql(name)) {
                return &self.inputs[ni];
            }
        }
        unreachable;
    }

    pub fn getOutput(self: *Node, name: IdLocal) *NodeOutput {
        for (self.*.template.func.outputs) |*output, ni| {
            if (output.name.eql(name)) {
                return &self.outputs[ni];
            }
        }

        unreachable;
    }

    pub fn setOutputReference(self: *Node, name: IdLocal, ref: IdLocal) void {
        for (self.*.template.func.outputs) |conn, i| {
            if (conn.name.eql(name)) {
                // std.mem.copy(u8, self.*.outputs[i].reference, ref);
                self.*.outputs[i].reference = ref;
            }
        }
    }

    pub fn debugPrint(self: Node) void {
        std.debug.print("Node {s}\n", .{self.name.toString()});
        for (self.inputs) |input| {
            if (input.template) |t| {
                std.debug.print("  Input {s}\n", .{t.name.toString()});
            }
            continue;
        }
        // for (self.template.func.outputs) |*output, ni| {
        //     self.outputs[ni].template = output;
        // }
    }
};

pub const NodeInput = struct {
    template: ?*NodeInputTemplate = null,
    source: ?*NodeOutput = null,
    reference: IdLocal = .{},
    value: v.Variant = .{},
    // node: *Node = null,
    // output_node: *NodeOutput = ,
};

pub const NodeOutput = struct {
    node: ?*Node = null,
    template: ?*NodeOutputTemplate = null,
    reference: IdLocal = .{},
    // value: LOL = 0,
    // node: *Node,
};

pub const NodeFuncResult = union(enum) {
    success: v.Variant,
    processing: void,
    waiting: void,
};

pub const NodeFuncParam = struct {
    name: IdLocal,
    value: v.Variant = .{},
};

pub const NodeFunc = fn (node: *Node, output: *NodeOutput, params: []NodeFuncParam) NodeFuncResult;
