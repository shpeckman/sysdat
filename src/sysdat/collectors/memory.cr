# src/sysdat/collectors/memory.cr
module Sysdat
  record Memory,
    total            : UInt64,
    free             : UInt64,
    available        : UInt64,
    buffers          : UInt64,
    cached           : UInt64,
    swap_total       : UInt64,
    swap_free        : UInt64,
    swap_cached      : UInt64,
    active           : UInt64,
    inactive         : UInt64,
    dirty            : UInt64,
    writeback        : UInt64,
    mapped           : UInt64,
    shmem            : UInt64,
    slab             : UInt64,
    slab_reclaimable : UInt64,
    commit_limit     : UInt64,
    committed_as     : UInt64,
    hugepages_total  : UInt64,
    hugepages_free   : UInt64,
    hugepage_size    : UInt64 do
    include JSON::Serializable

    def used : UInt64
      total > available ? total - available : 0_u64
    end

    def swap_used : UInt64
      swap_total > swap_free ? swap_total - swap_free : 0_u64
    end
  end

  def self.memory : Memory
    values = Hash(String, UInt64).new(0_u64)

    available = SysFS.read_lines("/proc/meminfo") do |line|
      key, separator, rest = line.partition(':')
      next if separator.empty?
      rest   = rest.strip
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
      writeback: values["Writeback"],
      mapped: values["Mapped"],
      shmem: values["Shmem"],
      slab: values["Slab"],
      slab_reclaimable: values["SReclaimable"],
      commit_limit: values["CommitLimit"],
      committed_as: values["Committed_AS"],
      hugepages_total: values["HugePages_Total"],
      hugepages_free: values["HugePages_Free"],
      hugepage_size: values["Hugepagesize"],
    )
  end
end
