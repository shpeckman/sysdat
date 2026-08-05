# src/sysdat.cr
require "./sysdat/lib_sys"
require "./sysdat/sys_fs"
require "./sysdat/os"
require "./sysdat/cpu"
require "./sysdat/memory"
require "./sysdat/storage"
require "./sysdat/network"
require "./sysdat/process"
require "./sysdat/power"
require "./sysdat/pressure"
require "./sysdat/graphics"
require "./sysdat/sensors"
require "./sysdat/devices"
require "./sysdat/host"
require "./sysdat/limits"

module Sysdat
  class Error < Exception
  end

  private def self.span_from_nanoseconds(total : Int64) : Time::Span
    Time::Span.new(seconds: total // 1_000_000_000, nanoseconds: total % 1_000_000_000)
  end

  private def self.span_from_hours(hours : Float64) : Time::Span?
    return nil unless hours.finite? && hours > 0.0 && hours < 1_000_000.0
    span_from_nanoseconds((hours * 3_600_000_000_000.0).to_i64)
  end
end
