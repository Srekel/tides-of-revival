const std = @import("std");

pub const RefCount = struct {
    count: u8 = 0,
};

pub const ReferrerId = u64;
pub const max_referrers = 16;

pub const RefCountWithId = struct {
    count: u8 = 0,
    referrers: [max_referrers]ReferrerId = undefined,

    pub fn addReference(self: *RefCountWithId, referrer: ReferrerId) void {
        std.debug.assert(std.mem.indexOfPosLinear(ReferrerId, self.referrers[0..], 0, &referrer[0..]));
        self.referrers[self.count] = referrer;
        self.count += 1;
    }

    pub fn removeReference(self: *RefCountWithId, referrer: ReferrerId) usize {
        const index = std.mem.indexOfPosLinear(ReferrerId, self.referrers[0..], 0, &referrer[0..]);
        self.count -= 1;
        self.referrers[index.?] = self.referrers[self.count];
        return index;
    }

    pub fn getReferrers(self: RefCountWithId) []ReferrerId {
        return self.referrers[0..self.count];
    }
};
