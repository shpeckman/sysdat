# src/sysdat.cr
require "./sysdat/serialization"
require "./sysdat/lib_sys"
require "./sysdat/sys_fs"
require "./sysdat/parsers"
require "./sysdat/format"
require "./sysdat/collector"
require "./sysdat/sampler"
require "./sysdat/collectors"
require "./sysdat/snapshot"
require "./sysdat/system"

module Sysdat
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  class Error < Exception
  end

  def self.span_from_nanoseconds(total : Int64) : Time::Span
    Time::Span.new(seconds: total // 1_000_000_000, nanoseconds: total % 1_000_000_000)
  end

  def self.span_from_hours(hours : Float64) : Time::Span?
    return nil unless hours.finite? && hours > 0.0 && hours < 1_000_000.0
    span_from_nanoseconds((hours * 3_600_000_000_000.0).to_i64)
  end
end
