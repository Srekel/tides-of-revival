const std = @import("std");
const IdLocal = @import("../core/core.zig").IdLocal;

pub const NodeId = u32;

pub const ResourceType = extern struct {
    name: []const u8,
};

pub const Resource = extern struct {
    resource_type: ResourceType,
    name: []const u8,
    data: [2][]u8,
    buffer: u1 = 0,

    pub fn getData(self: *Resource) []u8 {
        return self.data[self.buffer];
    }

    pub fn getDataAsObject(self: *Resource, T: type) T {
        return std.mem.bytesAsValue(T, self.data[self.buffer]);
    }

    pub fn flip(self: *Resource) void {
        self.buffer = 1 - self.buffer;
    }
};

pub const MutatorType = struct {
    input_ranges: []f32,
};

pub const Mutator = struct {
    mutatortype: MutatorType,
    inputs: []*?Resource,
    probability: f32 = 1,
    iterations: u32 = 1,
};

pub const Grid_i32 = extern struct {
    resource: Resource,
    size: [2]u32,
    pub fn get(self: *Grid_i32) []i32 {
        return std.mem.bytesAsSlice(i32, self.resource.getData());
    }
};

pub const Node = extern struct {
    name: []const u8,
    connections_in: []NodeId,
    connections_out: []NodeId,
    inputs: []ResourceType,
    outputs: []ResourceType,
};

pub const Graph = extern struct {
    nodes: []Node,
    resources: []*Resource,
    pub fn getMutator(self: *Graph, nodeid: NodeId) *const Mutator {
        return std.mem.bytesAsValue(Mutator, self.nodes[nodeid]);
    }
};

const VisitedNodeSet = std.AutoHashMap(NodeId, bool);
pub fn writePass(writer: std.ArrayList(u8).Writer, graph: Graph, node_id: NodeId, visited: *VisitedNodeSet) void {
    visited.put(node_id, true);
    const node = graph.nodes[node_id];

    for (node.connections_in) |conn| {
        if (visited.get(conn) == null) {
            writePass(writer, graph, conn);
        }
    }

    writer.print("    pass_{s}_{d}(\n", .{
        node.name,
        node_id,
    });

    for (node.inputs) |res| {
        writer.print("        {s},\n", .{res});
    }

    for (node.outputs) |res| {
        writer.print("        {s},\n", .{res});
    }

    writer.write("    );");
}

pub fn writeGraph(graph: Graph) void {
    const allocator = std.heap.GeneralPurposeAllocator(.{}).allocator();
    var buffer = std.ArrayList(u8).init(allocator);
    const writer = buffer.writer();

    writer.print("pub fn graph_{s}(context:GraphContext) void {\n");

    for (graph.resources) |res| {
        writer.print("    var res_{s} = context.getResource(\"{s}\");\n", .{ res.name, res.name });
    }
    writer.write("\n");

    for (graph.nodes) |node_id| {
        writePass(graph, node_id);
    }
    writer.write("\n");

    var buf: [1024]u8 = undefined;

    const filepath = std.fmt.bufPrint(&buf, "graph_{s}.zig", .{
        graph.name,
    });

    const file = try std.fs.cwd().createFile(
        filepath,
        .{ .read = true },
    );
    defer file.close();

    const bytes_written = try file.writeAll(buffer.items);
    _ = bytes_written; // autofix
}
