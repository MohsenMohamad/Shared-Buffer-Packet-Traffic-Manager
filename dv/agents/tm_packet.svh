// Legal packets are solver objects; raw stream items retain unrestricted beats.
class tm_packet extends uvm_object;
    `uvm_object_utils(tm_packet)
    rand int unsigned source, qid, length, length_class, pattern, gap;
    rand bit [15:0] tag;
    rand bit [31:0] payload_seed;
    rand int unsigned beat_count, cell_count;
    rand bit [7:0] final_keep;

    constraint profile_limits {
        source < N_RX;
        qid < N_Q;
        length inside {[1:MAX_PACKET_BYTES]};
        gap inside {[0:3]};
        pattern inside {[0:3]};
    }
    constraint length_distribution {
        // Choose a class before its length so the size of the interior range
        // does not overwhelm word/cell/maximum boundaries.
        solve length_class before length;
        length_class dist {0 := 2, 1 := 2, 2 := 1, 3 := 3};
        if(length_class == 0) length inside {1, 7, 8, 9};
        if(length_class == 1) length inside {CELL_BYTES-1, CELL_BYTES, CELL_BYTES+1};
        if(length_class == 2) length inside {MAX_PACKET_BYTES-1, MAX_PACKET_BYTES};
    }
    constraint framing {
        beat_count == (length+7)/8;
        cell_count == (length+CELL_BYTES-1)/CELL_BYTES;
        final_keep == ((1 << (((length-1)%8)+1))-1);
    }
    function new(string name="packet");
        super.new(name);
    endfunction

    function byte unsigned payload_byte(int unsigned offset);
        bit [31:0] mixed;
        case(pattern)
            0: return 8'(payload_seed+offset);
            1: return 8'(payload_seed);
            2: return (offset%2 == 0 ? 8'h55 : 8'haa) ^ 8'(payload_seed);
            default: begin
                mixed = payload_seed ^ (offset*32'h9e3779b9);
                mixed ^= mixed << 13;
                mixed ^= mixed >> 17;
                mixed ^= mixed << 5;
                return 8'(mixed);
            end
        endcase
    endfunction

    function tm_stream_item to_stream_item();
        tm_stream_item item = new;
        beat_t beat;
        for(int unsigned index=0; index<beat_count; index++) begin
            beat = '0;
            beat.last = (index+1 == beat_count);
            beat.keep = beat.last ? final_keep : 8'hff;
            beat.user = {24'(index == 0 ? 0 : 123), tag, 16'(length), 8'(qid)};
            for(int lane=0; lane<8; lane++)
                beat.data[lane*8+:8] = payload_byte(index*8+32'(lane));
            item.beats.push_back(beat);
            item.gaps.push_back(int'(gap));
        end
        return item;
    endfunction
endclass

class tm_packet_item_sequence extends uvm_sequence #(tm_stream_item);
    `uvm_object_utils(tm_packet_item_sequence)
    tm_stream_item item;
    function new(string name="packet_item_sequence");
        super.new(name);
    endfunction
    task body();
        if(item == null) `uvm_fatal("PACKET_ITEM", "packet conversion missing")
        start_item(item);
        finish_item(item);
    endtask
endclass
