MODULE: Sysdat
==============

Exceptions
----------

  `class Error < Exception`

Enums
-----

    enum ProcessSort
      CPU
      Memory
      PID
    end
  
    enum SensorKind
      Temperature
      Fan
      Voltage
    end

Constants
---------

  `POOLED_FS_TYPES : Tuple(String, String)`
  `SKIPPED_FS_TYPES : Tuple(String, String)`
  `IGNORED_BLOCK_PREFIXES : Tuple(String, String)`
  `SECTOR_SIZE : UInt64`
  `TCP_STATES : Array(String)`
  `SOCKET_SOURCES : Tuple(Tuple(String, String, Bool), Tuple(String, String, Bool), Tuple(String, String, Bool), Tuple(String, String, Bool))`
  `GPU_VENDORS : Hash(String, String)`
  `HWMON_SENSORS : Tuple(Tuple(SensorKind, String, String, Float64), Tuple(SensorKind, String, String, Float64), Tuple(SensorKind, String, String, Float64))`
  `HWMON_SENSOR_LIMIT : Int32`
  `HWMON_PROBE_FLOOR : Int32`
  `VM_PRODUCT_MARKERS : Tuple(String, String, String, String)`
  `VM_VENDOR_MARKERS : Tuple(String)`
  `CONTAINER_FILES : Tuple(Tuple(String, String), Tuple(String, String))`
  `CONTAINER_CGROUP_MARKERS : Tuple(Tuple(String, String), Tuple(String, String), Tuple(String, String))`

Serialization
-------------

  All records include `JSON::Serializable`. A whole-system `Snapshot` (see
  `Sysdat.snapshot`) or any individual record can be written with `#to_json`
  and reconstructed with `.from_json`. `Time::Span` fields serialize as integer
  nanoseconds, `Time` fields as RFC 3339 strings, and `OS#load_average` as a
  three-element JSON array, via the converters below.

Module Methods
--------------

  `def self.arp_cache : Array(ArpEntry)`
  `def self.block_devices : Array(BlockDevice)`
  `def self.cpu : CPU`
  `def self.cpu_stats : CPUStats`
  `def self.disk_io : Array(DiskIO)`
  `def self.displays : Array(Display)`
  `def self.file_descriptors : FileDescriptorLimits`
  `def self.filesystem(path : String) : Filesystem?`
  `def self.gpus : Array(GPU)`
  `def self.host : Host`
  `def self.hwmon : Array(HwmonChip)`
  `def self.interfaces : Array(NetworkInterface)`
  `def self.interrupts : Array(Interrupt)`
  `def self.kernel_info : KernelInfo`
  `def self.kernel_modules : Array(KernelModule)`
  `def self.kernel_stats : KernelStats`
  `def self.memory : Memory`
  `def self.mounts : Array(Mount)`
  `def self.os : OS`
  `def self.pci_devices : Array(PCIDevice)`
  `def self.power_supplies : Array(PowerSupply)`
  `def self.pressure : Pressure?`
  `def self.processes(sort : ProcessSort = ProcessSort::CPU, limit : Int32? = nil, io : Bool = false) : Array(Process)`
  `def self.routes : Array(Route)`
  `def self.snapshot : Snapshot`
  `def self.sockets(resolve_process : Bool = false) : Array(Socket)`
  `def self.swaps : Array(SwapDevice)`
  `def self.thermal_zones : Array(ThermalZone)`
  `def self.thread_limits : ThreadLimits`
  `def self.usb_devices : Array(USBDevice)`
  `def self.users : Array(User)`
  `def self.wifi : Array(WiFi)`

Samplers
--------

    class CPUSampler
      def initialize
      def initialize(previous : CPUStats)
      def sample : Float64
      def sample_per_core : Array(Float64)
    end
  
    class NetworkSampler
      def initialize
      def sample : Hash(String, NetworkRate)
    end

