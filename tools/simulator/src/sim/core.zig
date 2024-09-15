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
    name: []const u8,
    inputs: []ResourceType,
    outputs: []ResourceType,
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

pub const Graph = extern struct {
    nodes: [][]const u8,
    resources: [][]const u8,
    pub fn getMutator(self: *Graph, nodeid: NodeId) *const Mutator {
        return std.mem.bytesAsValue(Mutator, self.nodes[nodeid]);
    }
};
