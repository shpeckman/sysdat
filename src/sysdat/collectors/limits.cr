# src/sysdat/collectors/limits.cr
module Sysdat
  record FileDescriptorLimits,
    allocated : UInt64,
    maximum   : UInt64 do
    include JSON::Serializable

    def used : UInt64
      allocated
    end
  end

  record ThreadLimits,
    pid_max     : UInt64,
    threads_max : UInt64 do
    include JSON::Serializable
  end

  record KernelInfo,
    command_line  : String,
    entropy_avail : UInt64,
    pid_max       : UInt64,
    threads_max   : UInt64,
    overcommit    : Int32,
    swappiness    : Int32 do
    include JSON::Serializable
  end

  def self.file_descriptors : FileDescriptorLimits
    fields    = (SysFS.read_line("/proc/sys/fs/file-nr") || "").split
    allocated = fields[0]?.try(&.to_u64?(strict: false)) || 0_u64
    maximum   = fields[2]?.try(&.to_u64?(strict: false)) || 0_u64

    FileDescriptorLimits.new(
      allocated: allocated,
      maximum: maximum
    )
  end

  def self.thread_limits : ThreadLimits
    pid_max     = SysFS.read_int("/proc/sys/kernel/pid_max").try(&.to_u64) || 0_u64
    threads_max = SysFS.read_int("/proc/sys/kernel/threads-max").try(&.to_u64) || 0_u64

    ThreadLimits.new(
      pid_max: pid_max,
      threads_max: threads_max
    )
  end

  def self.kernel_info : KernelInfo
    KernelInfo.new(
      command_line: SysFS.read_line("/proc/cmdline") || "",
      entropy_avail: SysFS.read_int("/proc/sys/kernel/random/entropy_avail").try(&.to_u64) || 0_u64,
      pid_max: SysFS.read_int("/proc/sys/kernel/pid_max").try(&.to_u64) || 0_u64,
      threads_max: SysFS.read_int("/proc/sys/kernel/threads-max").try(&.to_u64) || 0_u64,
      overcommit: (SysFS.read_int("/proc/sys/vm/overcommit_memory") || 0_i64).to_i32,
      swappiness: (SysFS.read_int("/proc/sys/vm/swappiness") || 0_i64).to_i32,
    )
  end
end
