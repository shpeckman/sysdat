MODULE: Sysdat
==============

Entry Point
-----------

  The public surface is the `System` handle, obtained with `Sysdat.open`.
  Every collector is reached through a namespaced sub-facade on that handle
  (`system.cpu`, `system.network`, ...). There are no top-level collector
  methods on `Sysdat` itself.

    system = Sysdat.open           # => Sysdat::System

    system.cpu.info                # Sysdat::CPU::Info
    system.cpu.stats               # Sysdat::CPU::Stats
    system.memory.read             # Sysdat::Memory::Info
    system.network.interfaces      # Array(Sysdat::Network::Interface)
    system.process.list(limit: 10) # Array(Sysdat::Process::Info)
    system.snapshot                # Sysdat::Snapshot

Exceptions
----------

  `class Error < Exception`

Module Methods
--------------

  `def self.open : System`
  `def self.span_from_nanoseconds(total : Int64) : Time::Span`
  `def self.span_from_hours(hours : Float64) : Time::Span?`


CLASS: Sysdat::System
=====================

  The central handle. Sub-facades are built lazily on first access and cached.

Sub-Facades
-----------

  `def os : OS::Facade`
  `def cpu : CPU::Facade`
  `def kernel : Kernel::Facade`
  `def memory : Memory::Facade`
  `def storage : Storage::Facade`
  `def network : Network::Facade`
  `def process : Process::Facade`
  `def power : Power::Facade`
  `def pressure : Pressure::Facade`
  `def graphics : Graphics::Facade`
  `def sensors : Sensors::Facade`
  `def devices : Devices::Facade`
  `def host : Host::Facade`
  `def limits : Limits::Facade`

Aggregation
-----------

  `def snapshot : Snapshot`


The Collector Abstraction
=========================

  Every non-parameterized collection is performed by a class that includes
  the generic `Sysdat::Collector(T)` module and implements `collect : T`.
  Facades wrap these collectors; `snapshot` drives them. Parameterized queries
  (`Process`, `Network#sockets`, `Storage#filesystem`) are ordinary facade
  methods and are intentionally NOT part of this contract.

    module Sysdat::Collector(T)
      abstract def collect : T
    end

  Collector classes, by namespace:

    OS::Collector                    -> OS::Info
    Kernel::StatsCollector           -> Kernel::Stats
    Kernel::InfoCollector            -> Kernel::Info
    CPU::InfoCollector               -> CPU::Info
    CPU::StatsCollector              -> CPU::Stats
    Memory::Collector                -> Memory::Info
    Storage::MountsCollector         -> Array(Storage::Mount)
    Storage::DiskIOCollector         -> Array(Storage::DiskIO)
    Storage::BlockDevicesCollector   -> Array(Storage::BlockDevice)
    Storage::SwapsCollector          -> Array(Storage::SwapDevice)
    Network::InterfacesCollector     -> Array(Network::Interface)
    Network::WiFiCollector           -> Array(Network::WiFi)
    Network::RoutesCollector         -> Array(Network::Route)
    Process::Collector               -> Array(Process::Info)
    Power::Collector                 -> Array(Power::Supply)
    Pressure::Collector              -> Pressure::Info?
    Graphics::GPUsCollector          -> Array(Graphics::GPU)
    Graphics::DisplaysCollector      -> Array(Graphics::Display)
    Sensors::Collector               -> Array(Sensors::Chip)
    Devices::USBCollector            -> Array(Devices::USB)
    Devices::PCICollector            -> Array(Devices::PCI)
    Devices::KernelModulesCollector  -> Array(Devices::KernelModule)
    Host::Collector                  -> Host::Info
    Limits::FileDescriptorsCollector -> Limits::FileDescriptors
    Limits::ThreadsCollector         -> Limits::Threads

  `Process::Collector` is the one collector taking construction arguments,
  since `Process::Facade#list` forwards them:

    Process::Collector.new(sort : Process::Sort = Process::Sort::CPU,
                           limit : Int32? = nil,
                           io : Bool = false)


