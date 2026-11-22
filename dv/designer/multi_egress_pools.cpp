#include "Vtm_resource_pools.h"
#include "verilated.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

namespace {
constexpr int ports = POOL_PROFILE == 0 ? 4 : 2;
constexpr int cells = POOL_PROFILE == 0 ? 1024 : 16;
constexpr int descriptors = POOL_PROFILE == 0 ? 256 : 8;
constexpr int queues = 4 * ports;
constexpr int count_width = POOL_PROFILE == 0 ? 11 : 5;
constexpr int cell_width = POOL_PROFILE == 0 ? 10 : 4;
constexpr int desc_width = POOL_PROFILE == 0 ? 8 : 3;
constexpr int queue_width = POOL_PROFILE == 0 ? 4 : 3;
constexpr int max_frame_cells = POOL_PROFILE == 0 ? 24 : 3;

void check(bool ok, const char* detector) {
    if (!ok) throw std::runtime_error(detector);
}

struct Random {
    uint32_t state;

    uint32_t next() {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        return state;
    }

    int below(int limit) { return static_cast<int>(next() % static_cast<uint32_t>(limit)); }
};

struct Request {
    int ingress = -1;
    int queue = 0;
    int count = 0;
    bool first_beat_abort = false;
};

struct Retirement {
    int token = 0;
    int address = 0;
    int descriptor = 0;
    bool final = false;
};

struct Cleanup {
    int token = 0;
    int address = 0;
    int released = 0;
    bool has_cell = false;
    bool done = false;
};

struct Batch {
    std::array<Request, ports> reserve{};
    std::array<Retirement, ports> tx{};
    Cleanup cleanup;
    int write = 0;

    Batch& offer(int lane, int ingress, int queue, int count, bool abort = false) {
        reserve.at(lane) = {ingress, queue, count, abort};
        return *this;
    }
};

struct Frame {
    int ingress;
    int queue;
    int count;
    int desc;
    int birth;
    int abort_edge;
    int tx_ready = 0;
    int retired = 0;
    std::vector<int> assigned;

    // A repeated packet tag is intentional. The scoreboard keys by its epoch-local token.
    static constexpr int tag = 0x1357;
    bool aborting() const { return abort_edge >= 0; }
};

struct Counts {
    int f = cells;
    int u = cells;
    int d = descriptors;
    int r = 0;
    std::array<int, queues> held{};
};

struct Result {
    std::array<int, ports> tokens{};
    int address = -1;
};

template<class Packed>
int field(const Packed& words, int lsb, int width) {
    uint64_t value;
    if constexpr (std::is_integral_v<Packed>) {
        value = static_cast<uint64_t>(words) >> lsb;
    } else {
        const int word = lsb / 32;
        value = words[word] >> (lsb % 32);
        if (lsb % 32 + width > 32)
            value |= static_cast<uint64_t>(words[word + 1]) << (32 - lsb % 32);
    }
    return static_cast<int>(value & ((uint64_t{1} << width) - 1));
}

uint64_t insert(uint64_t word, int lane, int width, int value) {
    const auto mask = (uint64_t{1} << width) - 1;
    const int shift = lane * width;
    return (word & ~(mask << shift)) | ((static_cast<uint64_t>(value) & mask) << shift);
}

template<class Probe>
void intended_failure(const char* detector, Probe probe) {
    try {
        probe();
    } catch (const std::runtime_error& failure) {
        check(std::string(failure.what()) == detector, "wrong_detector");
        std::cout << "EXPECTED " << detector << '\n';
        return;
    }
    throw std::runtime_error(std::string("undetected_") + detector);
}

class Bench {
public:
    explicit Bench(uint32_t seed) : random{seed}, noise{seed ^ 0xc49f18adu} { reset(); }

    void reset() {
        const Counts abandoned = expected();
        // Offer activity throughout reset and through the first released edge.
        Batch activity;
        activity.offer(0, 0, 0, 1);
        activity.write = 1;
        activity.tx[ports - 1] = {1, 0, 0, true};
        activity.cleanup = {1, 0, 1, true, true};
        drive(activity, false);
        dut.rst_n = 1;
        dut.eval();
        dut.rst_n = 0;
        dut.eval();
        for (int i = 0; i < 2; ++i) {
            check(!dut.ready && !dut.grant && !dut.write_accept, "reset_acceptance");
            pulse();
        }
        owners.clear();
        cell_owner.fill(0);
        desc_owner.fill(0);
        ingress_ready.fill(0);
        tx_owner.fill(0);
        tx_ready.fill(0);
        dut.rst_n = 1;
        dut.eval();
        check(!dut.ready && !dut.grant && !dut.write_accept, "initialization_acceptance");
        pulse();
        check(dut.ready, "initialized");
        compare(observed(), expected());
        if (abandoned.f != cells || abandoned.u != cells || abandoned.d != descriptors) {
            print_counts("reset pre", abandoned);
            print_counts("reset post", observed());
        }
    }

