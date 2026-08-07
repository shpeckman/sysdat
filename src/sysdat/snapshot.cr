# src/sysdat/snapshot.cr
module Sysdat
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
    captured_at      : Time do
    include JSON::Serializable
  end
end
