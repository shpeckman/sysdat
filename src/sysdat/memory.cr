# src/sysdat/memory.cr
module Sysdat
  struct Memory
    getter total : UInt64
    getter free : UInt64
    getter available : UInt64
    getter buffers : UInt64
    getter cached : UInt64
    getter swap_total : UInt64
    getter swap_free : UInt64
    getter swap_cached : UInt64
    getter active : UInt64
    getter inactive : UInt64
    getter dirty : UInt64
    getter hugepages_total : UInt64
    getter hugepages_free : UInt64
    getter hugepage_size : UInt64

    def initialize(@total, @free, @available, @buffers, @cached, @swap_total, @swap_free,
                   @swap_cached, @active, @inactive, @dirty, @hugepages_total,
                   @hugepages_free, @hugepage_size)
    end

    def used : UInt64
      total > available ? total - available : 0_u64
    end
  end

  def self.memory : Memory
    values = Hash(String, UInt64).new(0_u64)

    available = SysFS.read_lines("/proc/meminfo") do |line|
      key, separator, rest = line.partition(':')
      next if separator.empty?
      rest = rest.strip
      amount = rest.to_u64?(strict: false)
      next unless amount
      amount *= 1024 if rest.ends_with?("kB")
      values[key] = amount
    end
    raise Error.new("/proc/meminfo is unavailable") unless available

    Memory.new(
      total: values["MemTotal"],
      free: values["MemFree"],
      available: values["MemAvailable"],
      buffers: values["Buffers"],
      cached: values["Cached"],
      swap_total: values["SwapTotal"],
      swap_free: values["SwapFree"],
      swap_cached: values["SwapCached"],
      active: values["Active"],
      inactive: values["Inactive"],
      dirty: values["Dirty"],
      hugepages_total: values["HugePages_Total"],
      hugepages_free: values["HugePages_Free"],
      hugepage_size: values["Hugepagesize"],
    )
  end
end
