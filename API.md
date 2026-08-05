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
  `def self.kernel_modules : Array(KernelModule)`
  `def self.memory : Memory`
  `def self.mounts : Array(Mount)`
  `def self.os : OS`
  `def self.pci_devices : Array(PCIDevice)`
  `def self.power_supplies : Array(PowerSupply)`
  `def self.pressure : Pressure?`
  `def self.processes(sort : ProcessSort = ProcessSort::CPU, limit : Int32? = nil) : Array(Process)`
  `def self.routes : Array(Route)`
  `def self.sockets : Array(Socket)`
  `def self.swaps : Array(SwapDevice)`
  `def self.thermal_zones : Array(ThermalZone)`
  `def self.thread_limits : ThreadLimits`
  `def self.usb_devices : Array(USBDevice)`
  `def self.users : Array(User)`
  `def self.wifi : Array(WiFi)`

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
      size_bytes : UInt64,
      rotational : Bool

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
  
    record KernelModule,
      name       : String,
      size_bytes : UInt64,
      ref_count  : UInt32
  
    record Memory,
      total           : UInt64,
      free            : UInt64,
      available       : UInt64,
      buffers         : UInt64,
      cached          : UInt64,
      swap_total      : UInt64,
      swap_free       : UInt64,
      swap_cached     : UInt64,
      active          : UInt64,
      inactive        : UInt64,
      dirty           : UInt64,
      hugepages_total : UInt64,
      hugepages_free  : UInt64,
      hugepage_size   : UInt64 do
      def used : UInt64
    end
  
    record Mount,
      device          : String,
      mount_point     : String,
      fs_type         : String,
      total_bytes     : UInt64,
      free_bytes      : UInt64,
      available_bytes : UInt64
  
    record NetworkInterface,
      name       : String,
      rx_bytes   : UInt64,
      rx_packets : UInt64,
      rx_errors  : UInt64,
      rx_dropped : UInt64,
      tx_bytes   : UInt64,
      tx_packets : UInt64,
      tx_errors  : UInt64,
      tx_dropped : UInt64 do
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
      rss_bytes      : UInt64,
      vsize_bytes    : UInt64,
      memory_percent : Float64,
      exe            : String?,
      cwd            : String? do
      def cpu_ticks : UInt64
    end

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
  
    record Socket,
      protocol    : String,
      local_ip    : String,
      local_port  : Int32,
      remote_ip   : String,
      remote_port : Int32,
      state       : String

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


MODULE: Sysdat::SysFS
=====================

Module Methods
--------------

  `def self.children(path : String) : Array(String)`
  `def self.read_all(path : String) : String?`
  `def self.read_int(path : String) : Int64?`
  `def self.read_line(path : String) : String?`
  `def self.read_lines(path : String, & : String ->) : Bool`
  `def self.readlink(path : String) : String?`
  `def self.string_from(bytes) : String`


LIB: LibSys (C Bindings)
========================

Constants
---------

  `SC_PAGESIZE : Int32 = 30`
  `USER_PROCESS : Int32 = 7`

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

Functions
---------

  `fun statvfs(path : LibC::Char*, buffer : StatVFS*) : LibC::Int`
  `fun sysconf(name : LibC::Int) : LibC::Long`
  `fun uname(buffer : UtsName*) : LibC::Int`
  `fun setutent : Void`
  `fun getutent : Utmp*`
  `fun endutent : Void`