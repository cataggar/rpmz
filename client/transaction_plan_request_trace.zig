const std = @import("std");
const Allocator = std.mem.Allocator;

const abi = @import("transaction_plan_capture_abi");
const error_codes = @import("tdnf_error");

const TraceError = Allocator.Error || error{
    InvalidTrace,
};

const alter = struct {
    const autoerase: u32 = 0;
    const autoerase_all: u32 = 1;
    const downgrade: u32 = 2;
    const downgrade_all: u32 = 3;
    const erase: u32 = 4;
    const install: u32 = 5;
    const reinstall: u32 = 6;
    const update: u32 = 7;
    const update_all: u32 = 8;
    const distro_sync: u32 = 9;
};

const Request = struct {
    id: []const u8,
    kind: u32,
    subject: ?[]const u8,
};

pub const SemanticCapability = struct {
    name: []const u8,
    flags: ?[]const u8 = null,
    version: ?[]const u8 = null,
    release: ?[]const u8 = null,
    epoch: ?u64 = null,
    comparison: u32,
    sense: u32 = 0,
    pre: bool = false,
};

const OwnedCapability = struct {
    name: []const u8,
    flags: ?[]const u8,
    version: ?[]const u8,
    release: ?[]const u8,
    epoch: ?u64,
    comparison: u32,
    sense: u32,
    pre: bool,
};

const Selection = union(enum) {
    all,
    package: i32,
    name: []const u8,
    capability: OwnedCapability,
};

const Job = struct {
    action: u32,
    selection: Selection,
    raw_how: u32,
    effective_how: u32,
    raw_flags: u32,
    effective_flags: u32,
    reason: u32,
    request_ref: ?u32,
};

const Stage = struct {
    selection_id: i32,
    action: u32,
    reason: u32,
    request_ref: ?u32,
};

const Origin = struct {
    queue_pair_index: u32,
    job_ref: u32,
    request_ref: ?u32,
};

const PolicyFact = struct {
    value: []const u8,
    kind: u32,
};

