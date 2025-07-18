const ssz = @import("ssz");
const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("@zeam/types");

pub const utils = @import("./utils.zig");
const transition = @import("./transition.zig");
const params = @import("@zeam/params");

const zeam_utils = @import("@zeam/utils");
const getLogger = zeam_utils.getLogger;

const MockChainData = struct {
    genesis_config: types.GenesisSpec,
    genesis_state: types.BeamState,
    blocks: []types.SignedBeamBlock,
    blockRoots: []types.Root,
    // what should be justified and finalzied post each of these blocks
    latestJustified: []types.Mini3SFCheckpoint,
    latestFinalized: []types.Mini3SFCheckpoint,
    latestHead: []types.Mini3SFCheckpoint,
    // did justification/finalization happen
    justification: []bool,
    finalization: []bool,
};

pub fn genMockChain(allocator: Allocator, numBlocks: usize, from_genesis: ?types.GenesisSpec) !MockChainData {
    const genesis_config = from_genesis orelse types.GenesisSpec{
        .genesis_time = 1234,
        .num_validators = 4,
    };

    const genesis_state = try utils.genGenesisState(allocator, genesis_config);
    var blockList = std.ArrayList(types.SignedBeamBlock).init(allocator);
    var blockRootList = std.ArrayList(types.Root).init(allocator);

    var justificationCPList = std.ArrayList(types.Mini3SFCheckpoint).init(allocator);
    var justificationList = std.ArrayList(bool).init(allocator);

    var finalizationCPList = std.ArrayList(types.Mini3SFCheckpoint).init(allocator);
    var finalizationList = std.ArrayList(bool).init(allocator);

    var headList = std.ArrayList(types.Mini3SFCheckpoint).init(allocator);

    // figure out a way to clone genesis_state
    var beam_state = try utils.genGenesisState(allocator, genesis_config);
    const genesis_block = try utils.genGenesisBlock(allocator, beam_state);

    var gen_signature: [48]u8 = undefined;
    _ = try std.fmt.hexToBytes(gen_signature[0..], utils.ZERO_HASH_48HEX);
    const gen_signed_block = types.SignedBeamBlock{
        .message = genesis_block,
        .signature = gen_signature,
    };
    var block_root: types.Root = undefined;
    try ssz.hashTreeRoot(types.BeamBlock, genesis_block, &block_root, allocator);

    try blockList.append(gen_signed_block);
    try blockRootList.append(block_root);

    var prev_block = genesis_block;

    // track latest justified and finalized for constructing votes
    var latest_justified: types.Mini3SFCheckpoint = .{ .root = block_root, .slot = genesis_block.slot };
    var latest_justified_prev = latest_justified;
    var latest_finalized = latest_justified;

    try justificationCPList.append(latest_justified);
    try justificationList.append(true);
    try finalizationCPList.append(latest_finalized);
    try finalizationList.append(true);

    // to easily track new justifications/finalizations for bunding in the response
    var prev_justified_root = latest_justified.root;
    var prev_finalized_root = latest_finalized.root;
    // head is genesis block itself
    var head_idx: usize = 0;
    try headList.append(.{ .root = block_root, .slot = head_idx });

    for (1..numBlocks) |slot| {
        var parent_root: [32]u8 = undefined;
        try ssz.hashTreeRoot(types.BeamBlock, prev_block, &parent_root, allocator);

        var state_root: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(state_root[0..], utils.ZERO_HASH_HEX);
        const timestamp = genesis_config.genesis_time + slot * params.SECONDS_PER_SLOT;
        var votes = std.ArrayList(types.Mini3SFVote).init(allocator);
        // 4 slot moving scenario can be applied over and over with finalization in 0
        switch (slot % 4) {
            // no votes on the first block of this
            1 => {
                head_idx = slot;
            },
            2 => {
                const slotVotes = [_]types.Mini3SFVote{
                    // val 0
                    .{ .validator_id = 0, .slot = slot - 1, .head = .{ .root = parent_root, .slot = slot - 1 }, .target = .{ .root = parent_root, .slot = slot - 1 }, .source = latest_justified },
                    // skip val1
                    // val2
                    .{ .validator_id = 2, .slot = slot - 1, .head = .{ .root = parent_root, .slot = slot - 1 }, .target = .{ .root = parent_root, .slot = slot - 1 }, .source = latest_justified },
                    // val3
                    .{ .validator_id = 3, .slot = slot - 1, .head = .{ .root = parent_root, .slot = slot - 1 }, .target = .{ .root = parent_root, .slot = slot - 1 }, .source = latest_justified },
                };
                for (slotVotes) |slotVote| {
                    try votes.append(slotVote);
                }

                head_idx = slot;
                // post these votes last_justified would be updated
                latest_justified_prev = latest_justified;
                latest_justified = .{ .root = parent_root, .slot = slot - 1 };
            },
            3 => {
                const slotVotes = [_]types.Mini3SFVote{
                    // skip val0
                    // val 1
                    .{ .validator_id = 1, .slot = slot - 1, .head = .{ .root = parent_root, .slot = slot - 1 }, .target = .{ .root = parent_root, .slot = slot - 1 }, .source = latest_justified },
                    // val2
                    .{ .validator_id = 2, .slot = slot - 1, .head = .{ .root = parent_root, .slot = slot - 1 }, .target = .{ .root = parent_root, .slot = slot - 1 }, .source = latest_justified },
                    // val3
                    .{ .validator_id = 3, .slot = slot - 1, .head = .{ .root = parent_root, .slot = slot - 1 }, .target = .{ .root = parent_root, .slot = slot - 1 }, .source = latest_justified },
                };
                for (slotVotes) |slotVote| {
                    try votes.append(slotVote);
                }

                head_idx = slot;
                // post these votes last justified and finalized would be updated
                latest_finalized = latest_justified;
                latest_justified_prev = latest_justified;
                latest_justified = .{ .root = parent_root, .slot = slot - 1 };
            },
            0 => {
                const slotVotes = [_]types.Mini3SFVote{
                    // val 0
                    .{ .validator_id = 0, .slot = slot - 1, .head = .{ .root = parent_root, .slot = slot - 1 }, .target = .{ .root = parent_root, .slot = slot - 1 }, .source = latest_justified },
                    // skip val1
                    // skip val2
                    // skip val3
                };

                head_idx = slot;
                for (slotVotes) |slotVote| {
                    try votes.append(slotVote);
                }
            },
            else => unreachable,
        }

        var block = types.BeamBlock{
            .slot = slot,
            .proposer_index = 1,
            .parent_root = parent_root,
            .state_root = state_root,
            .body = types.BeamBlockBody{
                .execution_payload_header = .{ .timestamp = timestamp },
                .votes = try votes.toOwnedSlice(),
            },
        };

        // prepare pre state to process block for that slot, may be rename prepare_pre_state
        try transition.process_slots(allocator, &beam_state, block.slot);
        // process block and modify the pre state to post state
        var logger = getLogger();
        logger.setActiveLevel(.info);
        try transition.process_block(allocator, &beam_state, block, &logger);

        // extract the post state root
        try ssz.hashTreeRoot(types.BeamState, beam_state, &state_root, allocator);
        block.state_root = state_root;
        try ssz.hashTreeRoot(types.BeamBlock, block, &block_root, allocator);

        // generate the signed beam block and add to block list
        var signature: [48]u8 = undefined;
        _ = try std.fmt.hexToBytes(signature[0..], utils.ZERO_HASH_48HEX);
        const signed_block = types.SignedBeamBlock{
            .message = block,
            .signature = signature,
        };
        try blockList.append(signed_block);
        try blockRootList.append(block_root);

        const head = types.Mini3SFCheckpoint{ .root = blockRootList.items[head_idx], .slot = head_idx };
        try headList.append(head);

        try justificationCPList.append(latest_justified);
        const justification = !std.mem.eql(u8, &prev_justified_root, &latest_justified.root);
        try justificationList.append(justification);
        prev_justified_root = latest_justified.root;

        try finalizationCPList.append(latest_finalized);
        const finalization = !std.mem.eql(u8, &prev_finalized_root, &latest_finalized.root);
        try finalizationList.append(finalization);
        prev_finalized_root = latest_finalized.root;

        // now we are ready for next round as the beam_state is not this blocks post state
        prev_block = block;
    }

    return MockChainData{
        .genesis_config = genesis_config,
        .genesis_state = genesis_state,
        .blocks = blockList.items,
        .blockRoots = blockRootList.items,
        .latestJustified = justificationCPList.items,
        .latestFinalized = finalizationCPList.items,
        .latestHead = headList.items,
        .justification = justificationList.items,
        .finalization = finalizationList.items,
    };
}