The Sampler Abstraction
=======================

  A single generic sampler replaces the former `CPUSampler` and
  `NetworkSampler`. It holds a previous reading plus a monotonic timestamp,
  and on each `sample` reads again, computes a rate from
  `(previous, current, interval)`, then stores the new reading.

    class Sysdat::Sampler(Reading, Rate)
      def initialize(read : -> Reading,
                     rate : (Reading, Reading, Time::Span) -> Rate)
      def initialize(previous : Reading,
                     read : -> Reading,
                     rate : (Reading, Reading, Time::Span) -> Rate)
      def sample : Rate
    end

  Configured samplers are handed out by facades:

    system.cpu.sampler        # => Sampler(CPU::Stats, Float64)
    system.cpu.core_sampler   # => Sampler(CPU::Stats, Array(Float64))
    system.network.sampler    # => Sampler(Array(Network::Interface), Hash(String, Network::Rate))


Serialization
=============

  All records include `JSON::Serializable`. A whole-system `Snapshot` (see
  `System#snapshot`) or any individual record can be written with `#to_json`
  and reconstructed with `.from_json`. `Time::Span` fields serialize as integer
  nanoseconds, `Time` fields as RFC 3339 strings (except `Kernel::Stats#boot_time`,
  which uses `Time::EpochConverter`), and `OS::Info#load_average` as a
  three-element JSON array, via the converters below.


NAMESPACE: Sysdat::OS
=====================

  `class Facade`
    `def info : Info`

    record Info,
      sysname           : String,
      release           : String,
      version           : String,
      machine           : String,
      hostname          : String,
      uptime            : Time::Span,
      load_average      : Tuple(Float64, Float64, Float64),
      processes_total   : Int32,
      processes_running : Int32


NAMESPACE: Sysdat::Kernel
=========================

  `class Facade`
    `def info : Info`
    `def stats : Stats`
    `def interrupts : Array(Interrupt)`

  `def self.interrupts : Array(Interrupt)`

    record Info,
      command_line  : String,
      entropy_avail : UInt64,
      pid_max       : UInt64,
      threads_max   : UInt64,
      overcommit    : Int32,
      swappiness    : Int32

    record Stats,
      boot_time        : Time,
      context_switches : UInt64,
      interrupts       : UInt64,
      processes_forked : UInt64,
      procs_running    : UInt64,
      procs_blocked    : UInt64

    record Interrupt,
      irq    : String,
      counts : Array(UInt64),
      kind   : String,
      action : String do
      def total : UInt64
    end


NAMESPACE: Sysdat::CPU
======================

  `class Facade`
    `def info : Info`
    `def stats : Stats`
    `def thermal_zones : Array(ThermalZone)`
    `def sampler : Sysdat::Sampler(Stats, Float64)`
    `def core_sampler : Sysdat::Sampler(Stats, Array(Float64))`

  `def self.thermal_zones : Array(ThermalZone)`

    record Info,
      model_name     : String,
      flags          : Array(String),
      logical_cores  : Int32,
      physical_cores : Int32,
      base_mhz       : Float64,
      cache_kb       : Int32,
      core_mhz       : Array(Float64),
      core_governors : Array(String),
      thermal_zones  : Array(ThermalZone)

    record Times,
      user    : UInt64,
      nice    : UInt64,
      system  : UInt64,
      idle    : UInt64,
      iowait  : UInt64,
      irq     : UInt64,
      softirq : UInt64,
      steal   : UInt64 do
      def idle_total : UInt64
      def total      : UInt64
      def usage_since(previous : Times) : Float64
    end

    record Stats,
      total : Times,
      cores : Array(Times)

    record ThermalZone,
      kind    : String,
      celsius : Float64


NAMESPACE: Sysdat::Memory
=========================

  `class Facade`
    `def read : Info`

    record Info,
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


NAMESPACE: Sysdat::Storage
==========================

  `class Facade`
    `def mounts : Array(Mount)`
    `def disk_io : Array(DiskIO)`
    `def block_devices : Array(BlockDevice)`
    `def swaps : Array(SwapDevice)`
    `def filesystem(path : String) : Filesystem?`

  `def self.filesystem(path : String) : Filesystem?`

