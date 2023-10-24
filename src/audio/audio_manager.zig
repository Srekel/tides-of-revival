const std = @import("std");
const AK = @import("wwise-zig");

pub const MaxThreadWorkers = 8;

pub const AudioManager = struct {
    allocator: std.mem.Allocator,
    io_hook: ?*AK.IOHooks.CAkFilePackageLowLevelIOBlocking = null,
    init_bank_id: AK.AkBankID = 0,
    memory_settings: AK.AkMemSettings = .{},
    stream_mgr_settings: AK.StreamMgr.AkStreamMgrSettings = .{},
    device_settings: AK.StreamMgr.AkDeviceSettings = .{},
    init_settings: AK.AkInitSettings = .{},
    platform_init_settings: AK.AkPlatformInitSettings = .{},
    music_settings: AK.MusicEngine.AkMusicSettings = .{},
    comm_settings: if (AK.Comm != void) AK.Comm.AkCommSettings else void = .{},
    job_worker_settings: if (AK.JobWorkerMgr != void) AK.JobWorkerMgr.InitSettings else void = .{},
    spatial_audio_settings: if (AK.SpatialAudio != void) AK.SpatialAudio.AkSpatialAudioInitSettings else void = undefined,

    pub fn create(allocator: std.mem.Allocator) !AudioManager {
        var audio_manager: AudioManager = .{ .allocator = allocator };
        try audio_manager.initDefaultWwiseSettings();
        try audio_manager.init();
        return audio_manager;
    }

    fn initDefaultWwiseSettings(self: *AudioManager) !void {
        AK.MemoryMgr.getDefaultSettings(&self.memory_settings);

        AK.StreamMgr.getDefaultSettings(&self.stream_mgr_settings);

        AK.StreamMgr.getDefaultDeviceSettings(&self.device_settings);

        try AK.SoundEngine.getDefaultInitSettings(self.allocator, &self.init_settings);

        AK.SoundEngine.getDefaultPlatformInitSettings(&self.platform_init_settings);

        AK.MusicEngine.getDefaultInitSettings(&self.music_settings);

        // Setup communication for debugging with the Wwise Authoring
        if (AK.Comm != void) {
            try AK.Comm.getDefaultInitSettings(&self.comm_settings);
        }

        if (AK.JobWorkerMgr != void) {
            AK.JobWorkerMgr.getDefaultInitSettings(&self.job_worker_settings);

            const max_workers = blk: {
                var runtime_cpu_count = std.Thread.getCpuCount() catch {
                    break :blk @as(usize, MaxThreadWorkers);
                };

                break :blk @min(runtime_cpu_count, MaxThreadWorkers);
            };
            self.job_worker_settings.num_worker_threads = @intCast(max_workers);

            self.init_settings.settings_job_manager = self.job_worker_settings.getJobMgrSettings();

            for (0..AK.AK_NUM_JOB_TYPES) |index| {
                self.init_settings.settings_job_manager.max_active_workers[index] = 2;
            }
        }
    }

    pub fn init(self: *AudioManager) !void {
        var allocator = self.allocator;

        // Create memory manager
        try AK.MemoryMgr.init(&self.memory_settings);

        // Create streaming manager
        _ = AK.StreamMgr.create(&self.stream_mgr_settings);

        // Create the I/O hook using default FilePackage blocking I/O Hook
        var io_hook = try AK.IOHooks.CAkFilePackageLowLevelIOBlocking.create(allocator);
        try io_hook.init(&self.device_settings, false);
        self.io_hook = io_hook;

        // Gather init settings and init the sound engine
        try AK.SoundEngine.init(allocator, &self.init_settings, &self.platform_init_settings);

        try AK.MusicEngine.init(&self.music_settings);

        // Setup communication for debugging with the Wwise Authoring
        if (AK.Comm != void) {
            self.comm_settings.setAppNetworkName("Tides of Revival");

            try AK.Comm.init(&self.comm_settings);
        }

        if (AK.JobWorkerMgr != void and self.job_worker_settings.num_worker_threads > 0) {
            try AK.JobWorkerMgr.initWorkers(&self.job_worker_settings);
        }

        // Setup I/O Hook base path
        const current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(current_dir);

        // TODO: Add path depending on platform
        const sound_banks_path = try std.fs.path.join(allocator, &[_][]const u8{
            current_dir,
            "content",
            "audio",
            "wwise",
        });
        defer allocator.free(sound_banks_path);

        try io_hook.setBasePath(allocator, sound_banks_path);

        try AK.StreamMgr.setCurrentLanguage(allocator, "English(US)");

        // Load Init Bank
        self.init_bank_id = try AK.SoundEngine.loadBankString(allocator, "Init.bnk", .{});

        // Register monitor callback
        try AK.SoundEngine.registerResourceMonitorCallback(resourceMonitorCallback);

        // Register spatial audio
        if (AK.SpatialAudio != void) {
            try AK.SpatialAudio.init(&self.spatial_audio_settings);
        }
    }

    pub fn destroy(self: *AudioManager) !void {
        try AK.SoundEngine.unregisterResourceMonitorCallback(resourceMonitorCallback);

        // try AK.SoundEngine.unloadBankID(self.init_bank_id, null, .{});

        if (AK.Comm != void) {
            AK.Comm.term();
        }

        // if (AK.SpatialAudio != void) {
        //     try AK.SpatialAudio.term();
        // }

        if (AK.SoundEngine.isInitialized()) {
            AK.SoundEngine.term();
        }

        if (AK.JobWorkerMgr != void and self.job_worker_settings.num_worker_threads > 0) {
            AK.JobWorkerMgr.termWorkers();
        }

        if (self.io_hook) |io_hook| {
            io_hook.term();

            io_hook.destroy(self.allocator);
        }

        if (AK.IAkStreamMgr.get()) |stream_mgr| {
            stream_mgr.destroy();
        }

        if (AK.MemoryMgr.isInitialized()) {
            AK.MemoryMgr.term();
        }
    }
};

var current_resource_monitor_data: AK.AkResourceMonitorDataSummary = .{};
fn resourceMonitorCallback(in_data_summary: ?*const AK.AkResourceMonitorDataSummary) callconv(.C) void {
    if (in_data_summary) |data_summary| {
        current_resource_monitor_data = data_summary.*;
    }
}
