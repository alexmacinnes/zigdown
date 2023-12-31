const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak)
            std.debug.print("MEM LEAK", .{});
    }

    try explainSolutionArr(alloc, 5, [_]u32{ 1, 2, 3, 4, 5, 6 });
    try explainSolutionArr(alloc, 119, [_]u32{ 1, 2, 3, 4, 5, 6 });

    std.debug.print("https://www.youtube.com/watch?v=pfa3MHLLSWI\n", .{});
    try explainSolutionArr(alloc, 952, [_]u32{ 25, 50, 75, 100, 3, 6 });

    return;
}

const CalcNode = struct { value: u32, op: ?u8 = null, leftNode: ?*const CalcNode = null, rightNode: ?*const CalcNode = null };

const CalcNodeList = struct { nodes: []*const CalcNode };

const SolveResult = struct { solutionNode: ?*const CalcNode, newNodeLists: ?[]*const CalcNodeList };

fn explainSolutionArr(alloc: std.mem.Allocator, target: u32, numbers: [6]u32) !void {
    try explainSolution(alloc, target, numbers[0..]);
    return;
}

fn explainSolution(alloc: std.mem.Allocator, target: u32, numbers: []const u32) !void {
    const node = try solveNumbers(alloc, target, numbers);
    defer destroyCalcNode(alloc, node);

    std.debug.print("{d} from {any}:\n", .{ target, numbers });

    if (node == null) {
        std.debug.print("  No solution\n", .{});
    } else {
        const n = node.?;
        if (n.op == null) {
            std.debug.print("  {d} = {d}\n", .{ n.value, target });
        } else {
            explainNode(n);
        }
    }
    std.debug.print("\n", .{});
    return;
}

fn explainNode(node: *const CalcNode) void {
    if (node.op != null) {
        explainNode(node.leftNode.?);
        explainNode(node.rightNode.?);

        std.debug.print("  {d} {c} {d} = {d}\n", .{ node.leftNode.?.*.value, node.op.?, node.rightNode.?.*.value, node.value });
    }
    return;
}

fn initCalcNode_Simple(alloc: std.mem.Allocator, value: u32) !*const CalcNode {
    return try createInit(alloc, CalcNode, .{ .value = value });
}

fn initCalcNode_Full(alloc: std.mem.Allocator, value: u32, op: u8, leftNode: *const CalcNode, rightNode: *const CalcNode) !*const CalcNode {
    return try createInit(alloc, CalcNode, .{ .value = value, .op = op, .leftNode = leftNode, .rightNode = rightNode });
}

fn initCalcNode_Copy(alloc: std.mem.Allocator, other: ?*const CalcNode) !?*const CalcNode {
    if (other == null) {
        return null;
    }

    const left = try initCalcNode_Copy(alloc, other.?.*.leftNode);
    const right = try initCalcNode_Copy(alloc, other.?.*.rightNode);

    const copy = try createInit(alloc, CalcNode, .{ .value = other.?.*.value, .op = other.?.*.op, .leftNode = left, .rightNode = right });

    return copy;
}

fn solveNumbers(alloc: std.mem.Allocator, target: u32, numbers: []const u32) !?*const CalcNode {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var arenaAlloc = arena.allocator();

    var nodes = std.ArrayList(*const CalcNode).init(arenaAlloc);
    for (numbers) |n| {
        // no prcoessing needed - return solution node, using the external allocator
        if (n == target) {
            return try initCalcNode_Simple(alloc, n);
        }

        // other nodes created with arena allocator - to be cleaned up on function exit
        const node = try initCalcNode_Simple(arenaAlloc, n);
        try nodes.append(node);
    }

    var nodeList = try createCalcNodeList(arenaAlloc, nodes.items);
    var nodeLists = std.ArrayList(*const CalcNodeList).init(arenaAlloc);
    try nodeLists.append(nodeList);

    const solution = try solveNodeLists(arenaAlloc, target, nodeLists.items);
    if (solution != null) {
        // solution found, copy node onto external allocator
        return try initCalcNode_Copy(alloc, solution.?);
    }

    // no solution found
    return null;
}

fn solveNodeLists(alloc: std.mem.Allocator, target: u32, nodeLists: []*const CalcNodeList) !?*const CalcNode {
    const len = nodeLists[0].nodes.len; // all will be same length
    if (len == 1) {
        return null;
    }

    var newNodeLists = std.ArrayList(*const CalcNodeList).init(alloc);

    for (nodeLists) |nl| {
        const solveResult = try solveSingleNodeList(alloc, target, nl);
        if (solveResult.solutionNode != null) {
            return solveResult.solutionNode;
        } else if (solveResult.newNodeLists != null) {
            try newNodeLists.appendSlice(solveResult.newNodeLists.?);
        }
    }

    const nextGenerationNodeLists = newNodeLists.items;
    if (nextGenerationNodeLists.len == 0) {
        return null;
    }

    return solveNodeLists(alloc, target, nextGenerationNodeLists);
}