    Result step(const Batch& batch = {}) {
        const Counts old = expected();
        validate_returns(batch);
        drive(batch);
        check(dut.ready, "ready_during_run");

        Result result;
        int remaining = old.u;
        int unused_desc = old.d;
        int grants = 0;
        std::array<bool, ports> offered_ingress{};
        for (int lane = 0; lane < ports; ++lane) {
            const Request& request = batch.reserve[lane];
            const bool present = request.ingress >= 0;
            if (present) {
                check(!offered_ingress[request.ingress] && ingress_available(request.ingress),
                      "ingress_eligibility");
                offered_ingress[request.ingress] = true;
            }
            const bool accept = present && request.count <= remaining && unused_desc > 0;
            check(bool(dut.grant & (1 << lane)) == accept, "old_prefix_grant");
            if (!accept) continue;
            const int desc = field(dut.grant_desc, lane * desc_width, desc_width);
            descriptor_zero += desc == 0;
            descriptor_high += desc == descriptors - 1;
            check(desc_owner.at(desc) == 0, "old_free_descriptor");
            check(request.count > 0 && request.count <= max_frame_cells, "frame_length");
            remaining -= request.count;
            --unused_desc;
            ++grants;
            const int token = next_token++;
            desc_owner[desc] = token;
            owners.emplace(token, Frame{request.ingress, request.queue, request.count, desc,
                                        edge, request.first_beat_abort ? edge : -1, 0, 0, {}});
            ingress_ready[request.ingress] = edge + 8 * request.count;
            result.tokens[lane] = token;
        }

        check(bool(dut.write_accept) == (batch.write != 0), "materialization_acceptance");
        if (batch.write) {
            check(can_write(batch.write) && old.r > 0, "old_staged_reservation");
            result.address = dut.write_id;
            cell_zero += result.address == 0;
            cell_high += result.address == cells - 1;
            check_old_cell(result.address);
            cell_owner[result.address] = batch.write;
            Frame& frame = owners.at(batch.write);
            frame.assigned.push_back(result.address);
            if (static_cast<int>(frame.assigned.size()) == frame.count) frame.tx_ready = edge + 16;
            ++writes;
        }

        int retirements = 0;
        for (int lane = 0; lane < ports; ++lane) {
            const Retirement& tx = batch.tx[lane];
            if (!tx.token) continue;
            Frame& frame = owners.at(tx.token);
            cell_owner[tx.address] = 0;
            tx_ready[lane] = edge + 8;
            ++retirements;
            if (tx.final) {
                tx_owner[lane] = 0;
                release_desc(tx.token);
            } else {
                tx_owner[lane] = tx.token;
                ++frame.retired;
            }
        }

        if (batch.cleanup.token) {
            Frame& frame = owners.at(batch.cleanup.token);
            if (batch.cleanup.has_cell) {
                cell_owner[batch.cleanup.address] = 0;
                frame.assigned.pop_back();
            }
            if (batch.cleanup.done) {
                ingress_ready[frame.ingress] = std::max(ingress_ready[frame.ingress], edge + 1);
                release_desc(batch.cleanup.token);
                ++cleanups;
            } else {
                ++partial_cleanups;
            }
        }

        pulse();
        const Counts after = observed();
        try {
            compare(after, expected());
        } catch (const std::runtime_error&) {
            print_counts("failed edge pre", old);
            print_counts("failed edge post", after);
            throw;
        }
        if (grants || batch.write || retirements || batch.cleanup.token) ++active_edges;
        total_grants += grants;
        total_returns += retirements;
        if (old.d <= 2 && (batch.cleanup.done || retirements)) ++desc_pressure;
        if (old.u == 0 && (batch.cleanup.done || retirements)) ++credit_pressure;
        if (retirements && retirements < ports) ++sparse_returns;
        if (retirements + bool(batch.cleanup.token) > 1) ++parallel_returns;
        if (grants && (retirements || batch.cleanup.token)) ++overlap;
        digest = digest * 1099511628211ull + static_cast<uint64_t>(
            after.u + 31 * after.f + 997 * after.d + 17 * grants + result.address + 1);
        return result;
    }

