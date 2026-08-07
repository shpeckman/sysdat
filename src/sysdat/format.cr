# src/sysdat/format.cr
module Sysdat::Format
  extend self

  BINARY_UNITS  = {"B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"}
  DECIMAL_UNITS = {"B", "KB", "MB", "GB", "TB", "PB", "EB"}

  def bytes(value : Int, binary : Bool = true, precision : Int32 = 1) : String
    humanize(value.to_f, binary ? 1024.0 : 1000.0, binary ? BINARY_UNITS : DECIMAL_UNITS, precision)
  end

  def bytes_per_second(value : Float64, binary : Bool = true, precision : Int32 = 1) : String
    "#{humanize(value, binary ? 1024.0 : 1000.0, binary ? BINARY_UNITS : DECIMAL_UNITS, precision)}/s"
  end

  def hertz(mhz : Float64, precision : Int32 = 2) : String
    if mhz >= 1000.0
      "#{(mhz / 1000.0).round(precision)} GHz"
    else
      "#{mhz.round(precision)} MHz"
    end
  end

  private def humanize(value : Float64, base : Float64, units : Tuple, precision : Int32) : String
    negative = value < 0
    value    = value.abs
    index    = 0
    while value >= base && index < units.size - 1
      value /= base
      index += 1
    end
    formatted = index.zero? ? value.round.to_i.to_s : value.round(precision).to_s
    "#{negative ? "-" : ""}#{formatted} #{units[index]}"
  end
end