pub const Trace = struct {
    arena_state: std.heap.ArenaAllocator,
    requests: std.ArrayList(Request) = .empty,
    stages: std.ArrayList(Stage) = .empty,
    jobs: std.ArrayList(Job) = .empty,
    origins: std.ArrayList(Origin) = .empty,
    policy_facts: std.ArrayList(PolicyFact) = .empty,
    stage_cursor: usize = 0,
    allow_erasing: bool = false,
    policies_recorded: bool = false,
    valid: bool = true,
    finalized: bool = false,
    view: abi.RequestTraceView = .{},

    pub fn init(allocator: Allocator) Trace {
        return .{
            .arena_state = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Trace) void {
        self.arena_state.deinit();
        self.* = undefined;
    }

    fn arenaAllocator(self: *Trace) Allocator {
        return self.arena_state.allocator();
    }

    fn ensureMutable(self: *const Trace) TraceError!void {
        if (!self.valid or self.finalized) return error.InvalidTrace;
    }

    fn invalidate(self: *Trace) void {
        self.valid = false;
        self.view = .{};
    }

    pub fn initResolve(
        self: *Trace,
        alter_type: u32,
        subjects: []const []const u8,
    ) TraceError!void {
        try self.ensureMutable();
        const kind = try requestKindFromAlter(alter_type);
        if (subjects.len == 0 or alterUsesSingletonRequest(alter_type)) {
            _ = try self.addRequest(kind, null, true);
            return;
        }
        for (subjects) |subject| {
            _ = try self.addRequest(kind, subject, true);
        }
    }

    pub fn addRequest(
        self: *Trace,
        kind: u32,
        raw_subject: ?[]const u8,
        sanitize_command_line_rpm: bool,
    ) TraceError!u32 {
        try self.ensureMutable();
        try validateRequestKind(kind);

        const allocator = self.arenaAllocator();
        const subject = if (raw_subject) |value|
            if (sanitize_command_line_rpm and shouldOmitSubject(value))
                null
            else
                try allocator.dupe(u8, value)
        else
            null;
        const ordinal: u32 = std.math.cast(u32, self.requests.items.len) orelse
            return error.InvalidTrace;
        const kind_name = requestKindName(kind);
        const id = if (subject) |value| blk: {
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(value, &digest, .{});
            const hex = lowerHex(digest);
            break :blk try std.fmt.allocPrint(
                allocator,
                "request-{d}-{s}-{s}",
                .{ ordinal, kind_name, &hex },
            );
        } else try std.fmt.allocPrint(
            allocator,
            "request-{d}-{s}",
            .{ ordinal, kind_name },
        );

        try self.requests.append(allocator, .{
            .id = id,
            .kind = kind,
            .subject = subject,
        });
        return ordinal;
    }

    pub fn recordGoalRange(
        self: *Trace,
        ids: []const i32,
        start: usize,
        end: usize,
        alter_type: u32,
        reason: u32,
        raw_request_ref: u32,
    ) TraceError!void {
        try self.ensureMutable();
        if (start > end or end > ids.len) return error.InvalidTrace;
        const action = try actionFromAlter(alter_type);
        try validateReason(reason);
        const request_ref = try self.decodeRequestRef(raw_request_ref);
        const allocator = self.arenaAllocator();
        for (ids[start..end]) |selection_id| {
            if (selection_id <= 0) return error.InvalidTrace;
            try self.stages.append(allocator, .{
                .selection_id = selection_id,
                .action = action,
                .reason = reason,
                .request_ref = request_ref,
            });
        }
    }

    pub fn recordHistoryGoal(
        self: *Trace,
        subject: []const u8,
        request_kind: u32,
        action: u32,
        ids: []const i32,
        start: usize,
        end: usize,
    ) TraceError!void {
        const request_ref = try self.addRequest(
            request_kind,
            subject,
            false,
        );
        try validateAction(action);
        if (start > end or end > ids.len) return error.InvalidTrace;
        const allocator = self.arenaAllocator();
        for (ids[start..end]) |selection_id| {
            if (selection_id <= 0) return error.InvalidTrace;
            try self.stages.append(allocator, .{
                .selection_id = selection_id,
                .action = action,
                .reason = abi.request_reason.user,
                .request_ref = request_ref,
            });
        }
    }

    pub fn commitGoal(
        self: *Trace,
        selection_id: i32,
        alter_type: u32,
        queue: []const i32,
        start: usize,
        end: usize,
    ) TraceError!void {
        try self.ensureMutable();
        if (self.stage_cursor >= self.stages.items.len or
            start > end or end > queue.len or start % 2 != 0 or
            (end != start and end != start + 2))
        {
            return error.InvalidTrace;
        }
        const stage = self.stages.items[self.stage_cursor];
        self.stage_cursor += 1;
        if (stage.selection_id != selection_id or
            stage.action != try actionFromAlter(alter_type))
        {
            return error.InvalidTrace;
        }
        if (end == start) return;
        if (queue[start + 1] != selection_id) return error.InvalidTrace;
        try self.recordPackageJob(
            @intCast(start / 2),
            stage.action,
            selection_id,
            queue[start],
            0,
            stage.reason,
            encodeRequestRef(stage.request_ref),
        );
    }

    pub fn recordPackageJob(
        self: *Trace,
        queue_pair_index: u32,
        action: u32,
        selection_id: i32,
        raw_how: i32,
        raw_flags: u32,
        reason: u32,
        raw_request_ref: u32,
    ) TraceError!void {
        if (selection_id <= 0) return error.InvalidTrace;
        try self.appendJob(
            queue_pair_index,
            action,
            .{ .package = selection_id },
            raw_how,
            raw_flags,
            reason,
            raw_request_ref,
        );
    }

    pub fn recordPackageJobRange(
        self: *Trace,
        queue: []const i32,
        start: usize,
        end: usize,
        action: u32,
        reason: u32,
        raw_request_ref: u32,
    ) TraceError!void {
        try self.ensureMutable();
        if (start > end or end > queue.len or start % 2 != 0 or end % 2 != 0)
            return error.InvalidTrace;
        var index = start;
        while (index < end) : (index += 2) {
            try self.recordPackageJob(
                @intCast(index / 2),
                action,
                queue[index + 1],
                queue[index],
                0,
                reason,
                raw_request_ref,
            );
        }
    }

    pub fn recordNameJob(
        self: *Trace,
        queue_pair_index: u32,
        action: u32,
        selection_name: []const u8,
        raw_how: i32,
        raw_flags: u32,
        reason: u32,
        raw_request_ref: u32,
    ) TraceError!void {
        try self.ensureMutable();
        if (selection_name.len == 0) return error.InvalidTrace;
        const name = try self.arenaAllocator().dupe(u8, selection_name);
        try self.appendJob(
            queue_pair_index,
            action,
            .{ .name = name },
            raw_how,
            raw_flags,
            reason,
            raw_request_ref,
        );
    }

    pub fn recordAllJob(
        self: *Trace,
        queue_pair_index: u32,
        action: u32,
        raw_how: i32,
        raw_flags: u32,
        reason: u32,
        raw_request_ref: u32,
    ) TraceError!void {
        try self.appendJob(
            queue_pair_index,
            action,
            .all,
            raw_how,
            raw_flags,
            reason,
            raw_request_ref,
        );
    }

    pub fn recordCapabilityJob(
        self: *Trace,
        queue_pair_index: u32,
        action: u32,
        capability: SemanticCapability,
        raw_how: i32,
        raw_flags: u32,
        reason: u32,
        raw_request_ref: u32,
    ) TraceError!void {
        try self.ensureMutable();
        const owned = try cloneSemanticCapability(
            self.arenaAllocator(),
            capability,
        );
        try self.appendJob(
            queue_pair_index,
            action,
            .{ .capability = owned },
            raw_how,
            raw_flags,
            reason,
            raw_request_ref,
        );
    }

    fn appendJob(
        self: *Trace,
        queue_pair_index: u32,
        action: u32,
        selection: Selection,
        raw_how: i32,
        raw_flags: u32,
        reason: u32,
        raw_request_ref: u32,
    ) TraceError!void {
        try self.ensureMutable();
        try validateAction(action);
        try validateReason(reason);
        if (raw_flags & ~known_flags != 0 or
            queue_pair_index != self.origins.items.len)
        {
            return error.InvalidTrace;
        }
        const request_ref = try self.decodeRequestRef(raw_request_ref);
        const allocator = self.arenaAllocator();
        const job_ref: u32 = std.math.cast(u32, self.jobs.items.len) orelse
            return error.InvalidTrace;
        const how: u32 = @bitCast(raw_how);
        try self.jobs.append(allocator, .{
            .action = action,
            .selection = selection,
            .raw_how = how,
            .effective_how = how,
            .raw_flags = raw_flags,
            .effective_flags = raw_flags,
            .reason = reason,
            .request_ref = request_ref,
        });
        try self.origins.append(allocator, .{
            .queue_pair_index = queue_pair_index,
            .job_ref = job_ref,
            .request_ref = request_ref,
        });
    }

    pub fn recordPolicies(
        self: *Trace,
        excludes: []const []const u8,
        installonly_names: []const []const u8,
        locked_names: []const []const u8,
        min_versions: []const []const u8,
        protected_names: []const []const u8,
        allow_erasing: bool,
    ) TraceError!void {
        try self.ensureMutable();
        if (self.policies_recorded) return error.InvalidTrace;
        self.policies_recorded = true;
        self.allow_erasing = allow_erasing;
        try self.recordPolicyValues(abi.request_trace_policy.exclude, excludes);
        try self.recordPolicyValues(
            abi.request_trace_policy.installonly,
            installonly_names,
        );
        try self.recordPolicyValues(abi.request_trace_policy.lock, locked_names);
        try self.recordPolicyValues(
            abi.request_trace_policy.min_version,
            min_versions,
        );
        try self.recordPolicyValues(
            abi.request_trace_policy.protected,
            protected_names,
        );
    }

    fn recordPolicyValues(
        self: *Trace,
        kind: u32,
        values: []const []const u8,
    ) TraceError!void {
        try validatePolicyKind(kind);
        const allocator = self.arenaAllocator();
        for (values) |value| {
            if (value.len == 0) return error.InvalidTrace;
            try self.policy_facts.append(allocator, .{
                .value = try allocator.dupe(u8, value),
                .kind = kind,
            });
        }
    }

    pub fn finalize(
        self: *Trace,
        queue: []const i32,
        clean_deps_mask: i32,
        force_best_mask: i32,
    ) TraceError!void {
        try self.ensureMutable();
        if (queue.len % 2 != 0 or self.stage_cursor != self.stages.items.len or
            self.jobs.items.len != queue.len / 2 or
            self.origins.items.len != queue.len / 2)
        {
            return error.InvalidTrace;
        }
        const clean_mask: u32 = @bitCast(clean_deps_mask);
        const best_mask: u32 = @bitCast(force_best_mask);
        for (self.origins.items, 0..) |origin, index| {
            if (origin.queue_pair_index != index or
                origin.job_ref >= self.jobs.items.len)
            {
                return error.InvalidTrace;
            }
            const effective_how: u32 = @bitCast(queue[index * 2]);
            const job = &self.jobs.items[origin.job_ref];
            job.effective_how = effective_how;
            job.effective_flags = job.raw_flags;
            if (effective_how & clean_mask != 0)
                job.effective_flags |= abi.request_trace_flag.clean_deps;
            if (effective_how & best_mask != 0)
                job.effective_flags |= abi.request_trace_flag.force_best;
        }
        try self.buildView();
        self.finalized = true;
    }

    fn buildView(self: *Trace) TraceError!void {
        const allocator = self.arenaAllocator();
        const requests = try allocator.alloc(abi.Request, self.requests.items.len);
        for (self.requests.items, requests) |request, *output| {
            output.* = .{
                .id = bytes(request.id),
                .kind = request.kind,
            };
            if (request.subject) |subject| {
                output.subject = bytes(subject);
                output.has_subject = 1;
            }
        }

        const jobs = try allocator.alloc(abi.RequestTraceJob, self.jobs.items.len);
        for (self.jobs.items, jobs) |job, *output| {
            output.* = .{
                .action = job.action,
                .selection_kind = selectionKind(job.selection),
                .raw_how = job.raw_how,
                .effective_how = job.effective_how,
                .raw_flags = job.raw_flags,
                .effective_flags = job.effective_flags,
                .reason = job.reason,
            };
            switch (job.selection) {
                .all => {},
                .package => |selection_id| output.selection_id = selection_id,
                .name => |name| output.selection_value = bytes(name),
                .capability => |capability| {
                    output.capability = capabilityToAbi(capability);
                },
            }
            if (job.request_ref) |request_ref| {
                output.request_ref = request_ref;
                output.has_request_ref = 1;
            }
        }

        const origins = try allocator.alloc(
            abi.RequestTraceQueueOrigin,
            self.origins.items.len,
        );
        for (self.origins.items, origins) |origin, *output| {
            output.* = .{
                .queue_pair_index = origin.queue_pair_index,
                .job_ref = origin.job_ref,
            };
            if (origin.request_ref) |request_ref| {
                output.request_ref = request_ref;
                output.has_request_ref = 1;
            }
        }

        const policy_facts = try allocator.alloc(
            abi.RequestTracePolicyFact,
            self.policy_facts.items.len,
        );
        for (self.policy_facts.items, policy_facts) |fact, *output| {
            output.* = .{
                .value = bytes(fact.value),
                .kind = fact.kind,
            };
        }

        self.view = .{
            .requests = optionalManyPointer(abi.Request, requests),
            .jobs = optionalManyPointer(abi.RequestTraceJob, jobs),
            .queue_origins = optionalManyPointer(
                abi.RequestTraceQueueOrigin,
                origins,
            ),
            .policy_facts = optionalManyPointer(
                abi.RequestTracePolicyFact,
                policy_facts,
            ),
            .request_count = @intCast(requests.len),
            .job_count = @intCast(jobs.len),
            .queue_origin_count = @intCast(origins.len),
            .policy_fact_count = @intCast(policy_facts.len),
            .allow_erasing = @intFromBool(self.allow_erasing),
        };
    }

    pub fn getView(self: *const Trace) ?*const abi.RequestTraceView {
        if (!self.valid or !self.finalized) return null;
        return &self.view;
    }

    fn decodeRequestRef(
        self: *const Trace,
        raw: u32,
    ) TraceError!?u32 {
        if (raw == abi.request_trace_no_request) return null;
        if (raw >= self.requests.items.len) return error.InvalidTrace;
        return raw;
    }
};

pub const CaptureFactsOwner = struct {
    backing_allocator: Allocator,
    arena_state: std.heap.ArenaAllocator,
    facts: abi.RequestTraceCaptureFacts = .{},

    pub fn create(
        allocator: Allocator,
        trace: *const Trace,
        package_refs: []const abi.RequestTracePackageRef,
    ) TraceError!*CaptureFactsOwner {
        if (!trace.valid or !trace.finalized) return error.InvalidTrace;
        try validatePackageRefs(package_refs);

        const owner = try allocator.create(CaptureFactsOwner);
        owner.* = .{
            .backing_allocator = allocator,
            .arena_state = std.heap.ArenaAllocator.init(allocator),
        };
        errdefer owner.destroy();

        const arena = owner.arena_state.allocator();
        const requests = try arena.alloc(abi.Request, trace.requests.items.len);
        for (trace.requests.items, requests) |request, *output| {
            output.* = .{
                .id = bytes(try arena.dupe(u8, request.id)),
                .kind = request.kind,
            };
            if (request.subject) |subject| {
                output.subject = bytes(try arena.dupe(u8, subject));
                output.has_subject = 1;
            }
        }

        const jobs = try arena.alloc(abi.Job, trace.jobs.items.len);
        for (trace.jobs.items, jobs) |job, *output| {
            output.* = .{
                .action = job.action,
                .selection_kind = selectionKind(job.selection),
                .reason = job.reason,
                .clean_deps = flag(
                    job.effective_flags,
                    abi.request_trace_flag.clean_deps,
                ),
                .force_best = flag(
                    job.effective_flags,
                    abi.request_trace_flag.force_best,
                ),
                .targeted = flag(
                    job.effective_flags,
                    abi.request_trace_flag.targeted,
                ),
                .not_by_user = flag(
                    job.effective_flags,
                    abi.request_trace_flag.not_by_user,
                ),
                .weak = flag(
                    job.effective_flags,
                    abi.request_trace_flag.weak,
                ),
            };
            switch (job.selection) {
                .all => {},
                .package => |selection_id| {
                    output.selection_package_ref = try findPackageRef(
                        package_refs,
                        selection_id,
                    );
                },
                .name => |name| {
                    output.selection_value = bytes(try arena.dupe(u8, name));
                },
                .capability => |capability| {
                    output.capability = try cloneCapabilityAbi(
                        arena,
                        capability,
                    );
                },
            }
            if (job.request_ref) |request_ref| {
                output.request_ref = request_ref;
                output.has_request_ref = 1;
            }
        }

        owner.facts = .{
            .requests = optionalManyPointer(abi.Request, requests),
            .jobs = optionalManyPointer(abi.Job, jobs),
            .request_count = @intCast(requests.len),
            .job_count = @intCast(jobs.len),
        };
        return owner;
    }

    pub fn destroy(self: *CaptureFactsOwner) void {
        const allocator = self.backing_allocator;
        self.arena_state.deinit();
        allocator.destroy(self);
    }
};

fn shouldOmitSubject(subject: []const u8) bool {
    if (std.mem.endsWith(u8, subject, ".rpm")) return true;
    const scheme = std.mem.indexOf(u8, subject, "://") orelse return false;
    const authority_start = scheme + 3;
    const authority_end = std.mem.indexOfScalarPos(
        u8,
        subject,
        authority_start,
        '/',
    ) orelse subject.len;
    return std.mem.indexOfScalar(
        u8,
        subject[authority_start..authority_end],
        '@',
    ) != null;
}

fn requestKindFromAlter(alter_type: u32) TraceError!u32 {
    return switch (alter_type) {
        alter.autoerase, alter.autoerase_all, alter.erase => abi.request_kind.erase,
        alter.downgrade, alter.downgrade_all => abi.request_kind.downgrade,
        alter.install => abi.request_kind.install,
        alter.reinstall => abi.request_kind.reinstall,
        alter.update => abi.request_kind.update,
        alter.update_all => abi.request_kind.update_all,
        alter.distro_sync => abi.request_kind.distro_sync,
        else => error.InvalidTrace,
    };
}

fn actionFromAlter(alter_type: u32) TraceError!u32 {
    return switch (alter_type) {
        alter.autoerase, alter.autoerase_all, alter.erase => abi.job_action.erase,
        alter.downgrade, alter.downgrade_all => abi.job_action.downgrade,
        alter.install => abi.job_action.install,
        alter.reinstall => abi.job_action.reinstall,
        alter.update, alter.update_all => abi.job_action.update,
        alter.distro_sync => abi.job_action.dist_sync,
        else => error.InvalidTrace,
    };
}

fn alterUsesSingletonRequest(alter_type: u32) bool {
    return alter_type == alter.autoerase_all or
        alter_type == alter.downgrade_all or
        alter_type == alter.update_all or
        alter_type == alter.distro_sync;
}

fn validateRequestKind(kind: u32) TraceError!void {
    if (kind > abi.request_kind.update_all) return error.InvalidTrace;
}

fn validateAction(action: u32) TraceError!void {
    if (action > abi.job_action.allow_uninstall) return error.InvalidTrace;
}

fn validateReason(reason: u32) TraceError!void {
    if (reason > abi.request_reason.policy) return error.InvalidTrace;
}

fn validatePolicyKind(kind: u32) TraceError!void {
    if (kind > abi.request_trace_policy.protected) return error.InvalidTrace;
}

fn requestKindName(kind: u32) []const u8 {
    return switch (kind) {
        abi.request_kind.distro_sync => "distro-sync",
        abi.request_kind.downgrade => "downgrade",
        abi.request_kind.erase => "erase",
        abi.request_kind.install => "install",
        abi.request_kind.lock => "lock",
        abi.request_kind.reinstall => "reinstall",
        abi.request_kind.update => "update",
        abi.request_kind.update_all => "update-all",
        else => unreachable,
    };
}

fn lowerHex(input: [32]u8) [64]u8 {
    const alphabet = "0123456789abcdef";
    var output: [64]u8 = undefined;
    for (input, 0..) |value, index| {
        output[index * 2] = alphabet[value >> 4];
        output[index * 2 + 1] = alphabet[value & 0xf];
    }
    return output;
}

fn cloneSemanticCapability(
    allocator: Allocator,
    input: SemanticCapability,
) TraceError!OwnedCapability {
    if (input.name.len == 0 or input.comparison > abi.compare_op.none)
        return error.InvalidTrace;
    return .{
        .name = try allocator.dupe(u8, input.name),
        .flags = try cloneOptionalBytes(allocator, input.flags),
        .version = try cloneOptionalBytes(allocator, input.version),
        .release = try cloneOptionalBytes(allocator, input.release),
        .epoch = input.epoch,
        .comparison = input.comparison,
        .sense = input.sense,
        .pre = input.pre,
    };
}

fn cloneOptionalBytes(
    allocator: Allocator,
    input: ?[]const u8,
) Allocator.Error!?[]const u8 {
    return if (input) |value| try allocator.dupe(u8, value) else null;
}

fn selectionKind(selection: Selection) u32 {
    return switch (selection) {
        .all => abi.selection_kind.all,
        .package => abi.selection_kind.package,
        .name => abi.selection_kind.name,
        .capability => abi.selection_kind.capability,
    };
}

fn capabilityToAbi(input: OwnedCapability) abi.Capability {
    var output = abi.Capability{
        .name = bytes(input.name),
        .comparison = input.comparison,
        .sense = input.sense,
        .pre = @intFromBool(input.pre),
    };
    if (input.flags) |value| {
        output.flags = bytes(value);
        output.has_flags = 1;
    }
    if (input.version) |value| {
        output.version = bytes(value);
        output.has_version = 1;
    }
    if (input.release) |value| {
        output.release = bytes(value);
        output.has_release = 1;
    }
    if (input.epoch) |value| {
        output.epoch = value;
        output.has_epoch = 1;
    }
    return output;
}

fn cloneCapabilityAbi(
    allocator: Allocator,
    input: OwnedCapability,
) Allocator.Error!abi.Capability {
    var output = capabilityToAbi(input);
    output.name = bytes(try allocator.dupe(u8, input.name));
    if (input.flags) |value| output.flags = bytes(try allocator.dupe(u8, value));
    if (input.version) |value|
        output.version = bytes(try allocator.dupe(u8, value));
    if (input.release) |value|
        output.release = bytes(try allocator.dupe(u8, value));
    return output;
}

fn semanticCapabilityFromAbi(
    raw: abi.Capability,
) TraceError!SemanticCapability {
    return .{
        .name = try borrowedBytes(raw.name),
        .flags = try borrowedOptionalBytes(raw.flags, raw.has_flags),
        .version = try borrowedOptionalBytes(raw.version, raw.has_version),
        .release = try borrowedOptionalBytes(raw.release, raw.has_release),
        .epoch = try optionalU64(raw.epoch, raw.has_epoch),
        .comparison = raw.comparison,
        .sense = raw.sense,
        .pre = try boolean(raw.pre),
    };
}

fn borrowedBytes(raw: abi.Bytes) TraceError![]const u8 {
    if (raw.length == 0)
        return if (raw.data == null) "" else error.InvalidTrace;
    const pointer = raw.data orelse return error.InvalidTrace;
    return pointer[0..raw.length];
}

fn borrowedOptionalBytes(
    raw: abi.Bytes,
    present: u32,
) TraceError!?[]const u8 {
    if (!try boolean(present)) {
        if (raw.data != null or raw.length != 0) return error.InvalidTrace;
        return null;
    }
    return try borrowedBytes(raw);
}

fn optionalU64(value: u64, present: u32) TraceError!?u64 {
    if (try boolean(present)) return value;
    if (value != 0) return error.InvalidTrace;
    return null;
}

fn boolean(value: u32) TraceError!bool {
    return switch (value) {
        0 => false,
        1 => true,
        else => error.InvalidTrace,
    };
}

fn bytes(value: []const u8) abi.Bytes {
    if (value.len == 0) return .{};
    return .{ .data = value.ptr, .length = value.len };
}

fn optionalManyPointer(comptime T: type, values: []const T) ?[*]const T {
    return if (values.len == 0) null else values.ptr;
}

fn encodeRequestRef(value: ?u32) u32 {
    return value orelse abi.request_trace_no_request;
}

const known_flags = abi.request_trace_flag.clean_deps |
    abi.request_trace_flag.force_best |
    abi.request_trace_flag.targeted |
    abi.request_trace_flag.not_by_user |
    abi.request_trace_flag.weak;

fn flag(flags: u32, mask: u32) u32 {
    return @intFromBool(flags & mask != 0);
}

fn validatePackageRefs(
    package_refs: []const abi.RequestTracePackageRef,
) TraceError!void {
    for (package_refs, 0..) |value, index| {
        if (value.selection_id <= 0) return error.InvalidTrace;
        for (package_refs[0..index]) |prior| {
            if (prior.selection_id == value.selection_id)
                return error.InvalidTrace;
        }
    }
}

fn findPackageRef(
    package_refs: []const abi.RequestTracePackageRef,
    selection_id: i32,
) TraceError!u32 {
    for (package_refs) |value| {
        if (value.selection_id == selection_id) return value.package_ref;
    }
    return error.InvalidTrace;
}

fn rawCString(raw: ?[*:0]const u8) TraceError![]const u8 {
    const pointer = raw orelse return error.InvalidTrace;
    return std.mem.span(pointer);
}

fn rawI32Slice(
    raw: ?[*]const i32,
    count: u32,
) TraceError![]const i32 {
    if (count == 0) return &.{};
    const pointer = raw orelse return error.InvalidTrace;
    return pointer[0..count];
}

fn rawPackageRefSlice(
    raw: ?[*]const abi.RequestTracePackageRef,
    count: u32,
) TraceError![]const abi.RequestTracePackageRef {
    if (count == 0) {
        if (raw != null) return error.InvalidTrace;
        return &.{};
    }
    const pointer = raw orelse return error.InvalidTrace;
    return pointer[0..count];
}

fn cStringsToOwnedSlice(
    allocator: Allocator,
    raw: ?[*]const ?[*:0]const u8,
) TraceError![]const []const u8 {
    const pointer = raw orelse return &.{};
    var count: usize = 0;
    while (pointer[count] != null) : (count += 1) {}
    const output = try allocator.alloc([]const u8, count);
    for (output, 0..) |*value, index| {
        value.* = try rawCString(pointer[index]);
    }
    return output;
}

fn handleTraceError(trace: *Trace, result: TraceError!void) void {
    result catch trace.invalidate();
}

fn requestTraceCreate(
    alter_type: u32,
    raw_subjects: ?[*]const ?[*:0]const u8,
    subject_count: u32,
) callconv(.c) ?*Trace {
    if (subject_count != 0 and raw_subjects == null) return null;
    const trace = std.heap.c_allocator.create(Trace) catch return null;
    trace.* = Trace.init(std.heap.c_allocator);

    const kind = requestKindFromAlter(alter_type) catch {
        requestTraceDestroy(trace);
        return null;
    };
    if (subject_count == 0 or alterUsesSingletonRequest(alter_type)) {
        _ = trace.addRequest(kind, null, true) catch {
            requestTraceDestroy(trace);
            return null;
        };
    } else {
        for (raw_subjects.?[0..subject_count]) |raw_subject| {
            const subject = rawCString(raw_subject) catch {
                requestTraceDestroy(trace);
                return null;
            };
            _ = trace.addRequest(kind, subject, true) catch {
                requestTraceDestroy(trace);
                return null;
            };
        }
    }
    return trace;
}

fn requestTraceCreateHistory() callconv(.c) ?*Trace {
    const trace = std.heap.c_allocator.create(Trace) catch return null;
    trace.* = Trace.init(std.heap.c_allocator);
    return trace;
}

fn requestTraceDestroy(trace: ?*Trace) callconv(.c) void {
    const value = trace orelse return;
    value.deinit();
    std.heap.c_allocator.destroy(value);
}

fn requestTraceRecordGoalRange(
    trace: ?*Trace,
    raw_ids: ?[*]const i32,
    start: u32,
    end: u32,
    alter_type: u32,
    reason: u32,
    request_ref: u32,
) callconv(.c) void {
    const value = trace orelse return;
    if (end == 0 and raw_ids == null and start == 0) {
        handleTraceError(
            value,
            value.recordGoalRange(&.{}, 0, 0, alter_type, reason, request_ref),
        );
        return;
    }
    const ids = rawI32Slice(raw_ids, end) catch {
        value.invalidate();
        return;
    };
    handleTraceError(
        value,
        value.recordGoalRange(ids, start, end, alter_type, reason, request_ref),
    );
}

fn requestTraceRecordHistoryGoal(
    trace: ?*Trace,
    raw_subject: ?[*:0]const u8,
    request_kind: u32,
    action: u32,
    raw_ids: ?[*]const i32,
    start: u32,
    end: u32,
) callconv(.c) void {
    const value = trace orelse return;
    const subject = rawCString(raw_subject) catch {
        value.invalidate();
        return;
    };
    const ids = rawI32Slice(raw_ids, end) catch {
        value.invalidate();
        return;
    };
    handleTraceError(
        value,
        value.recordHistoryGoal(
            subject,
            request_kind,
            action,
            ids,
            start,
            end,
        ),
    );
}

fn requestTraceCommitGoal(
    trace: ?*Trace,
    selection_id: i32,
    alter_type: u32,
    raw_queue: ?[*]const i32,
    start: u32,
    end: u32,
) callconv(.c) void {
    const value = trace orelse return;
    const queue = rawI32Slice(raw_queue, end) catch {
        value.invalidate();
        return;
    };
    handleTraceError(
        value,
        value.commitGoal(selection_id, alter_type, queue, start, end),
    );
}

fn requestTraceRecordPackageJob(
    trace: ?*Trace,
    queue_pair_index: u32,
    action: u32,
    selection_id: i32,
    raw_how: i32,
    raw_flags: u32,
    reason: u32,
    request_ref: u32,
) callconv(.c) void {
    const value = trace orelse return;
    handleTraceError(
        value,
        value.recordPackageJob(
            queue_pair_index,
            action,
            selection_id,
            raw_how,
            raw_flags,
            reason,
            request_ref,
        ),
    );
}

fn requestTraceRecordPackageJobRange(
    trace: ?*Trace,
    raw_queue: ?[*]const i32,
    start: u32,
    end: u32,
    action: u32,
    reason: u32,
    request_ref: u32,
) callconv(.c) void {
    const value = trace orelse return;
    const queue = rawI32Slice(raw_queue, end) catch {
        value.invalidate();
        return;
    };
    handleTraceError(
        value,
        value.recordPackageJobRange(
            queue,
            start,
            end,
            action,
            reason,
            request_ref,
        ),
    );
}

fn requestTraceRecordNameJob(
    trace: ?*Trace,
    queue_pair_index: u32,
    action: u32,
    raw_name: ?[*:0]const u8,
    raw_how: i32,
    raw_flags: u32,
    reason: u32,
    request_ref: u32,
) callconv(.c) void {
    const value = trace orelse return;
    const name = rawCString(raw_name) catch {
        value.invalidate();
        return;
    };
    handleTraceError(
        value,
        value.recordNameJob(
            queue_pair_index,
            action,
            name,
            raw_how,
            raw_flags,
            reason,
            request_ref,
        ),
    );
}

fn requestTraceRecordAllJob(
    trace: ?*Trace,
    queue_pair_index: u32,
    action: u32,
    raw_how: i32,
    raw_flags: u32,
    reason: u32,
    request_ref: u32,
) callconv(.c) void {
    const value = trace orelse return;
    handleTraceError(
        value,
        value.recordAllJob(
            queue_pair_index,
            action,
            raw_how,
            raw_flags,
            reason,
            request_ref,
        ),
    );
}

fn requestTraceRecordCapabilityJob(
    trace: ?*Trace,
    queue_pair_index: u32,
    action: u32,
    raw_capability: ?*const abi.Capability,
    raw_how: i32,
    raw_flags: u32,
    reason: u32,
    request_ref: u32,
) callconv(.c) void {
    const value = trace orelse return;
    const capability = semanticCapabilityFromAbi(
        (raw_capability orelse {
            value.invalidate();
            return;
        }).*,
    ) catch {
        value.invalidate();
        return;
    };
    handleTraceError(
        value,
        value.recordCapabilityJob(
            queue_pair_index,
            action,
            capability,
            raw_how,
            raw_flags,
            reason,
            request_ref,
        ),
    );
}

fn requestTraceRecordPolicies(
    trace: ?*Trace,
    raw_excludes: ?[*]const ?[*:0]const u8,
    raw_installonly_names: ?[*]const ?[*:0]const u8,
    raw_locked_names: ?[*]const ?[*:0]const u8,
    raw_min_versions: ?[*]const ?[*:0]const u8,
    raw_protected_names: ?[*]const ?[*:0]const u8,
    raw_allow_erasing: u32,
) callconv(.c) void {
    const value = trace orelse return;
    const allocator = value.arenaAllocator();
    const excludes = cStringsToOwnedSlice(allocator, raw_excludes) catch {
        value.invalidate();
        return;
    };
    const installonly_names = cStringsToOwnedSlice(
        allocator,
        raw_installonly_names,
    ) catch {
        value.invalidate();
        return;
    };
    const locked_names = cStringsToOwnedSlice(
        allocator,
        raw_locked_names,
    ) catch {
        value.invalidate();
        return;
    };
    const min_versions = cStringsToOwnedSlice(
        allocator,
        raw_min_versions,
    ) catch {
        value.invalidate();
        return;
    };
    const protected_names = cStringsToOwnedSlice(
        allocator,
        raw_protected_names,
    ) catch {
        value.invalidate();
        return;
    };
    const allow_erasing = boolean(raw_allow_erasing) catch {
        value.invalidate();
        return;
    };
    handleTraceError(
        value,
        value.recordPolicies(
            excludes,
            installonly_names,
            locked_names,
            min_versions,
            protected_names,
            allow_erasing,
        ),
    );
}

fn requestTraceFinalize(
    trace: ?*Trace,
    raw_queue: ?[*]const i32,
    element_count: u32,
    clean_deps_mask: i32,
    force_best_mask: i32,
) callconv(.c) void {
    const value = trace orelse return;
    const queue = rawI32Slice(raw_queue, element_count) catch {
        value.invalidate();
        return;
    };
    handleTraceError(
        value,
        value.finalize(queue, clean_deps_mask, force_best_mask),
    );
}

fn requestTraceGetView(
    trace: ?*const Trace,
) callconv(.c) ?*const abi.RequestTraceView {
    return (trace orelse return null).getView();
}

fn mapTraceError(err: anyerror) u32 {
    return switch (err) {
        error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        else => error_codes.ERROR_TDNF_INVALID_PARAMETER,
    };
}

fn requestTraceCaptureFactsCreate(
    trace: ?*const Trace,
    raw_package_refs: ?[*]const abi.RequestTracePackageRef,
    package_ref_count: u32,
    raw_facts: ?*?*const abi.RequestTraceCaptureFacts,
    raw_owner: ?*?*CaptureFactsOwner,
) callconv(.c) u32 {
    const facts_out = raw_facts orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const owner_out = raw_owner orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    facts_out.* = null;
    owner_out.* = null;
    const value = trace orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const package_refs = rawPackageRefSlice(
        raw_package_refs,
        package_ref_count,
    ) catch |err| return mapTraceError(err);
    const owner = CaptureFactsOwner.create(
        std.heap.c_allocator,
        value,
        package_refs,
    ) catch |err| return mapTraceError(err);
    owner_out.* = owner;
    facts_out.* = &owner.facts;
    return 0;
}

fn requestTraceCaptureFactsDestroy(
    owner: ?*CaptureFactsOwner,
) callconv(.c) void {
    if (owner) |value| value.destroy();
}

comptime {
    @export(&requestTraceCreate, .{
        .name = "TDNFTransactionPlanRequestTraceCreate",
        .visibility = .hidden,
    });
    @export(&requestTraceCreateHistory, .{
        .name = "TDNFTransactionPlanRequestTraceCreateHistory",
        .visibility = .hidden,
    });
    @export(&requestTraceDestroy, .{
        .name = "TDNFTransactionPlanRequestTraceDestroy",
        .visibility = .hidden,
    });
    @export(&requestTraceRecordGoalRange, .{
        .name = "TDNFTransactionPlanRequestTraceRecordGoalRange",
        .visibility = .hidden,
    });
    @export(&requestTraceRecordHistoryGoal, .{
        .name = "TDNFTransactionPlanRequestTraceRecordHistoryGoal",
        .visibility = .hidden,
    });
    @export(&requestTraceCommitGoal, .{
        .name = "TDNFTransactionPlanRequestTraceCommitGoal",
        .visibility = .hidden,
    });
    @export(&requestTraceRecordPackageJob, .{
        .name = "TDNFTransactionPlanRequestTraceRecordPackageJob",
        .visibility = .hidden,
    });
    @export(&requestTraceRecordPackageJobRange, .{
        .name = "TDNFTransactionPlanRequestTraceRecordPackageJobRange",
        .visibility = .hidden,
    });
    @export(&requestTraceRecordNameJob, .{
        .name = "TDNFTransactionPlanRequestTraceRecordNameJob",
        .visibility = .hidden,
    });
    @export(&requestTraceRecordAllJob, .{
        .name = "TDNFTransactionPlanRequestTraceRecordAllJob",
        .visibility = .hidden,
    });
    @export(&requestTraceRecordCapabilityJob, .{
        .name = "TDNFTransactionPlanRequestTraceRecordCapabilityJob",
        .visibility = .hidden,
    });
    @export(&requestTraceRecordPolicies, .{
        .name = "TDNFTransactionPlanRequestTraceRecordPolicies",
        .visibility = .hidden,
    });
    @export(&requestTraceFinalize, .{
        .name = "TDNFTransactionPlanRequestTraceFinalize",
        .visibility = .hidden,
    });
    @export(&requestTraceGetView, .{
        .name = "TDNFTransactionPlanRequestTraceGetView",
        .visibility = .hidden,
    });
    @export(&requestTraceCaptureFactsCreate, .{
        .name = "TDNFTransactionPlanRequestTraceCaptureFactsCreate",
        .visibility = .hidden,
    });
    @export(&requestTraceCaptureFactsDestroy, .{
        .name = "TDNFTransactionPlanRequestTraceCaptureFactsDestroy",
        .visibility = .hidden,
    });
}

test "original requests and glob jobs retain stable provenance" {
    var trace = Trace.init(std.testing.allocator);
    defer trace.deinit();
    try trace.initResolve(alter.install, &.{
        "kernel-*",
        "/home/user/private-package.rpm",
    });
    try std.testing.expectEqual(@as(usize, 2), trace.requests.items.len);
    try std.testing.expectEqualStrings(
        "kernel-*",
        trace.requests.items[0].subject.?,
    );
    try std.testing.expect(trace.requests.items[1].subject == null);
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            trace.requests.items[1].id,
            "/home/user",
        ) == null,
    );
    var repeated = Trace.init(std.testing.allocator);
    defer repeated.deinit();
    try repeated.initResolve(alter.install, &.{
        "kernel-*",
        "/home/user/private-package.rpm",
    });
    for (trace.requests.items, repeated.requests.items) |left, right| {
        try std.testing.expectEqualStrings(left.id, right.id);
    }

    const goal = [_]i32{ 11, 12, 13 };
    try trace.recordGoalRange(
        &goal,
        0,
        2,
        alter.install,
        abi.request_reason.user,
        0,
    );
    try trace.recordGoalRange(
        &goal,
        2,
        3,
        alter.install,
        abi.request_reason.user,
        1,
    );
    const queue = [_]i32{ 0x101, 11, 0x101, 12, 0x101, 13 };
    try trace.commitGoal(11, alter.install, &queue, 0, 2);
    try trace.commitGoal(12, alter.install, &queue, 2, 4);
    try trace.commitGoal(13, alter.install, &queue, 4, 6);
    try trace.finalize(&queue, 0x400, 0x800);

    const view = trace.getView().?;
    try std.testing.expectEqual(@as(u32, 3), view.job_count);
    const jobs = view.jobs.?[0..view.job_count];
    try std.testing.expectEqual(@as(u32, 0), jobs[0].request_ref);
    try std.testing.expectEqual(@as(u32, 0), jobs[1].request_ref);
    try std.testing.expectEqual(@as(u32, 1), jobs[2].request_ref);
    const origins = view.queue_origins.?[0..view.queue_origin_count];
    for (origins, 0..) |origin, index| {
        try std.testing.expectEqual(@as(u32, @intCast(index)), origin.job_ref);
        try std.testing.expectEqual(
            @as(u32, @intCast(index)),
            origin.queue_pair_index,
        );
    }
}