    void idle(int edges) {
        for (int i = 0; i < edges; ++i) step();
    }

    int reserve(int ingress, int queue, int count, bool abort = false) {
        const auto result = step(Batch{}.offer(0, ingress, queue, count, abort));
        check(result.tokens[0] != 0, "directed_reservation");
        return result.tokens[0];
    }

    int size(int token) const { return static_cast<int>(owners.at(token).assigned.size()); }

    void materialize(int token, int count) {
        for (int i = 0; i < count; ++i) {
            while (!can_write(token)) step();
            Batch batch;
            batch.write = token;
            step(batch);
        }
    }

    void mark_abort(int token) {
        Frame& frame = owners.at(token);
        check(!frame.aborting() && size(token) < frame.count, "legal_abort_mark");
        frame.abort_edge = edge;
        step();
    }

    Retirement tx(int token) const {
        const Frame& frame = owners.at(token);
        return {token, frame.assigned.at(frame.retired), frame.desc, frame.retired + 1 == frame.count};
    }

    Cleanup cleanup(int token) const {
        const Frame& frame = owners.at(token);
        const bool done = size(token) <= 1;
        return {token, size(token) ? frame.assigned.back() : 0, done ? frame.count : 0,
                size(token) != 0, done};
    }

    void check_old_cell(int address) const {
        check(cell_owner.at(address) == 0, "old_free_cell");
    }

    int last_free_cell() const {
        check(std::count(cell_owner.begin(), cell_owner.end(), 0) == 1, "one_old_free_cell");
        return static_cast<int>(std::find(cell_owner.begin(), cell_owner.end(), 0) - cell_owner.begin());
    }

    void check_cell_extremes() const {
        check(cell_zero && cell_high, "cell_ID_extremes");
    }

    void check_descriptor_extremes() const {
        check(descriptor_zero && descriptor_high, "descriptor_ID_extremes");
    }

    int descriptor(int token) const { return owners.at(token).desc; }

    void validate_returns(const Batch& batch) const {
        std::array<bool, cells> returning_cells{};
        std::array<bool, descriptors> returning_desc{};
        const auto claim = [&](int address) {
            check(!returning_cells.at(address), "duplicate_cell");
            check(cell_owner.at(address) != 0, "already_free_cell");
            returning_cells[address] = true;
        };
        const auto desc = [&](int id, int token) {
            check(!returning_desc.at(id), "duplicate_descriptor");
            check(desc_owner.at(id) != 0, "already_free_descriptor");
            check(desc_owner.at(id) == token, "current_descriptor_owner");
            returning_desc[id] = true;
        };

        for (int lane = 0; lane < ports; ++lane) {
            const Retirement& tx_return = batch.tx[lane];
            if (!tx_return.token) continue;
            claim(tx_return.address);
            check(cell_owner.at(tx_return.address) == tx_return.token, "current_owner");
            check(can_retire(tx_return.token, lane) && tx_return.address == tx(tx_return.token).address,
                  "legal_tx_retirement");
            check(tx_return.final == tx(tx_return.token).final, "real_final_retirement");
            if (tx_return.final) desc(tx_return.descriptor, tx_return.token);
        }

        const Cleanup& reclaim = batch.cleanup;
        if (reclaim.token) {
            if (reclaim.has_cell) {
                claim(reclaim.address);
                check(cell_owner.at(reclaim.address) == reclaim.token, "current_owner");
            }
            const Frame& frame = owners.at(reclaim.token);
            check(frame.aborting() && edge > frame.abort_edge, "legal_cleanup_edge");
            const auto legal = cleanup(reclaim.token);
            check(legal.has_cell == reclaim.has_cell && legal.address == reclaim.address &&
                  legal.done == reclaim.done && legal.released == reclaim.released, "cleanup_delta");
            if (reclaim.done) desc(frame.desc, reclaim.token);
        }
    }

    void blocked_write() {
        Batch invalid;
        invalid.write = 1;
        drive(invalid);
        check(!dut.write_accept, "empty_cell_pool_rejected_write");
        std::cout << "EXPECTED empty_cell_pool_rejected_write\n";
        // Keep the corrupt offer present for an edge, and require an unchanged pool.
        const auto old = observed();
        pulse();
        compare(observed(), old);
    }

    bool ingress_available(int ingress) const {
        if (edge < ingress_ready[ingress]) return false;
        int staged = 0;
        for (const auto& [token, frame] : owners) {
            if (frame.ingress != ingress) continue;
            if (frame.aborting()) return false;
            staged += frame.count - size(token);
        }
        return staged < 4;
    }

