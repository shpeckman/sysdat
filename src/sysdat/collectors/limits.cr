# src/sysdat/collectors/limits.cr
module Sysdat::Limits
  record FileDescriptors,
    allocated : UInt64,
    maximum   : UInt64 do
    include JSON::Serializable

    def used : UInt64
      allocated
    end
  end

  record Threads,
    pid_max     : UInt64,
    threads_max : UInt64 do
    include JSON::Serializable
  end

  class FileDescriptorsCollector
    include Sysdat::Collector(FileDescriptors)

    def collect : FileDescriptors
      fields    = (SysFS.read_line("/proc/sys/fs/file-nr") || "").split
      allocated = fields[0]?.try(&.to_u64?(strict: false)) || 0_u64
      maximum   = fields[2]?.try(&.to_u64?(strict: false)) || 0_u64

      FileDescriptors.new(
        allocated: allocated,
        maximum: maximum
      )
    end
  end

  class ThreadsCollector
    include Sysdat::Collector(Threads)

    def collect : Threads
      pid_max     = SysFS.read_int("/proc/sys/kernel/pid_max").try(&.to_u64) || 0_u64
      threads_max = SysFS.read_int("/proc/sys/kernel/threads-max").try(&.to_u64) || 0_u64

      Threads.new(
        pid_max: pid_max,
        threads_max: threads_max
      )
    end
  end

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def file_descriptors : FileDescriptors
      FileDescriptorsCollector.new.collect
    end

    def threads : Threads
      ThreadsCollector.new.collect
    end
  end
end
