# src/sysdat/snapshot.cr
module Sysdat
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
    captured_at      : Time do
    include JSON::Serializable
  end

  def self.snapshot : Snapshot
    Snapshot.new(
      os: os,
      kernel: kernel_info,
      kernel_stats: kernel_stats,
      cpu: cpu,
      cpu_stats: cpu_stats,
      memory: memory,
      pressure: pressure,
      mounts: mounts,
      block_devices: block_devices,
      disk_io: disk_io,
      swaps: swaps,
      interfaces: interfaces,
      wifi: wifi,
      routes: routes,
      gpus: gpus,
      displays: displays,
      hwmon: hwmon,
      power_supplies: power_supplies,
      host: host,
      file_descriptors: file_descriptors,
      thread_limits: thread_limits,
      captured_at: Time.utc,
    )
  end
end