    bool can_write(int token) const {
        const auto& frame = owners.at(token);
        if (frame.aborting() || size(token) == frame.count ||
            edge < frame.birth + 8 * (size(token) + 1)) return false;
        for (auto older = owners.begin(); older->first != token; ++older) {
            const auto& old = older->second;
            if (old.ingress == frame.ingress && !old.aborting() && size(older->first) < old.count)
                return false;
        }
        return true;
    }

    bool can_retire(int token, int lane) const {
        const auto& frame = owners.at(token);
        return !frame.aborting() && frame.queue / 4 == lane && size(token) == frame.count &&
               edge >= frame.tx_ready && edge >= tx_ready[lane] &&
               (tx_owner[lane] == 0 || tx_owner[lane] == token);
    }

    void drain() {
        const int first_edge = edge;
        while (!owners.empty()) {
            Batch batch;
            for (const auto& [token, frame] : owners) {
                if (frame.aborting() && frame.abort_edge < edge && !batch.cleanup.token)
                    batch.cleanup = cleanup(token);
                if (!batch.write && can_write(token)) batch.write = token;
                const int lane = frame.queue / 4;
                if (!batch.tx[lane].token && can_retire(token, lane)) batch.tx[lane] = tx(token);
            }
            step(batch);
            check(edge - first_edge < 20000, "bounded_drain");
        }
        check(std::all_of(cell_owner.begin(), cell_owner.end(), [](int id) { return !id; }) &&
              std::all_of(desc_owner.begin(), desc_owner.end(), [](int id) { return !id; }), "owner_drain");
        compare(observed(), Counts{});
    }

    void random_sequence() {
        int deadline = edge + 25000;
        const int first_active = active_edges;
        while (active_edges - first_active < 1024) {
            Batch batch;
            const int phase = (edge / 160) % 4;
            // Advance malformed frames before offering any new ingress headers.
            // A three-cell frame can have two assigned cells before its last beat.
            for (auto& [token, frame] : owners) {
                if (!frame.aborting() && size(token) > 0 && size(token) < frame.count &&
                    edge < frame.birth + 8 * frame.count && random.below(80) == 0)
                    frame.abort_edge = edge;
            }
            const int cursor = random.below(ports);
            for (int lane = 0; lane < ports; ++lane) {
                const int ingress = (cursor + lane) % ports;
                if (ingress_available(ingress) && random.below(4) != 0)
                    batch.offer(lane, ingress, random.below(queues), 1 + random.below(max_frame_cells),
                                random.below(10) == 0);
            }

            int write_candidates = 0;
            int cleanup_candidates = 0;
            for (const auto& [token, frame] : owners) {
                if (can_write(token) && random.below(++write_candidates) == 0) batch.write = token;
                if (frame.aborting() && frame.abort_edge < edge &&
                    random.below(++cleanup_candidates) == 0 && phase != 0)
                    batch.cleanup = cleanup(token);
                const int lane = frame.queue / 4;
                if (!batch.tx[lane].token && can_retire(token, lane) &&
                    phase != 0 && random.below(4) < phase)
                    batch.tx[lane] = tx(token);
            }
            step(batch);
            check(edge < deadline, "active_sequence_bound");
        }
        std::cout << "RANDOM_ACTIVE " << active_edges - first_active << '\n';
        std::cout << "RANDOM_TRIGGERS sparse=" << sparse_returns << " cleanup=" << cleanups
                  << " partial=" << partial_cleanups << " overlap=" << overlap
                  << " simultaneous=" << parallel_returns << " u_pressure=" << credit_pressure << '\n';
        check(sparse_returns && cleanups && partial_cleanups && overlap && parallel_returns && credit_pressure,
              "random_trigger_coverage");
        print_counts("random pre-drain", observed());
        drain();
    }

    void witness(const char* name, int f, int u, int d, int r) const {
        const auto counts = observed();
        check(counts.f == f && counts.u == u && counts.d == d && counts.r == r, name);
        print_counts(name, counts);
    }

    void wrong_delta() const {
        compare(observed(), expected());
        auto corrupt = observed();
        ++corrupt.held[0];
        intended_failure("merged_queue_delta", [&] { compare(corrupt, expected()); });
    }