Constants
---------

  `POOLED_FS_TYPES : Tuple(String, String)`
  `SKIPPED_FS_TYPES : Tuple(String, String)`
  `IGNORED_BLOCK_PREFIXES : Tuple(String, String)`
  `SECTOR_SIZE : UInt64`

Records
-------

    record Filesystem,
      total_bytes     : UInt64,
      free_bytes      : UInt64,
      available_bytes : UInt64,
      inodes_total    : UInt64,
      inodes_free     : UInt64

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

    record DiskIO,
      device           : String,
      reads_completed  : UInt64,
      writes_completed : UInt64,
      bytes_read       : UInt64,
      bytes_written    : UInt64,
      io_ticks         : UInt64

    record Partition,
      name       : String,
      size_bytes : UInt64

    record BlockDevice,
      name       : String,
      model      : String,
      serial     : String,
      size_bytes : UInt64,
      rotational : Bool,
      scheduler  : String,
      partitions : Array(Partition)

    record SwapDevice,
      path       : String,
      kind       : String,
      size_bytes : UInt64,
      used_bytes : UInt64,
      priority   : Int32


NAMESPACE: Sysdat::Network
==========================

  `class Facade`
    `def interfaces : Array(Interface)`
    `def wifi : Array(WiFi)`
    `def routes : Array(Route)`
    `def sockets(resolve_process : Bool = false) : Array(Socket)`
    `def arp_cache : Array(ArpEntry)`
    `def sampler : Sysdat::Sampler(Array(Interface), Hash(String, Rate))`

  `def self.sockets(resolve_process : Bool = false) : Array(Socket)`
  `def self.arp_cache : Array(ArpEntry)`

Constants
---------

  `TCP_STATES : Array(String)`
  `SOCKET_SOURCES : Tuple(Tuple(String, String, Bool), Tuple(String, String, Bool), Tuple(String, String, Bool), Tuple(String, String, Bool))`

Records
-------

    record Interface,
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
      def rate_since(previous : Interface, interval : Time::Span) : Rate
    end

    record InterfaceAddress,
      family  : String,
      address : String

    record Rate,
      rx_bytes_per_sec   : Float64,
      tx_bytes_per_sec   : Float64,
      rx_packets_per_sec : Float64,
      tx_packets_per_sec : Float64

    record WiFi,
      name         : String,
      link_quality : Float64,
      signal_dbm   : Float64,
      noise_dbm    : Float64

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

    record ArpEntry,
      ip         : String,
      hw_type    : String,
      flags      : String,
      hw_address : String,
      mask       : String,
      device     : String


NAMESPACE: Sysdat::Process
==========================

  `class Facade`
    `def list(sort : Sort = Sort::CPU, limit : Int32? = nil, io : Bool = false) : Array(Info)`

Enums
-----

    enum Sort
      CPU
      Memory
      PID
    end

Records
-------

    record Info,
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
      io             : IO?,
      exe            : String?,
      cwd            : String? do
      def cpu_ticks : UInt64
    end

    record IO,
      read_chars  : UInt64,
      write_chars : UInt64,
      read_bytes  : UInt64,
      write_bytes : UInt64

  NOTE: `Sysdat::Process::IO` deliberately shadows the stdlib `IO` module
  within the `Process` namespace. Reference the stdlib type as `::IO` inside
  that scope.


NAMESPACE: Sysdat::Power
========================

  `class Facade`
    `def supplies : Array(Supply)`

    record Supply,
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
      def charging?      : Bool
      def discharging?   : Bool
      def health_percent : Int32?
    end


NAMESPACE: Sysdat::Pressure
===========================

  `class Facade`
    `def read : Info?`

    record Info,
      cpu_some    : Metric?,
      memory_some : Metric?,
      memory_full : Metric?,
      io_some     : Metric?,
      io_full     : Metric?

    record Metric,
      avg10  : Float64,
      avg60  : Float64,
      avg300 : Float64,
      total  : Time::Span