test "erase update-all distro-sync downgrade and reinstall stay distinct" {
    inline for (.{
        .{ alter.erase, abi.job_action.erase },
        .{ alter.downgrade, abi.job_action.downgrade },
        .{ alter.reinstall, abi.job_action.reinstall },
    }) |entry| {
        var trace = Trace.init(std.testing.allocator);
        defer trace.deinit();
        try trace.initResolve(entry[0], &.{"pkg"});
        const goal = [_]i32{42};
        try trace.recordGoalRange(
            &goal,
            0,
            1,
            entry[0],
            abi.request_reason.user,
            0,
        );
        const queue = [_]i32{ 0x101, 42 };
        try trace.commitGoal(42, entry[0], &queue, 0, 2);
        try trace.finalize(&queue, 0x400, 0x800);
        try std.testing.expectEqual(
            entry[1],
            trace.getView().?.jobs.?[0].action,
        );
    }

    inline for (.{
        .{ alter.update_all, abi.job_action.update },
        .{ alter.distro_sync, abi.job_action.dist_sync },
    }) |entry| {
        var trace = Trace.init(std.testing.allocator);
        defer trace.deinit();
        try trace.initResolve(entry[0], &.{});
        try trace.recordAllJob(
            0,
            entry[1],
            0x202,
            0,
            abi.request_reason.user,
            0,
        );
        const queue = [_]i32{ 0x202, 0 };
        try trace.finalize(&queue, 0x400, 0x800);
        try std.testing.expectEqual(
            entry[1],
            trace.getView().?.jobs.?[0].action,
        );
    }
}