    void summary() const {
        print_counts("drained", observed());
        std::cout << "TOTAL edge=" << edge << " active=" << active_edges << " grants=" << total_grants
                  << " write=" << writes << " tx=" << total_returns << " cleanup=" << cleanups
                  << " partial=" << partial_cleanups << " sparse=" << sparse_returns
                  << " overlap=" << overlap << " simultaneous=" << parallel_returns
                  << " d_pressure=" << desc_pressure << " u_pressure=" << credit_pressure
                  << " cell_zero=" << cell_zero << " cell_high=" << cell_high
                  << " desc_zero=" << descriptor_zero << " desc_high=" << descriptor_high
                  << " digest=" << digest << '\n';
    }

    Random random;
    int edge = 0;

private:
    Vtm_resource_pools dut;
    Random noise;
    std::map<int, Frame> owners;
    std::array<int, cells> cell_owner{};
    std::array<int, descriptors> desc_owner{};
    std::array<int, ports> ingress_ready{}, tx_owner{}, tx_ready{};
    int next_token = 1;
    int active_edges = 0, total_grants = 0, writes = 0, total_returns = 0;
    int cleanups = 0, partial_cleanups = 0, sparse_returns = 0, overlap = 0;
    int desc_pressure = 0, credit_pressure = 0, parallel_returns = 0;
    int cell_zero = 0, cell_high = 0, descriptor_zero = 0, descriptor_high = 0;
    uint64_t digest = 0;

    void release_desc(int token) {
        desc_owner[owners.at(token).desc] = 0;
        owners.erase(token);
    }

    void pulse() {
        dut.clk = 1;
        dut.eval();
        dut.clk = 0;
        dut.eval();
        ++edge;
    }

    void drive(const Batch& batch, bool vary_absent = true) {
        const auto filler = [&](int width) {
            return vary_absent ? noise.next() & ((uint64_t{1} << width) - 1) : 0;
        };
        dut.reserve_offer = 0;
        dut.reserve_cells = 0;
        dut.reserve_qid = 0;
        dut.tx_present = 0;
        dut.tx_final = filler(ports);
        dut.tx_cell = 0;
        dut.tx_qid = 0;
        dut.tx_desc = 0;
        dut.write_offer = batch.write != 0;
        for (int lane = 0; lane < ports; ++lane) {
            const auto& reserve = batch.reserve[lane];
            const bool offered = reserve.ingress >= 0;
            if (offered) dut.reserve_offer |= 1 << lane;
            dut.reserve_cells = insert(dut.reserve_cells, lane, count_width,
                                       offered ? reserve.count : filler(count_width));
            dut.reserve_qid = insert(dut.reserve_qid, lane, queue_width,
                                     offered ? reserve.queue : filler(queue_width));
            const auto& tx = batch.tx[lane];
            const bool returning = tx.token != 0;
            if (returning) {
                dut.tx_present |= 1 << lane;
                dut.tx_final = insert(dut.tx_final, lane, 1, tx.final);
            }
            dut.tx_cell = insert(dut.tx_cell, lane, cell_width, returning ? tx.address : filler(cell_width));
            dut.tx_qid = insert(dut.tx_qid, lane, queue_width,
                                returning && vary_absent ? owners.at(tx.token).queue : filler(queue_width));
            dut.tx_desc = insert(dut.tx_desc, lane, desc_width,
                                 returning && tx.final ? tx.descriptor : filler(desc_width));
        }

        const auto& cleanup = batch.cleanup;
        dut.cleanup_present = cleanup.token != 0;
        dut.cleanup_done = cleanup.token ? cleanup.done : filler(1);
        dut.cleanup_has_cell = cleanup.token ? cleanup.has_cell : filler(1);
        dut.cleanup_cell = cleanup.has_cell ? cleanup.address : filler(cell_width);
        dut.cleanup_qid = cleanup.token && vary_absent ? owners.at(cleanup.token).queue : filler(queue_width);
        dut.cleanup_desc = cleanup.done && vary_absent ? owners.at(cleanup.token).desc : filler(desc_width);
        dut.cleanup_released = cleanup.done ? cleanup.released : filler(count_width);
        dut.eval();
    }

    Counts observed() const {
        Counts state{dut.free_cells, dut.unreserved, dut.free_desc, dut.reserved_free, {}};
        for (int queue = 0; queue < queues; ++queue)
            state.held[queue] = field(dut.held, queue * count_width, count_width);
        return state;
    }

    Counts expected() const {
        Counts state;
        state.f = std::count(cell_owner.begin(), cell_owner.end(), 0);
        state.d = std::count(desc_owner.begin(), desc_owner.end(), 0);
        for (const auto& [token, frame] : owners) state.held[frame.queue] += frame.count - frame.retired;
        for (int count : state.held) state.u -= count;
        state.r = state.f - state.u;
        return state;
    }