NAMESPACE: Sysdat::Graphics
===========================

  `class Facade`
    `def gpus : Array(GPU)`
    `def displays : Array(Display)`

Constants
---------

  `GPU_VENDORS : Hash(String, String)`

Records
-------

    record GPU,
      name          : String,
      vendor        : String,
      busy_percent  : Int32?,
      vram_total_mb : UInt64,
      vram_used_mb  : UInt64,
      core_mhz      : Float64

    record Display,
      name       : String,
      connected  : Bool,
      resolution : String,
      dpms_state : String


NAMESPACE: Sysdat::Sensors
==========================

  `class Facade`
    `def hwmon : Array(Chip)`

Enums
-----

    enum Kind
      Temperature
      Fan
      Voltage
    end

Constants
---------

  `HWMON_SENSORS : Tuple(Tuple(Kind, String, String, Float64), Tuple(Kind, String, String, Float64), Tuple(Kind, String, String, Float64))`
  `HWMON_SENSOR_LIMIT : Int32`
  `HWMON_PROBE_FLOOR : Int32`

Records
-------

    record Chip,
      name    : String,
      sensors : Array(Sensor)

    record Sensor,
      label : String,
      kind  : Kind,
      value : Float64


NAMESPACE: Sysdat::Devices
==========================

  `class Facade`
    `def usb_devices : Array(USB)`
    `def pci_devices : Array(PCI)`
    `def kernel_modules : Array(KernelModule)`

Records
-------

    record USB,
      vendor_id    : String,
      product_id   : String,
      manufacturer : String,
      product      : String

    record PCI,
      address   : String,
      vendor_id : String,
      device_id : String,
      class_id  : String

    record KernelModule,
      name       : String,
      size_bytes : UInt64,
      ref_count  : UInt32


NAMESPACE: Sysdat::Host
=======================

  `class Facade`
    `def info : Info`
    `def users : Array(User)`

  `def self.users : Array(User)`

Constants
---------

  `VM_PRODUCT_MARKERS : Tuple(String, String, String, String)`
  `VM_VENDOR_MARKERS : Tuple(String)`
  `CONTAINER_FILES : Tuple(Tuple(String, String), Tuple(String, String))`
  `CONTAINER_CGROUP_MARKERS : Tuple(Tuple(String, String), Tuple(String, String), Tuple(String, String))`

Records
-------

    record Info,
      virtual_machine      : String?,
      container            : String? do
      def virtual_machine? : Bool
      def container?       : Bool
    end

    record User,
      name       : String,
      tty        : String,
      login_time : Time


NAMESPACE: Sysdat::Limits
=========================

  `class Facade`
    `def file_descriptors : FileDescriptors`
    `def threads : Threads`

    record FileDescriptors,
      allocated : UInt64,
      maximum   : UInt64 do
      def used  : UInt64
    end

    record Threads,
      pid_max     : UInt64,
      threads_max : UInt64


RECORD: Sysdat::Snapshot
========================

    record Snapshot,
      os               : OS::Info,
      kernel           : Kernel::Info,
      kernel_stats     : Kernel::Stats,
      cpu              : CPU::Info,
      cpu_stats        : CPU::Stats,
      memory           : Memory::Info,
      pressure         : Pressure::Info?,
      mounts           : Array(Storage::Mount),
      block_devices    : Array(Storage::BlockDevice),
      disk_io          : Array(Storage::DiskIO),
      swaps            : Array(Storage::SwapDevice),
      interfaces       : Array(Network::Interface),
      wifi             : Array(Network::WiFi),
      routes           : Array(Network::Route),
      gpus             : Array(Graphics::GPU),
      displays         : Array(Graphics::Display),
      hwmon            : Array(Sensors::Chip),
      power_supplies   : Array(Power::Supply),
      host             : Host::Info,
      file_descriptors : Limits::FileDescriptors,
      thread_limits    : Limits::Threads,
      captured_at      : Time


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
  `def self.parse_cpu_times(fields : Array(String)) : CPU::Times`
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