test "lock installonly protection cleanup retry and flags are exact" {
    var trace = Trace.init(std.testing.allocator);
    defer trace.deinit();
    try trace.initResolve(alter.erase, &.{"old"});
    try trace.recordPackageJob(
        0,
        abi.job_action.erase,
        10,
        0x101,
        0,
        abi.request_reason.user,
        0,
    );
    try trace.recordPackageJob(
        1,
        abi.job_action.user_installed,
        11,
        0x102,
        0,
        abi.request_reason.policy,
        abi.request_trace_no_request,
    );
    try trace.recordNameJob(
        2,
        abi.job_action.lock,
        "locked",
        0x103,
        0,
        abi.request_reason.policy,
        abi.request_trace_no_request,
    );
    try trace.recordNameJob(
        3,
        abi.job_action.multiversion,
        "kernel",
        0x104,
        0,
        abi.request_reason.policy,
        abi.request_trace_no_request,
    );
    try trace.recordPackageJob(
        4,
        abi.job_action.allow_uninstall,
        12,
        0x105,
        0,
        abi.request_reason.policy,
        abi.request_trace_no_request,
    );
    try trace.recordPackageJob(
        5,
        abi.job_action.erase,
        13,
        0x106,
        0,
        abi.request_reason.installonly_limit,
        abi.request_trace_no_request,
    );
    try trace.recordPackageJob(
        6,
        abi.job_action.erase,
        14,
        0x107,
        0,
        abi.request_reason.cleanup,
        abi.request_trace_no_request,
    );
    try trace.recordPolicies(
        &.{"debug-*"},
        &.{"kernel"},
        &.{"locked"},
        &.{"openssl=3"},
        &.{"tdnf"},
        true,
    );
    const queue = [_]i32{
        0xd01, 10,
        0xd02, 11,
        0x103, 0,
        0x104, 0,
        0x105, 12,
        0x106, 13,
        0x107, 14,
    };
    try trace.finalize(&queue, 0x400, 0x800);
    const view = trace.getView().?;
    const jobs = view.jobs.?[0..view.job_count];
    try std.testing.expectEqual(@as(u32, 0x101), jobs[0].raw_how);
    try std.testing.expectEqual(@as(u32, 0xd01), jobs[0].effective_how);
    try std.testing.expectEqual(
        abi.request_trace_flag.clean_deps |
            abi.request_trace_flag.force_best,
        jobs[0].effective_flags,
    );
    try std.testing.expectEqual(
        abi.request_reason.installonly_limit,
        jobs[5].reason,
    );
    try std.testing.expectEqual(abi.request_reason.cleanup, jobs[6].reason);
    try std.testing.expectEqual(@as(u32, 5), view.policy_fact_count);
    try std.testing.expectEqual(@as(u32, 1), view.allow_erasing);
}