inline fn solveSingleNodeList(alloc: std.mem.Allocator, target: u32, nodeList: *const CalcNodeList) !SolveResult {
    const len = nodeList.nodes.len; // all will be same length

    var newNodeLists = std.ArrayList(*const CalcNodeList).init(alloc);

    for (0..(len - 1)) |left| {
        for ((left + 1)..len) |right| {

            // all possible values achieved with the left and right nodes
            const permutations = try permuteNodes(alloc, nodeList.nodes[left], nodeList.nodes[right]);
            for (permutations) |p| {
                if (p.value == target) {
                    return SolveResult{ .solutionNode = p, .newNodeLists = null }; // we have found a solution, stop further processing
                }
            }

            if (len == 2) { // no solution found, and no further possible node lists to examine
                return SolveResult{ .solutionNode = null, .newNodeLists = null };
            }

            var remainingNodes = try getRemainingNodes(alloc, left, right, len, nodeList.nodes);
            for (permutations) |p| {
                var newNodes = std.ArrayList(*const CalcNode).init(alloc);
                try newNodes.append(p);
                try newNodes.appendSlice(remainingNodes);

                const newNodeList = try createCalcNodeList(alloc, newNodes.items);
                try newNodeLists.append(newNodeList);
            }
        }
    }

    return SolveResult{ .solutionNode = null, .newNodeLists = newNodeLists.items }; // no solution found, but we have a new set of CalcNodeLists to be processed
}

inline fn getRemainingNodes(alloc: std.mem.Allocator, left: u64, right: u64, len: u64, nodes: []*const CalcNode) ![]*const CalcNode {
    var remainingNodes = std.ArrayList(*const CalcNode).init(alloc);
    if (left > 0) {
        try remainingNodes.appendSlice(nodes[0..left]);
    }
    if (right - left > 1) {
        try remainingNodes.appendSlice(nodes[left + 1 .. right]);
    }
    if (right < len - 1) {
        try remainingNodes.appendSlice(nodes[right + 1 .. len]);
    }
    return remainingNodes.items;
}

fn useArena(alloc: std.mem.Allocator) !?*const CalcNode {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var arenaAlloc = arena.allocator();

    const nLeft = try createInit(arenaAlloc, CalcNode, .{ .value = 12 });
    const nRight = try createInit(arenaAlloc, CalcNode, .{ .value = 34 });
    const n = try createInit(arenaAlloc, CalcNode, .{ .value = 56, .op = '+', .leftNode = nLeft, .rightNode = nRight });

    std.debug.print("gfgggggggg, {d}!\n", .{n.value});
    std.debug.print("gfgggggggg, {d}!\n", .{n.rightNode.?.*.value});

    const nCopy = try initCalcNode_Copy(alloc, n);
    return nCopy;
}

fn createInit(alloc: std.mem.Allocator, comptime T: type, props: anytype) !*T {
    const new = try alloc.create(T);
    new.* = props;
    return new;
}

fn createCalcNodeList(alloc: std.mem.Allocator, nodes: []*const CalcNode) !*const CalcNodeList {
    const result = try createInit(alloc, CalcNodeList, .{ .nodes = nodes });
    return result;
}

fn destroyCalcNode(alloc: std.mem.Allocator, node: ?*const CalcNode) void {
    if (node) |n| {
        destroyCalcNode(alloc, n.leftNode);
        destroyCalcNode(alloc, n.rightNode);
        alloc.destroy(n);
    }
}

fn permuteNodes(alloc: std.mem.Allocator, nodeA: *const CalcNode, nodeB: *const CalcNode) ![]*const CalcNode {
    var result = std.ArrayList(*const CalcNode).init(alloc);

    var hi: *const CalcNode = undefined;
    var lo: *const CalcNode = undefined;

    if (nodeA.*.value >= nodeB.*.value) {
        hi = nodeA;
        lo = nodeB;
    } else {
        hi = nodeB;
        lo = nodeA;
    }

    const plus = try initCalcNode_Full(alloc, hi.*.value + lo.*.value, '+', hi, lo);
    try result.append(plus);

    if (hi.*.value != lo.*.value) {
        const minus = try initCalcNode_Full(alloc, hi.*.value - lo.*.value, '-', hi, lo);
        try result.append(minus);
    }

    if (hi.*.value != 1 and lo.*.value != 1) {
        const multiply = try initCalcNode_Full(alloc, lo.*.value * hi.*.value, '*', hi, lo);
        try result.append(multiply);

        const factor = @divFloor(hi.*.value, lo.*.value);
        if ((factor * lo.*.value) == hi.*.value) {
            const divide = try initCalcNode_Full(alloc, factor, '/', hi, lo);
            try result.append(divide);
        }
    }

    return result.items;
}