Records
-------

    record ArpEntry,
      ip         : String,
      hw_type    : String,
      flags      : String,
      hw_address : String,
      mask       : String,
      device     : String

    record BlockDevice,
      name       : String,
      model      : String,
      serial     : String,
      size_bytes : UInt64,
      rotational : Bool,
      scheduler  : String,
      partitions : Array(Partition)

    record CPU,
      model_name     : String,
      flags          : Array(String),
      logical_cores  : Int32,
      physical_cores : Int32,
      base_mhz       : Float64,
      cache_kb       : Int32,
      core_mhz       : Array(Float64),
      core_governors : Array(String),
      thermal_zones  : Array(ThermalZone)
  
    record CPUStats,
      total : CPUTimes,
      cores : Array(CPUTimes)
  
    record CPUTimes,
      user           : UInt64,
      nice           : UInt64,
      system         : UInt64,
      idle           : UInt64,
      iowait         : UInt64,
      irq            : UInt64,
      softirq        : UInt64,
      steal          : UInt64 do
      def idle_total : UInt64
      def total      : UInt64
      def usage_since(previous : CPUTimes) : Float64
    end
  
    record DiskIO,
      device           : String,
      reads_completed  : UInt64,
      writes_completed : UInt64,
      bytes_read       : UInt64,
      bytes_written    : UInt64,
      io_ticks         : UInt64
  
    record Display,
      name       : String,
      connected  : Bool,
      resolution : String,
      dpms_state : String

    record FileDescriptorLimits,
      allocated : UInt64,
      maximum   : UInt64 do
      def used  : UInt64
    end
  
    record Filesystem,
      total_bytes     : UInt64,
      free_bytes      : UInt64,
      available_bytes : UInt64,
      inodes_total    : UInt64,
      inodes_free     : UInt64
  
    record GPU,
      name          : String,
      vendor        : String,
      busy_percent  : Int32?,
      vram_total_mb : UInt64,
      vram_used_mb  : UInt64,
      core_mhz      : Float64
  
    record Host,
      virtual_machine      : String?,
      container            : String? do
      def virtual_machine? : Bool
      def container?       : Bool
    end
  
    record HwmonChip,
      name    : String,
      sensors : Array(Sensor)
  
    record InterfaceAddress,
      family  : String,
      address : String

    record Interrupt,
      irq    : String,
      counts : Array(UInt64),
      kind   : String,
      action : String do
      def total : UInt64
    end

    record KernelInfo,
      command_line  : String,
      entropy_avail : UInt64,
      pid_max       : UInt64,
      threads_max   : UInt64,
      overcommit    : Int32,
      swappiness    : Int32

    record KernelModule,
      name       : String,
      size_bytes : UInt64,
      ref_count  : UInt32

    record KernelStats,
      boot_time        : Time,
      context_switches : UInt64,
      interrupts       : UInt64,
      processes_forked : UInt64,
      procs_running    : UInt64,
      procs_blocked    : UInt64
  
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
      def used      : UInt64
      def swap_used : UInt64
    end
  
    record Mount,
      device          : String,
      mount_point     : String,
      fs_type         : String,
      options         : Array(String),
      total_bytes     : UInt64,
      free_bytes      : UInt64,
      available_bytes : UInt64 do
      def read_only? : Bool
    end
  
    record NetworkInterface,
      name        : String,
      mac_address : String,
      operstate   : String,
      mtu         : Int32,
      speed_mbps  : Int32,
      addresses   : Array(InterfaceAddress),
      rx_bytes    : UInt64,
      rx_packets  : UInt64,
      rx_errors   : UInt64,
      rx_dropped  : UInt64,
      tx_bytes    : UInt64,
      tx_packets  : UInt64,
      tx_errors   : UInt64,
      tx_dropped  : UInt64 do
      def up? : Bool
      def rate_since(previous : NetworkInterface, interval : Time::Span) : NetworkRate
    end
  
    record NetworkRate,
      rx_bytes_per_sec   : Float64,
      tx_bytes_per_sec   : Float64,
      rx_packets_per_sec : Float64,
      tx_packets_per_sec : Float64
  
    record OS,
      sysname           : String,
      release           : String,
      version           : String,
      machine           : String,
      hostname          : String,
      uptime            : Time::Span,
      load_average      : Tuple(Float64, Float64, Float64),
      processes_total   : Int32,
      processes_running : Int32
  
    record Partition,
      name       : String,
      size_bytes : UInt64

    record PCIDevice,
      address   : String,
      vendor_id : String,
      device_id : String,
      class_id  : String
  
    record PowerSupply,
      name                   : String,
      kind                   : String,
      status                 : String,
      present                : Bool,
      online                 : Bool?,
      capacity_percent       : Int32?,
      energy_now_uwh         : Int64?,
      energy_full_uwh        : Int64?,
      energy_full_design_uwh : Int64?,
      power_now_uw           : Int64?,
      voltage_now_uv         : Int64?,
      charge_now_uah         : Int64?,
      charge_full_uah        : Int64?,
      charge_full_design_uah : Int64?,
      current_now_ua         : Int64?,
      cycle_count            : Int32?,
      time_remaining         : Time::Span? do
      def charging? : Bool
      def discharging? : Bool
      def health_percent : Int32?
    end
  
    record Pressure,
      cpu_some    : PressureMetric?,
      memory_some : PressureMetric?,
      memory_full : PressureMetric?,
      io_some     : PressureMetric?,
      io_full     : PressureMetric?
  
    record PressureMetric,
      avg10  : Float64,
      avg60  : Float64,
      avg300 : Float64,
      total  : Time::Span
  
    record Process,
      pid            : Int32,
      ppid           : Int32,
      uid            : UInt32,
      user           : String,
      name           : String,
      cmdline        : Array(String),
      state          : Char,
      utime          : UInt64,
      stime          : UInt64,
      threads        : Int32,
      fd_count       : UInt32,
      rss_bytes      : UInt64,
      vsize_bytes    : UInt64,
      memory_percent : Float64,
      io             : ProcessIO?,
      exe            : String?,
      cwd            : String? do
      def cpu_ticks : UInt64
    end

    record ProcessIO,
      read_chars  : UInt64,
      write_chars : UInt64,
      read_bytes  : UInt64,
      write_bytes : UInt64

    record Route,
      destination : String,
      gateway     : String,
      flags       : Int32,
      ref_count   : Int32,
      use         : Int32,
      metric      : Int32,
      mask        : String,
      mtu         : Int32,
      window      : Int32,
      irtt        : Int32,
      interface   : String
  
    record Sensor,
      label : String,
      kind  : SensorKind,
      value : Float64
  
    record Snapshot,
      os               : OS,
      kernel           : KernelInfo,
      kernel_stats     : KernelStats,
      cpu              : CPU,
      cpu_stats        : CPUStats,
      memory           : Memory,
      pressure         : Pressure?,
      mounts           : Array(Mount),
      block_devices    : Array(BlockDevice),
      disk_io          : Array(DiskIO),
      swaps            : Array(SwapDevice),
      interfaces       : Array(NetworkInterface),
      wifi             : Array(WiFi),
      routes           : Array(Route),
      gpus             : Array(GPU),
      displays         : Array(Display),
      hwmon            : Array(HwmonChip),
      power_supplies   : Array(PowerSupply),
      host             : Host,
      file_descriptors : FileDescriptorLimits,
      thread_limits    : ThreadLimits,
      captured_at      : Time

    record Socket,
      protocol    : String,
      local_ip    : String,
      local_port  : Int32,
      remote_ip   : String,
      remote_port : Int32,
      state       : String,
      inode       : UInt64,
      pid         : Int32?,
      process     : String?

    record SwapDevice,
      path       : String,
      kind       : String,
      size_bytes : UInt64,
      used_bytes : UInt64,
      priority   : Int32
  
    record ThermalZone,
      kind    : String,
      celsius : Float64

    record ThreadLimits,
      pid_max     : UInt64,
      threads_max : UInt64
  
    record USBDevice,
      vendor_id    : String,
      product_id   : String,
      manufacturer : String,
      product      : String
  
    record User,
      name       : String,
      tty        : String,
      login_time : Time
  
    record WiFi,
      name         : String,
      link_quality : Float64,
      signal_dbm   : Float64,
      noise_dbm    : Float64


