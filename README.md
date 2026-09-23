# sysdat

Linux system information for Crystal. sysdat reads `/proc`, `/sys` and a handful of libc calls, and returns immutable, typed, JSON-serializable records covering the OS, kernel, CPU, memory, pressure stall information, storage, network, processes, power supplies, graphics, hardware sensors, devices, host environment and system limits.

Every read returns fresh data. Nothing is cached, and there are no background threads or external dependencies.

## Requirements

- Linux with glibc
- Crystal `>= 1.21.0`

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  sysdat:
    github: shpeckman/sysdat
```

Then run `shards install`.

## Usage

```crystal
require "sysdat"

system = Sysdat.open

cpu = system.cpu.info
puts "#{cpu.model_name} (#{cpu.physical_cores}C/#{cpu.logical_cores}T)"

memory = system.memory.read
puts "#{Sysdat::Format.bytes(memory.used)} / #{Sysdat::Format.bytes(memory.total)}"

system.storage.mounts.each do |mount|
  puts "#{mount.mount_point}: #{Sysdat::Format.bytes(mount.available_bytes)} free"
end
```

### Sampling rates

Counters such as CPU time and interface bytes only become meaningful as deltas. A sampler takes its first reading when it is created, and each call to `#sample` returns the rate since the previous call.

```crystal
cpu = system.cpu.sampler
net = system.network.sampler

loop do
  sleep 1.second

  puts "cpu #{cpu.sample.round(1)}%"
  net.sample.each do |name, rate|
    rx = Sysdat::Format.bytes_per_second(rate.rx_bytes_per_sec)
    tx = Sysdat::Format.bytes_per_second(rate.tx_bytes_per_sec)
    puts "#{name}  rx #{rx}  tx #{tx}"
  end
end
```

### Processes

```crystal
system.process.list(sort: :memory, limit: 5).each do |process|
  puts "#{process.pid} #{process.name} #{Sysdat::Format.bytes(process.rss_bytes)}"
end

if details = system.process.details(Process.pid.to_i32)
  puts details.capabilities.effective.includes?("CAP_NET_ADMIN")
  puts details.namespaces.map(&.kind).join(", ")
  puts "#{details.fds.sockets.size} open sockets"
end
```

### Listening sockets with owners

```crystal
system.network.sockets(resolve_process: true)
  .select { |socket| socket.state == "LISTEN" }
  .each { |socket| puts "#{socket.local_ip}:#{socket.local_port} #{socket.process}" }
```

### Snapshots and JSON

Every record includes `JSON::Serializable`. `System#snapshot` captures most domains in one call.

```crystal
File.write("snapshot.json", system.snapshot.to_pretty_json)

restored = Sysdat::Snapshot.from_json(File.read("snapshot.json"))
```

### Error handling