test "history goal inputs receive deterministic owned requests" {
    var trace = Trace.init(std.testing.allocator);
    defer trace.deinit();
    const goal = [_]i32{ 40, 41 };
    try trace.recordHistoryGoal(
        "alpha-1.0-1.x86_64",
        abi.request_kind.install,
        abi.job_action.install,
        &goal,
        0,
        2,
    );
    const queue = [_]i32{ 0x101, 40, 0x101, 41 };
    try trace.commitGoal(40, alter.install, &queue, 0, 2);
    try trace.commitGoal(41, alter.install, &queue, 2, 4);
    try trace.finalize(&queue, 0, 0);
    const view = trace.getView().?;
    try std.testing.expectEqual(@as(u32, 1), view.request_count);
    try std.testing.expectEqual(@as(u32, 2), view.job_count);
    const requests = view.requests.?[0..view.request_count];
    try std.testing.expectEqualStrings(
        "alpha-1.0-1.x86_64",
        requests[0].subject.data.?[0..requests[0].subject.length],
    );
    try std.testing.expectEqual(@as(u32, 0), view.jobs.?[1].request_ref);
}

test "private C trace API publishes borrowed view and remapped facts" {
    const subjects = [_]?[*:0]const u8{
        "alpha",
        "/srv/private/alpha.rpm",
    };
    const trace = requestTraceCreate(alter.install, &subjects, subjects.len) orelse return error.OutOfMemory;
    defer requestTraceDestroy(trace);
    const goal = [_]i32{ 70, 71 };
    requestTraceRecordGoalRange(
        trace,
        &goal,
        0,
        1,
        alter.install,
        abi.request_reason.user,
        0,
    );
    requestTraceRecordGoalRange(
        trace,
        &goal,
        1,
        2,
        alter.install,
        abi.request_reason.user,
        1,
    );
    const queue = [_]i32{ 0x101, 70, 0x101, 71 };
    requestTraceCommitGoal(trace, 70, alter.install, &queue, 0, 2);
    requestTraceCommitGoal(trace, 71, alter.install, &queue, 2, 4);
    requestTraceFinalize(trace, &queue, queue.len, 0, 0);
    const view = requestTraceGetView(trace).?;
    try std.testing.expectEqual(@as(u32, 2), view.request_count);
    try std.testing.expectEqual(@as(u32, 0), view.requests.?[1].has_subject);

    const package_refs = [_]abi.RequestTracePackageRef{
        .{ .selection_id = 70, .package_ref = 4 },
        .{ .selection_id = 71, .package_ref = 5 },
    };
    var facts: ?*const abi.RequestTraceCaptureFacts = null;
    var owner: ?*CaptureFactsOwner = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        requestTraceCaptureFactsCreate(
            trace,
            &package_refs,
            package_refs.len,
            &facts,
            &owner,
        ),
    );
    defer requestTraceCaptureFactsDestroy(owner);
    try std.testing.expectEqual(@as(u32, 4), facts.?.jobs.?[0].selection_package_ref);
    try std.testing.expectEqual(@as(u32, 5), facts.?.jobs.?[1].selection_package_ref);
}

fn allocationFailureCase(allocator: Allocator) !void {
    var trace = Trace.init(allocator);
    defer trace.deinit();
    try trace.initResolve(alter.install, &.{ "alpha*", "local.rpm" });
    const goal = [_]i32{ 20, 21 };
    try trace.recordGoalRange(
        &goal,
        0,
        2,
        alter.install,
        abi.request_reason.user,
        0,
    );
    const queue = [_]i32{ 0x101, 20, 0x101, 21 };
    try trace.commitGoal(20, alter.install, &queue, 0, 2);
    try trace.commitGoal(21, alter.install, &queue, 2, 4);
    try trace.finalize(&queue, 0, 0);
    const refs = [_]abi.RequestTracePackageRef{
        .{ .selection_id = 20, .package_ref = 0 },
        .{ .selection_id = 21, .package_ref = 1 },
    };
    const owner = try CaptureFactsOwner.create(allocator, &trace, &refs);
    owner.destroy();
}

test "trace and capture fact ownership clean every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailureCase,
        .{},
    );
}