MODULE: Sysdat::Format
======================

Constants
---------

  `BINARY_UNITS : Tuple(String, String, String, String, String, String, String)`
  `DECIMAL_UNITS : Tuple(String, String, String, String, String, String, String)`

Module Methods
--------------

  `def self.bytes(value : Int, binary : Bool = true, precision : Int32 = 1) : String`
  `def self.bytes_per_second(value : Float64, binary : Bool = true, precision : Int32 = 1) : String`
  `def self.hertz(mhz : Float64, precision : Int32 = 2) : String`


MODULE: Sysdat::Parsers
=======================

Module Methods
--------------

  `def self.decode_ipv4_hex(hex : String) : String`
  `def self.decode_endpoint(field : String, ipv6 : Bool) : Tuple(String, Int32)`
  `def self.format_ipv4(bytes : StaticArray(UInt8, 4)) : String`
  `def self.format_ipv6(bytes : StaticArray(UInt8, 16)) : String`
  `def self.parse_cpu_times(fields : Array(String)) : CPUTimes`
  `def self.parse_scheduler(raw : String?) : String`


MODULE: Sysdat::SysFS
=====================

Module Methods
--------------

  `def self.children(path : String) : Array(String)`
  `def self.count_children(path : String) : UInt32`
  `def self.read_all(path : String) : String?`
  `def self.read_int(path : String) : Int64?`
  `def self.read_line(path : String) : String?`
  `def self.read_lines(path : String, & : String ->) : Bool`
  `def self.readlink(path : String) : String?`
  `def self.string_from(bytes) : String`


