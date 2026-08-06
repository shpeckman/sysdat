# src/sysdat/parsers.cr
module Sysdat
  module Parsers
    extend self

    def decode_ipv4_hex(hex : String) : String
      packed = hex.to_u32?(16)
      return "0.0.0.0" unless packed

      String.build do |io|
        4.times do |index|
          io << '.' if index > 0
          io << ((packed >> (index * 8)) & 0xff)
        end
      end
    end

    def decode_endpoint(field : String, ipv6 : Bool) : Tuple(String, Int32)
      address, separator, port = field.rpartition(':')
      return {"unknown", 0} if separator.empty?

      port_number = port.to_i?(16) || 0
      return {address, port_number} if ipv6 || address.size != 8

      {decode_ipv4_hex(address), port_number}
    end

    def format_ipv4(bytes : StaticArray(UInt8, 4)) : String
      String.build do |io|
        4.times do |index|
          io << '.' if index > 0
          io << bytes[index]
        end
      end
    end

    def format_ipv6(bytes : StaticArray(UInt8, 16)) : String
      groups = Array(UInt16).new(8) do |index|
        (bytes[index * 2].to_u16 << 8) | bytes[index * 2 + 1]
      end

      best_start = -1
      best_len   = 0
      run_start  = -1
      run_len    = 0
      groups.each_with_index do |value, index|
        if value == 0
          run_start = index if run_len == 0
          run_len += 1
          if run_len > best_len
            best_len   = run_len
            best_start = run_start
          end
        else
          run_len = 0
        end
      end

      String.build do |io|
        index = 0
        while index < 8
          if best_len > 1 && index == best_start
            io << "::"
            index += best_len
            next
          end
          io << ':' if index > 0 && !(index == best_start + best_len && best_len > 1)
          io << groups[index].to_s(16)
          index += 1
        end
      end
    end

    def parse_cpu_times(fields : Array(String)) : CPUTimes
      values = StaticArray(UInt64, 8).new(0_u64)
      fields.each_with_index do |field, index|
        break if index > 8
        next if index.zero?
        values[index - 1] = field.to_u64? || 0_u64
      end

      CPUTimes.new(values[0], values[1], values[2], values[3],
        values[4], values[5], values[6], values[7])
    end

    def parse_scheduler(raw : String?) : String
      return "" unless raw

      open_bracket  = raw.index('[')
      close_bracket = raw.index(']')
      if open_bracket && close_bracket && close_bracket > open_bracket
        raw[(open_bracket + 1)...close_bracket]
      else
        raw.split.first? || ""
      end
    end
  end
end
