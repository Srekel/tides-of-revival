const std = @import("std");
const ecs = @import("zflecs");

// inouts
pub fn Filter(comptime T: type) type {
    return struct {
        pub const inout: flecs.InOutKind = .filter;
        term_type: T,
    };
}

pub fn Writeonly(comptime T: type) type {
    return struct {
        pub const inout: flecs.InOutKind = .out;
        term_type: T,
    };
}

pub fn WriteonlyI(comptime T: type, field_param: []const u8) type {
    return struct {
        pub const inout: flecs.InOutKind = .out;
        pub const field = field_param;
        term_type: T,
    };
}

// opers
pub fn Or(comptime T1: type, comptime T2: type) type {
    return struct {
        term_type1: T1,
        term_type2: T2,
    };
}

pub fn Not(comptime T: type) type {
    return struct {
        pub const oper: flecs.OperKind = .not;
        term_type: T,
    };
}

// next three are opers that work only on kinds. not implemented yet
fn AndFrom(comptime T1: type, comptime T2: type) type {
    return struct {
        pub const oper: flecs.OperKind = .and_from;
        term_type1: T1,
        term_type2: T2,
    };
}

fn OrFrom(comptime T1: type, comptime T2: type) type {
    return struct {
        pub const oper: flecs.OperKind = .or_from;
        term_type1: T1,
        term_type2: T2,
    };
}

fn NotFrom(comptime T1: type, comptime T2: type) type {
    return struct {
        pub const oper: flecs.OperKind = .not_from;
        term_type1: T1,
        term_type2: T2,
    };
}

/// Non matching term. T should not be present in the query unless it should also match for some reason.
/// Same thing as `Mark(EcsNothing)`.
pub fn DontMatch(comptime T: type) type {
    return struct {
        pub const mask: u8 = .ecs_nothing;
        term_type: T,
    };
}

pub fn Mask(comptime T: type, mask_param: u8) type {
    return struct {
        pub const mask: u8 = mask_param;
        term_type: T,
    };
}

pub fn MaskI(comptime T: type, mask_param: u8, field_param: []const u8) type {
    return struct {
        pub const field = field_param;
        pub const mask: u8 = mask_param;
        term_type: T,
    };
}

pub fn Pair(comptime RelationT: type, comptime ObjectT: type) type {
    return struct {
        relation_type: RelationT,
        obj_type: ObjectT,
    };
}

pub fn PairI(comptime RelationT: type, comptime ObjectT: type, field_param: []const u8) type {
    return struct {
        pub const field = field_param;
        relation_type: RelationT,
        obj_type: ObjectT,
    };
}