JSON Converters
---------------

  Used internally via `@[JSON::Field(converter: ...)]`; can be reused on your
  own records.

    module Sysdat::SpanConverter
      def self.to_json(value : Time::Span, builder : JSON::Builder) : Nil
      def self.from_json(pull : JSON::PullParser) : Time::Span
    end
  
    module Sysdat::NilableSpanConverter
      def self.to_json(value : Time::Span?, builder : JSON::Builder) : Nil
      def self.from_json(pull : JSON::PullParser) : Time::Span?
    end
  
    module Sysdat::LoadAverageConverter
      def self.to_json(value : Tuple(Float64, Float64, Float64), builder : JSON::Builder) : Nil
      def self.from_json(pull : JSON::PullParser) : Tuple(Float64, Float64, Float64)
    end


LIB: LibSys (C Bindings)
========================

Constants
---------

  `SC_PAGESIZE : Int32 = 30`
  `USER_PROCESS : Int32 = 7`
  `AF_INET : Int32 = 2`
  `AF_INET6 : Int32 = 10`

Structs
-------

    struct StatVFS
      f_bsize   : LibC::ULong
      f_frsize  : LibC::ULong
      f_blocks  : UInt64
      f_bfree   : UInt64
      f_bavail  : UInt64
      f_files   : UInt64
      f_ffree   : UInt64
      f_favail  : UInt64
      f_fsid    : LibC::ULong
      f_flag    : LibC::ULong
      f_namemax : LibC::ULong
      f_type    : LibC::UInt
      f_spare   : StaticArray(LibC::Int, 5)
    end
  
    struct UtsName
      sysname    : StaticArray(UInt8, 65)
      nodename   : StaticArray(UInt8, 65)
      release    : StaticArray(UInt8, 65)
      version    : StaticArray(UInt8, 65)
      machine    : StaticArray(UInt8, 65)
      domainname : StaticArray(UInt8, 65)
    end
  
    struct UtmpExit
      e_termination : Int16
      e_exit        : Int16
    end
  
    struct UtmpTimeval
      tv_sec  : Int32
      tv_usec : Int32
    end
  
    struct Utmp
      ut_type     : Int16
      ut_pid      : LibC::PidT
      ut_line     : StaticArray(UInt8, 32)
      ut_id       : StaticArray(UInt8, 4)
      ut_user     : StaticArray(UInt8, 32)
      ut_host     : StaticArray(UInt8, 256)
      ut_exit     : UtmpExit
      ut_session  : Int32
      ut_tv       : UtmpTimeval
      ut_addr_v6  : StaticArray(Int32, 4)
      ut_reserved : StaticArray(UInt8, 20)
    end
  
    struct Sockaddr
      sa_family : LibC::UShort
      sa_data   : StaticArray(UInt8, 14)
    end
  
    struct SockaddrIn
      sin_family : LibC::UShort
      sin_port   : UInt16
      sin_addr   : StaticArray(UInt8, 4)
      sin_zero   : StaticArray(UInt8, 8)
    end
  
    struct SockaddrIn6
      sin6_family   : LibC::UShort
      sin6_port     : UInt16
      sin6_flowinfo : UInt32
      sin6_addr     : StaticArray(UInt8, 16)
      sin6_scope_id : UInt32
    end
  
    struct Ifaddrs
      ifa_next    : Ifaddrs*
      ifa_name    : LibC::Char*
      ifa_flags   : LibC::UInt
      ifa_addr    : Sockaddr*
      ifa_netmask : Sockaddr*
      ifa_ifu     : Sockaddr*
      ifa_data    : Void*
    end

Functions
---------

  `fun statvfs(path : LibC::Char*, buffer : StatVFS*) : LibC::Int`
  `fun sysconf(name : LibC::Int) : LibC::Long`
  `fun uname(buffer : UtsName*) : LibC::Int`
  `fun setutent : Void`
  `fun getutent : Utmp*`
  `fun endutent : Void`
  `fun getifaddrs(ifap : Ifaddrs**) : LibC::Int`
  `fun freeifaddrs(ifa : Ifaddrs*) : Void`