    static void compare(const Counts& actual, const Counts& expected) {
        check(actual.f == expected.f && actual.u == expected.u && actual.d == expected.d &&
              actual.r == expected.r && actual.r >= 0, "resource_conservation");
        check(actual.held == expected.held, "merged_queue_delta");
    }

    static void print_counts(const char* name, const Counts& state) {
        std::cout << "STATE " << name << " F=" << state.f << " U=" << state.u
                  << " R=" << state.r << " D=" << state.d << " H=";
        for (int queue = 0; queue < queues; ++queue) {
            if (queue) std::cout << ',';
            std::cout << state.held[queue];
        }
        std::cout << '\n';
    }
};

void descriptor_scarcity(Bench& bench) {
    std::vector<int> tokens;
    for (int i = 0; i < descriptors; ++i) {
        const int token = bench.reserve(0, 0, 1);
        tokens.push_back(token);
        bench.materialize(token, 1);
    }
    bench.idle(16);
    bench.witness("D=0 pre", cells - descriptors, cells - descriptors, 0, 0);
    bench.check_descriptor_extremes();
    Batch batch;
    batch.offer(0, 0, 0, 1);
    batch.tx[0] = bench.tx(tokens[0]);
    check(!bench.step(batch).tokens[0], "D0_return_bypass");
    bench.witness("D=0 post", cells - descriptors + 1, cells - descriptors + 1, 1, 0);
    const int reused = bench.step(Batch{}.offer(0, 0, 0, 1)).tokens[0];
    check(reused && bench.descriptor(reused) == batch.tx[0].descriptor, "D_next_edge_reuse");
    bench.idle(15);

    Batch one;
    one.tx[0] = bench.tx(tokens[1]);
    bench.step(one);
    bench.idle(7);
    one.offer(0, 0, 0, 1).offer(1, 1, 0, 1);
    one.tx[0] = bench.tx(tokens[2]);
    bench.witness("D=1 pre", cells - descriptors + 2, cells - descriptors + 1, 1, 1);
    auto result = bench.step(one);
    check(result.tokens[0] && !result.tokens[1], "D1_one_rank");
    bench.witness("D=1 post", cells - descriptors + 3, cells - descriptors + 1, 1, 2);
    bench.idle(7);

    Batch two;
    two.tx[0] = bench.tx(tokens[3]);
    bench.step(two);
    bench.idle(7);
    two.tx[0] = bench.tx(tokens[4]);
    for (int lane = 0; lane < ports; ++lane) two.offer(lane, lane, 0, 1);
    bench.witness("D=2 pre", cells - descriptors + 4, cells - descriptors + 2, 2, 2);
    result = bench.step(two);
    for (int lane = 0; lane < ports; ++lane)
        check(bool(result.tokens[lane]) == (lane < 2), "D2_two_ranks");
    bench.witness("D=2 post", cells - descriptors + 5, cells - descriptors + 1, 1, 4);
    bench.drain();
}

std::pair<int, int> fill_cell_credit(Bench& bench, bool withhold_last) {
    int first = 0;
    int last = 0;
    for (int remaining = cells; remaining > 0;) {
        const int length = std::min(max_frame_cells, remaining);
        last = bench.reserve(0, 0, length);
        if (!first) first = last;
        remaining -= length;
        bench.materialize(last, length - (remaining == 0 && withhold_last));
    }
    return {first, last};
}

void cell_scarcity(Bench& bench) {
    auto [first, last] = fill_cell_credit(bench, true);
    bench.idle(24);
    const int unused_desc = descriptors - (cells + max_frame_cells - 1) / max_frame_cells;
    bench.witness("F=1 U=0 pre", 1, 0, unused_desc, 1);
    Batch batch;
    batch.write = last;
    batch.offer(0, 1, 0, 1);
    batch.tx[0] = bench.tx(first);
    intended_failure("old_free_cell", [&] { bench.check_old_cell(batch.tx[0].address); });
    const int last_free = bench.last_free_cell();
    const auto result = bench.step(batch);
    check(result.address == last_free && result.address != batch.tx[0].address && !result.tokens[0],
          "last_old_cell_without_credit_bypass");
    bench.witness("F=1 U=1 post", 1, 1, unused_desc, 0);

    // A failed large offer and a hole must consume neither credit nor an ID rank.
    Batch fit;
    fit.offer(0, 0, 0, 2).offer(ports - 1, 1, queues - 1, 1);
    auto granted = bench.step(fit);
    check(!granted.tokens[0] && granted.tokens[ports - 1], "resource_hole_keeps_rank");
    bench.witness("credit reused", 1, 0, unused_desc - 1, 1);
    bench.materialize(granted.tokens[ports - 1], 1);
    bench.witness("F=0 full occupancy", 0, 0, unused_desc - 1, 0);
    bench.check_cell_extremes();
    bench.blocked_write();
    bench.drain();
}

std::array<int, ports> make_tx_cohort(Bench& bench) {
    Batch reserve;
    for (int lane = 0; lane < ports; ++lane) reserve.offer(lane, lane, 4 * lane, 1);
    const auto tokens = bench.step(reserve).tokens;
    for (int token : tokens) bench.materialize(token, 1);
    bench.idle(16);
    return tokens;
}

void peak(Bench& bench) {
    const auto tx = make_tx_cohort(bench);
    const int staged = bench.reserve(0, 0, 1);
    bench.idle(8);
    Batch all;
    all.write = staged;
    for (int lane = 0; lane < ports; ++lane) {
        all.offer(lane, lane, lane < 2 ? 0 : 4 * lane + 1, 1);
        all.tx[lane] = bench.tx(tx[lane]);
    }
    bench.witness("peak grant pre", cells - ports, cells - ports - 1, descriptors - ports - 1, 1);
    for (int token : bench.step(all).tokens) check(token != 0, "peak_grants");
    bench.witness("peak grant post", cells - 1, cells - ports - 1, descriptors - ports - 1, ports);
    bench.wrong_delta();
    bench.drain();

    const auto all_tx = make_tx_cohort(bench);
    const int aborting = bench.reserve(ports - 1, queues - 1, 2);
    bench.materialize(aborting, 1);
    const int old_stage = bench.reserve(0, 0, 1);
    bench.mark_abort(aborting);
    bench.idle(8);
    Batch peak_return;
    peak_return.write = old_stage;
    peak_return.cleanup = bench.cleanup(aborting);
    for (int lane = 0; lane < ports; ++lane) {
        peak_return.tx[lane] = bench.tx(all_tx[lane]);
        if (lane < ports - 1) peak_return.offer(lane, lane, 4 * lane, 1);
    }
    check(!bench.ingress_available(ports - 1), "cleanup_ingress_ineligible");
    bench.witness("peak return pre", cells - ports - 1, cells - ports - 3, descriptors - ports - 2, 2);
    const auto grants = bench.step(peak_return).tokens;
    for (int lane = 0; lane < ports; ++lane)
        check(bool(grants[lane]) == (lane < ports - 1), "cleanup_parallel_ingresses");
    bench.witness("peak return post", cells - 1, cells - ports, descriptors - ports, ports - 1);
    check(bench.ingress_available(ports - 1), "cleanup_ingress_next_edge");
    bench.drain();

    const auto sparse = make_tx_cohort(bench);
    Batch high;
    high.tx[ports - 1] = bench.tx(sparse[ports - 1]);
    bench.witness("highest TX lane pre", cells - ports, cells - ports, descriptors - ports, 0);
    bench.step(high);
    bench.witness("highest TX lane post", cells - ports + 1, cells - ports + 1, descriptors - ports + 1, 0);
    bench.drain();
}

void abort_and_stall(Bench& bench) {
    const int aborting = bench.reserve(0, 0, 3);
    bench.materialize(aborting, 2);
    bench.mark_abort(aborting);
    Batch reclaim;
    reclaim.cleanup = bench.cleanup(aborting);
    check(!reclaim.cleanup.done, "nonfinal_cleanup_trigger");
    bench.witness("nonfinal cleanup pre", cells - 2, cells - 3, descriptors - 1, 1);
    bench.step(reclaim);
    bench.witness("nonfinal cleanup post", cells - 1, cells - 3, descriptors - 1, 2);
    reclaim.cleanup = bench.cleanup(aborting);
    check(reclaim.cleanup.done && reclaim.cleanup.released == 3, "final_cleanup_trigger");
    bench.step(reclaim);
    bench.witness("final cleanup post", cells, cells, descriptors, 0);

    while (!bench.ingress_available(0)) bench.idle(1);
    const int malformed = bench.reserve(0, queues - 1, 3, true);
    bench.witness("reserve and abort", cells, cells - 3, descriptors - 1, 3);
    reclaim.cleanup = bench.cleanup(malformed);
    check(!reclaim.cleanup.has_cell && reclaim.cleanup.done, "zero_cell_cleanup_trigger");
    bench.step(reclaim);
    bench.witness("zero-cell cleanup post", cells, cells, descriptors, 0);
    bench.idle(24);

    const int retained = bench.reserve(0, 0, 1);
    bench.materialize(retained, 1);
    bench.idle(16);
    bench.witness("before stalled final", cells - 1, cells - 1, descriptors - 1, 0);
    bench.idle(7);
    bench.witness("after stalled final", cells - 1, cells - 1, descriptors - 1, 0);
    Batch retire;
    retire.tx[0] = bench.tx(retained);
    bench.step(retire);
    bench.drain();
}

void identity(Bench& bench) {
    const int token = bench.reserve(0, 0, 1);
    const int other = bench.reserve(1, 4, 1);
    static_assert(Frame::tag == 0x1357);
    bench.materialize(token, 1);
    bench.materialize(other, 1);
    bench.idle(16);
    Batch legal;
    legal.tx[0] = bench.tx(token);
    legal.tx[1] = bench.tx(other);
    check(legal.tx[0].address == 0 && legal.tx[1].address != 0, "ID_zero_is_present");
    Batch duplicate = legal;
    duplicate.tx[1] = legal.tx[0];
    intended_failure("duplicate_cell", [&] { bench.validate_returns(duplicate); });
    Batch free = legal;
    free.tx[1].address = cells - 1;
    intended_failure("already_free_cell", [&] { bench.validate_returns(free); });
    Batch duplicate_desc = legal;
    duplicate_desc.tx[1].descriptor = legal.tx[0].descriptor;
    intended_failure("duplicate_descriptor", [&] { bench.validate_returns(duplicate_desc); });
    Batch free_desc = legal;
    free_desc.tx[1].descriptor = descriptors - 1;
    intended_failure("already_free_descriptor", [&] { bench.validate_returns(free_desc); });
    Batch nonfinal = legal;
    nonfinal.tx[1].final = false;
    intended_failure("real_final_retirement", [&] { bench.validate_returns(nonfinal); });
    bench.step(legal);

    const int reused = bench.reserve(0, 0, 1);
    bench.materialize(reused, 1);
    bench.idle(16);
    Batch current;
    current.tx[0] = bench.tx(reused);
    check(current.tx[0].address == legal.tx[0].address && reused != token, "phys_id_reused");
    Batch stale = current;
    stale.tx[0] = legal.tx[0];
    intended_failure("current_owner", [&] { bench.validate_returns(stale); });
    bench.step(current);
    bench.drain();
}

void reset_owned(Bench& bench) {
    constexpr int frame_cells = cells / descriptors;
    static_assert(cells % descriptors == 0 && frame_cells <= max_frame_cells);
    for (int i = 0; i < descriptors; ++i)
        bench.materialize(bench.reserve(0, 0, frame_cells), frame_cells);
    bench.witness("reset both pools fully owned", 0, 0, 0, 0);
    bench.reset();

    const int aborting = bench.reserve(0, 0, 3);
    const int staged = bench.reserve(1, queues - 1, 2);
    bench.materialize(aborting, 1);
    bench.materialize(staged, 1);
    bench.mark_abort(aborting);
    bench.witness("reset mixed", cells - 2, cells - 5, descriptors - 2, 3);
    const auto stale = bench.cleanup(aborting);
    bench.reset();

    const int current = bench.reserve(0, 0, 1);
    bench.materialize(current, 1);
    bench.idle(16);
    Batch retire;
    retire.tx[0] = bench.tx(current);
    check(stale.address == retire.tx[0].address, "reset_id_reuse");
    Batch corrupt;
    corrupt.cleanup = stale;
    intended_failure("current_owner", [&] { bench.validate_returns(corrupt); });
    bench.step(retire);
    bench.drain();
}
}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    const std::string scenario = argv[1];
    const auto seed = static_cast<uint32_t>(std::stoul(argv[2]));
    Bench bench(seed);
    try {
        if (scenario == "descriptor") descriptor_scarcity(bench);
        else if (scenario == "cell") cell_scarcity(bench);
        else if (scenario == "peak") peak(bench);
        else if (scenario == "abort") abort_and_stall(bench);
        else if (scenario == "identity") identity(bench);
        else if (scenario == "reset") reset_owned(bench);
        else if (scenario == "random") {
            fill_cell_credit(bench, false);
            bench.random_sequence();
        }
        else return 2;
        bench.drain();
        bench.summary();
        std::cout << "POOLS_PASS " << scenario << " seed=" << seed << '\n';
    } catch (const std::exception& failure) {
        std::cerr << "POOLS_FAIL " << scenario << " seed=" << seed << " edge=" << bench.edge
                  << " detector=" << failure.what() << '\n';
        return 1;
    }
}