Missing or unreadable sources degrade to `nil`, empty collections or zero values. `Sysdat::Error` is raised only when a source that a result cannot exist without is unavailable (see [Errors](#errors)).

```crystal
begin
  system.memory.read
rescue error : Sysdat::Error
  STDERR.puts error.message
end
```

### Permissions

Some data requires the same user as the target process or root: process `exe`, `cwd`, `io` and fd details, as well as socket owner resolution. Values that can't be read are `nil`, zero or omitted.

## API Reference

### Conventions

- Fields suffixed `_bytes` are bytes, `_mb` are MiB and `_mhz` are MHz. `_uwh`, `_uw`, `_uv`, `_uah` and `_ua` are micro-watt-hours, micro-watts, micro-volts, micro-amp-hours and micro-amps.
- Durations are `Time::Span`. In JSON they serialize as integer nanoseconds.
- Facade methods perform a new read on every call.

### `Sysdat`

| Member                     | Description                                   |
|----------------------------|-----------------------------------------------|
| `Sysdat.open : System`     | Creates a `System`.                           |
| `Sysdat::VERSION : String` | Library version.                              |
| `Sysdat::Error`            | Raised when a required source is unavailable. |

### `Sysdat::System`

| Method     | Returns            |
|------------|--------------------|
| `os`       | `OS::Facade`       |
| `kernel`   | `Kernel::Facade`   |
| `cpu`      | `CPU::Facade`      |
| `memory`   | `Memory::Facade`   |
| `pressure` | `Pressure::Facade` |
| `storage`  | `Storage::Facade`  |
| `network`  | `Network::Facade`  |
| `process`  | `Process::Facade`  |
| `power`    | `Power::Facade`    |
| `graphics` | `Graphics::Facade` |
| `sensors`  | `Sensors::Facade`  |
| `devices`  | `Devices::Facade`  |
| `host`     | `Host::Facade`     |
| `limits`   | `Limits::Facade`   |
| `snapshot` | `Snapshot`         |

Facades are created lazily and reused.

### `Sysdat::Snapshot`

```crystal
os                  : OS::Info
kernel              : Kernel::Info
kernel_stats        : Kernel::Stats
cpu                 : CPU::Info
cpu_stats           : CPU::Stats
cpu_topology        : Array(CPU::Package)
cpu_vulnerabilities : Array(CPU::Vulnerability)
memory              : Memory::Info
pressure            : Pressure::Info?
mounts              : Array(Storage::Mount)
block_devices       : Array(Storage::BlockDevice)
disk_io             : Array(Storage::DiskIO)
swaps               : Array(Storage::SwapDevice)
interfaces          : Array(Network::Interface)
wifi                : Array(Network::WiFi)
routes              : Array(Network::Route)
gpus                : Array(Graphics::GPU)
displays            : Array(Graphics::Display)
hwmon               : Array(Sensors::Chip)
power_supplies      : Array(Power::Supply)
host                : Host::Info
file_descriptors    : Limits::FileDescriptors
thread_limits       : Limits::Threads
captured_at         : Time
```

### OS

| Method              | Returns       |
|---------------------|---------------|
| `system.os.info`    | `OS::Info`    |
| `system.os.release` | `OS::Release` |

```crystal
OS::Info
  sysname           : String
  release           : String
  version           : String
  machine           : String
  hostname          : String
  distro            : OS::Release
  uptime            : Time::Span
  load_average      : Tuple(Float64, Float64, Float64)   # JSON: [1m, 5m, 15m]
  processes_total   : Int32
  processes_running : Int32

OS::Release
  id               : String
  id_like          : Array(String)
  name             : String
  pretty_name      : String
  version          : String
  version_id       : String
  version_codename : String
  build_id         : String
  fields           : Hash(String, String)              # every os-release key, unquoted
```

### Kernel

| Method                     | Returns                                                              |
|----------------------------|----------------------------------------------------------------------|
| `system.kernel.info`       | `Kernel::Info`                                                       |
| `system.kernel.stats`      | `Kernel::Stats`                                                      |
| `system.kernel.interrupts` | `Array(Kernel::Interrupt)`                                           |
| `system.kernel.config`     | `Hash(String, String)`, from `/proc/config.gz`; empty if unavailable |

```crystal
Kernel::Info
  command_line  : String
  entropy_avail : UInt64
  pid_max       : UInt64
  threads_max   : UInt64
  overcommit    : Int32
  swappiness    : Int32
  taint         : Kernel::Taint

Kernel::Taint
  value : UInt32
  tainted? : Bool
  flags    : Array(Kernel::TaintFlag)
  letters  : String

Kernel::TaintFlag
  bit         : Int32
  letter      : Char
  description : String

Kernel::Stats
  boot_time        : Time                             # JSON: epoch seconds
  context_switches : UInt64
  interrupts       : UInt64
  processes_forked : UInt64
  procs_running    : UInt64
  procs_blocked    : UInt64

Kernel::Interrupt
  irq    : String
  counts : Array(UInt64)                              # one entry per CPU
  kind   : String
  action : String
  total  : UInt64
```

### CPU

| Method                       | Returns                                                          |
|------------------------------|------------------------------------------------------------------|
| `system.cpu.info`            | `CPU::Info`                                                      |
| `system.cpu.stats`           | `CPU::Stats`                                                     |
| `system.cpu.thermal_zones`   | `Array(CPU::ThermalZone)`                                        |
| `system.cpu.topology`        | `Array(CPU::Package)`                                            |
| `system.cpu.vulnerabilities` | `Array(CPU::Vulnerability)`                                      |
| `system.cpu.frequency_stats` | `Array(CPU::FrequencyStats)`                                     |
| `system.cpu.sampler`         | `Sampler(CPU::Stats, Float64)`: total usage in percent           |
| `system.cpu.core_sampler`    | `Sampler(CPU::Stats, Array(Float64))`: per-core usage in percent |

```crystal
CPU::Info
  model_name     : String
  flags          : Array(String)
  logical_cores  : Int32
  physical_cores : Int32
  base_mhz       : Float64
  cache_kb       : Int32
  microcode      : String
  core_mhz       : Array(Float64)                     # indexed by logical CPU
  core_governors : Array(String)                      # indexed by logical CPU
  thermal_zones  : Array(CPU::ThermalZone)

CPU::ThermalZone
  kind    : String
  celsius : Float64

CPU::Stats
  total : CPU::Times
  cores : Array(CPU::Times)

CPU::Times                                            # USER_HZ clock ticks
  user, nice, system, idle, iowait, irq, softirq, steal : UInt64
  idle_total  : UInt64
  total       : UInt64
  usage_since(previous : CPU::Times) : Float64        # percent

CPU::Package
  physical_package_id : Int32
  die_id              : Int32?
  cluster_id          : Int32?
  cores               : Array(CPU::Core)
  thread_count        : Int32

CPU::Core
  core_id : Int32
  threads : Array(CPU::Thread)
  smt?    : Bool

CPU::Thread
  processor : Int32
  core_mhz  : Float64
  governor  : String

CPU::Vulnerability
  name        : String
  status      : String
  mitigated?  : Bool
  vulnerable? : Bool

CPU::FrequencyStats
  processor   : Int32
  transitions : UInt64
  buckets     : Array(CPU::FrequencyBucket)
  total       : Time::Span

CPU::FrequencyBucket
  khz        : Int64
  time_ticks : UInt64                                 # 10 ms units
  time       : Time::Span
```

### Memory

| Method               | Returns        |
|----------------------|----------------|
| `system.memory.read` | `Memory::Info` |

```crystal
Memory::Info                                          # bytes unless noted
  total, free, available, buffers, cached       : UInt64
  swap_total, swap_free, swap_cached            : UInt64
  active, inactive, dirty, writeback, mapped    : UInt64
  shmem, slab, slab_reclaimable                 : UInt64
  commit_limit, committed_as                    : UInt64
  hugepages_total, hugepages_free               : UInt64   # page counts
  hugepage_size                                 : UInt64
  used      : UInt64                                  # total - available
  swap_used : UInt64
```

### Pressure

| Method                 | Returns                                          |
|------------------------|--------------------------------------------------|
| `system.pressure.read` | `Pressure::Info?`: `nil` when PSI is unavailable |

```crystal
Pressure::Info
  cpu_some, memory_some, memory_full, io_some, io_full : Pressure::Metric?

Pressure::Metric
  avg10, avg60, avg300 : Float64                      # percent
  total                : Time::Span
```

### Storage

| Method                                     | Returns                                                      |
|--------------------------------------------|--------------------------------------------------------------|
| `system.storage.mounts`                    | `Array(Storage::Mount)`: device-backed, ZFS and Btrfs mounts |
| `system.storage.disk_io`                   | `Array(Storage::DiskIO)`                                     |
| `system.storage.block_devices`             | `Array(Storage::BlockDevice)`                                |
| `system.storage.swaps`                     | `Array(Storage::SwapDevice)`                                 |
| `system.storage.filesystem(path : String)` | `Storage::Filesystem?`                                       |

Loop and RAM devices are excluded.

```crystal
Storage::Mount
  device, mount_point, fs_type                : String
  options                                     : Array(String)
  total_bytes, free_bytes, available_bytes    : UInt64
  read_only? : Bool

Storage::Filesystem
  total_bytes, free_bytes, available_bytes    : UInt64
  inodes_total, inodes_free                   : UInt64

Storage::DiskIO
  device                                      : String
  reads_completed, writes_completed           : UInt64
  bytes_read, bytes_written                   : UInt64
  io_ticks                                    : UInt64   # milliseconds

Storage::BlockDevice
  name, model, serial, scheduler              : String
  size_bytes                                  : UInt64
  rotational                                  : Bool
  partitions                                  : Array(Storage::Partition)

Storage::Partition
  name       : String
  size_bytes : UInt64

Storage::SwapDevice
  path, kind              : String
  size_bytes, used_bytes  : UInt64
  priority                : Int32
```

### Network

| Method                                            | Returns                                                           |
|---------------------------------------------------|-------------------------------------------------------------------|
| `system.network.interfaces`                       | `Array(Network::Interface)`                                       |
| `system.network.wifi`                             | `Array(Network::WiFi)`                                            |
| `system.network.routes`                           | `Array(Network::Route)`: IPv4 routing table                       |
| `system.network.sockets(resolve_process = false)` | `Array(Network::Socket)`                                          |
| `system.network.arp_cache`                        | `Array(Network::ArpEntry)`                                        |
| `system.network.sampler`                          | `Sampler(Array(Network::Interface), Hash(String, Network::Rate))` |

`resolve_process: true` scans every process's file descriptors to fill in `pid` and `process`.

```crystal
Network::Interface
  name, mac_address, operstate                    : String
  mtu                                             : Int32
  speed_mbps                                      : Int32   # -1 when unknown
  addresses                                       : Array(Network::InterfaceAddress)
  rx_bytes, rx_packets, rx_errors, rx_dropped     : UInt64
  tx_bytes, tx_packets, tx_errors, tx_dropped     : UInt64
  up? : Bool
  rate_since(previous : Network::Interface, interval : Time::Span) : Network::Rate

Network::InterfaceAddress
  family  : String                                # "inet" | "inet6"
  address : String

Network::Rate
  rx_bytes_per_sec, tx_bytes_per_sec, rx_packets_per_sec, tx_packets_per_sec : Float64

Network::WiFi
  name                               : String
  link_quality, signal_dbm, noise_dbm : Float64

Network::Socket
  protocol                : String                # "tcp4" | "udp4" | "tcp6" | "udp6"
  local_ip, remote_ip     : String
  local_port, remote_port : Int32
  state                   : String                # TCP state name, or "ACTIVE" / "CLOSE" for UDP
  inode                   : UInt64
  pid                     : Int32?
  process                 : String?

Network::Route
  destination, gateway, mask, interface                  : String
  flags, ref_count, use, metric, mtu, window, irtt        : Int32

Network::ArpEntry
  ip, hw_type, flags, hw_address, mask, device : String
```

### Process

| Method                                                      | Returns                                                 |
|-------------------------------------------------------------|---------------------------------------------------------|
| `system.process.list(sort = :cpu, limit = nil, io = false)` | `Array(Process::Info)`                                  |
| `system.process.details(pid : Int32)`                       | `Process::Details?`: `nil` if the process doesn't exist |

`sort` is a `Process::Sort` (`CPU`, `Memory` or `PID`). `CPU` sorts by cumulative CPU time and `Memory` by RSS, both descending. `io: true` populates `Process::Info#io`.

```crystal
Process::Info
  pid, ppid                                            : Int32
  uid                                                  : UInt32
  user, name                                           : String
  cmdline                                              : Array(String)
  state                                                : Char
  utime, stime                                         : UInt64   # clock ticks
  threads                                              : Int32
  fd_count                                             : UInt32
  rss_bytes, vsize_bytes                               : UInt64
  memory_percent                                       : Float64
  seccomp                                              : Process::Seccomp
  no_new_privs                                         : Bool
  voluntary_ctxt_switches, nonvoluntary_ctxt_switches  : UInt64
  io                                                   : Process::IO?
  exe, cwd                                             : String?
  cpu_ticks : UInt64

Process::IO
  read_chars, write_chars, read_bytes, write_bytes : UInt64

enum Process::Seccomp
  Disabled | Strict | Filter | Unknown

Process::Details
  pid          : Int32
  cgroups      : Array(Process::CGroup)
  unified_path : String?                           # cgroup v2 path
  namespaces   : Array(Process::Namespace)
  capabilities : Process::Capabilities
  fds          : Process::FDSummary

Process::CGroup
  hierarchy_id : Int32
  controllers  : Array(String)
  path         : String
  unified?     : Bool

Process::Namespace
  kind  : String
  inode : UInt64

Process::Capabilities
  inheritable, permitted, effective, bounding, ambient : Process::CapabilitySet

Process::CapabilitySet
  mask         : UInt64
  capabilities : Array(String)                     # e.g. "CAP_NET_ADMIN"
  includes?(name : String) : Bool
  full?  : Bool
  empty? : Bool

Process::FDSummary
  total   : UInt32
  groups  : Array(Process::FDGroup)
  sockets : Array(UInt64)                          # socket inodes

Process::FDGroup
  kind   : Process::FDKind
  count  : UInt32
  inodes : Array(UInt64)                           # populated for sockets and pipes

enum Process::FDKind
  File | Directory | Socket | Pipe | AnonInode | CharDevice | Other
```

### Power

| Method                  | Returns                |
|-------------------------|------------------------|
| `system.power.supplies` | `Array(Power::Supply)` |

```crystal
Power::Supply
  name, kind, status                                           : String
  present                                                      : Bool
  online                                                       : Bool?
  capacity_percent                                             : Int32?
  energy_now_uwh, energy_full_uwh, energy_full_design_uwh      : Int64?
  power_now_uw, voltage_now_uv                                 : Int64?
  charge_now_uah, charge_full_uah, charge_full_design_uah      : Int64?
  current_now_ua                                               : Int64?
  cycle_count                                                  : Int32?
  time_remaining                                               : Time::Span?
  charging?      : Bool
  discharging?   : Bool
  health_percent : Int32?
```

When the kernel doesn't report `capacity_percent` and `power_now_uw`, they are derived from the energy/charge and current/voltage readings. `time_remaining` is an estimate, available only while charging or discharging.

### Graphics

| Method                     | Returns                    |
|----------------------------|----------------------------|
| `system.graphics.gpus`     | `Array(Graphics::GPU)`     |
| `system.graphics.displays` | `Array(Graphics::Display)` |

```crystal
Graphics::GPU
  name, vendor                : String
  busy_percent                : Int32?
  vram_total_mb, vram_used_mb : UInt64
  core_mhz                    : Float64

Graphics::Display
  name                    : String
  connected               : Bool
  resolution, dpms_state  : String
```

### Sensors

| Method                 | Returns                |
|------------------------|------------------------|
| `system.sensors.hwmon` | `Array(Sensors::Chip)` |

```crystal
Sensors::Chip
  name    : String
  sensors : Array(Sensors::Sensor)

Sensors::Sensor
  label : String
  kind  : Sensors::Kind
  value : Float64

enum Sensors::Kind
  Temperature   # °C
  Fan           # RPM
  Voltage       # V
```

### Devices

| Method                          | Returns                        |
|---------------------------------|--------------------------------|
| `system.devices.usb_devices`    | `Array(Devices::USB)`          |
| `system.devices.pci_devices`    | `Array(Devices::PCI)`          |
| `system.devices.kernel_modules` | `Array(Devices::KernelModule)` |

```crystal
Devices::USB
  vendor_id, product_id, manufacturer, product : String

Devices::PCI
  address, vendor_id, device_id, class_id : String   # IDs as hex without "0x"

Devices::KernelModule
  name       : String
  size_bytes : UInt64
  ref_count  : UInt32
```

### Host

| Method              | Returns             |
|---------------------|---------------------|
| `system.host.info`  | `Host::Info`        |
| `system.host.users` | `Array(Host::User)` |

```crystal
Host::Info
  virtual_machine  : String?                       # product name when virtualized
  container        : String?                       # "Docker", "Podman/CRI-O", "LXC", "Kubernetes"
  virtual_machine? : Bool
  container?       : Bool

Host::User
  name, tty  : String
  login_time : Time
```

### Limits

| Method                           | Returns                   |
|----------------------------------|---------------------------|
| `system.limits.file_descriptors` | `Limits::FileDescriptors` |
| `system.limits.threads`          | `Limits::Threads`         |

```crystal
Limits::FileDescriptors
  allocated, maximum : UInt64
  used : UInt64

Limits::Threads
  pid_max, threads_max : UInt64
```

### `Sysdat::Sampler(Reading, Rate)`

| Member                                                                 | Description                                                                                |
|------------------------------------------------------------------------|--------------------------------------------------------------------------------------------|
| `.new(read : -> Reading, rate : Reading, Reading, Time::Span -> Rate)` | Takes the initial reading immediately.                                                     |
| `.new(previous : Reading, read, rate)`                                 | Seeds the sampler with an existing reading.                                                |
| `#sample : Rate`                                                       | Reads, computes the rate from `(previous, current, interval)`, and stores the new reading. |

Custom samplers can be built from any facade method:

```crystal
disk = Sysdat::Sampler(Array(Sysdat::Storage::DiskIO), Hash(String, Float64)).new(
  -> { system.storage.disk_io },
  ->(previous : Array(Sysdat::Storage::DiskIO), current : Array(Sysdat::Storage::DiskIO), interval : Time::Span) {
    before = previous.to_h { |device| {device.device, device.bytes_read} }
    current.each_with_object({} of String => Float64) do |device, rates|
      if bytes = before[device.device]?
        rates[device.device] = (device.bytes_read.to_f - bytes.to_f) / interval.total_seconds
      end
    end
  }
)
```

### `Sysdat::Format`

| Method                                                                     | Example       |
|----------------------------------------------------------------------------|---------------|
| `bytes(value : Int, binary = true, precision = 1) : String`                | `"15.3 GiB"`  |
| `bytes_per_second(value : Float64, binary = true, precision = 1) : String` | `"1.2 MiB/s"` |
| `hertz(mhz : Float64, precision = 2) : String`                             | `"4.4 GHz"`   |

### Errors

`Sysdat::Error` is raised by:

- `os.info` when `uname` fails
- `kernel.stats` and `cpu.stats` when `/proc/stat` is unavailable
- `cpu.info` when `/proc/cpuinfo` is unavailable
- `memory.read` when `/proc/meminfo` is unavailable
- `process.list` when `/proc` cannot be listed
- `Network::Interface#rate_since` when the interval is not positive
- `snapshot`, transitively

### Collectors

Each facade method is backed by a collector class, for example `CPU::InfoCollector` or `Process::Collector`. Every collector includes `Sysdat::Collector(T)` and implements `collect : T`. Collectors can be instantiated directly when a facade is unnecessary, and `Sysdat::Collector(T)` can be included to write your own.

## Example

`examples/basic.cr` prints a colorized report of the whole system:

```sh
crystal run examples/basic.cr
```

## License

MIT. See `LICENSE`.

## Contributors

- shpeckman <geelenrobin@proton.me>