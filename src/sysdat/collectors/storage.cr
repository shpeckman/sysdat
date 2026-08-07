# src/sysdat/collectors/storage.cr
module Sysdat
  POOLED_FS_TYPES  = {"zfs", "btrfs"}
  SKIPPED_FS_TYPES = {"tmpfs", "devtmpfs"}

  IGNORED_BLOCK_PREFIXES = {"loop", "ram"}

  SECTOR_SIZE = 512_u64

  record Filesystem,
    total_bytes     : UInt64,
    free_bytes      : UInt64,
    available_bytes : UInt64,
    inodes_total    : UInt64,
    inodes_free     : UInt64 do
    include JSON::Serializable
  end

  record Mount,
    device          : String,
    mount_point     : String,
    fs_type         : String,
    options         : Array(String),
    total_bytes     : UInt64,
    free_bytes      : UInt64,
    available_bytes : UInt64 do
    include JSON::Serializable

    def read_only? : Bool
      options.includes?("ro")
    end
  end

  record DiskIO,
    device           : String,
    reads_completed  : UInt64,
    writes_completed : UInt64,
    bytes_read       : UInt64,
    bytes_written    : UInt64,
    io_ticks         : UInt64 do
    include JSON::Serializable
  end

  record Partition,
    name       : String,
    size_bytes : UInt64 do
    include JSON::Serializable
  end

  record BlockDevice,
    name       : String,
    model      : String,
    serial     : String,
    size_bytes : UInt64,
    rotational : Bool,
    scheduler  : String,
    partitions : Array(Partition) do
    include JSON::Serializable
  end

  record SwapDevice,
    path       : String,
    kind       : String,
    size_bytes : UInt64,
    used_bytes : UInt64,
    priority   : Int32 do
    include JSON::Serializable
  end

  def self.filesystem(path : String) : Filesystem?
    stat = uninitialized LibSys::StatVFS
    return nil unless LibSys.statvfs(path.check_no_null_byte, pointerof(stat)) == 0

    fragment_size = stat.f_frsize.to_u64
    Filesystem.new(
      total_bytes: stat.f_blocks * fragment_size,
      free_bytes: stat.f_bfree * fragment_size,
      available_bytes: stat.f_bavail * fragment_size,
      inodes_total: stat.f_files,
      inodes_free: stat.f_ffree,
    )
  end

  def self.mounts : Array(Mount)
    mounts = [] of Mount

    SysFS.read_lines("/proc/mounts") do |line|
      fields = line.split
      next if fields.size < 4

      device, mount_point, fs_type = fields[0], fields[1], fields[2]
      next unless device.starts_with?('/') || POOLED_FS_TYPES.includes?(fs_type)
      next if SKIPPED_FS_TYPES.includes?(fs_type)

      usage = filesystem(mount_point)
      mounts << Mount.new(
        device: device,
        mount_point: mount_point,
        fs_type: fs_type,
        options: fields[3].split(','),
        total_bytes: usage.try(&.total_bytes) || 0_u64,
        free_bytes: usage.try(&.free_bytes) || 0_u64,
        available_bytes: usage.try(&.available_bytes) || 0_u64,
      )
    end

    mounts
  end

  def self.disk_io : Array(DiskIO)
    disks = [] of DiskIO

    SysFS.read_lines("/proc/diskstats") do |line|
      fields = line.split
      next if fields.size < 13

      device = fields[2]
      next if IGNORED_BLOCK_PREFIXES.any? { |prefix| device.starts_with?(prefix) }

      disks << DiskIO.new(
        device: device,
        reads_completed: fields[3].to_u64? || 0_u64,
        writes_completed: fields[7].to_u64? || 0_u64,
        bytes_read: (fields[5].to_u64? || 0_u64) * SECTOR_SIZE,
        bytes_written: (fields[9].to_u64? || 0_u64) * SECTOR_SIZE,
        io_ticks: fields[12].to_u64? || 0_u64,
      )
    end

    disks
  end

  def self.block_devices : Array(BlockDevice)
    devices = [] of BlockDevice

    SysFS.children("/sys/block").each do |entry|
      next if IGNORED_BLOCK_PREFIXES.any? { |prefix| entry.starts_with?(prefix) }

      base         = "/sys/block/#{entry}"
      size_sectors = SysFS.read_int("#{base}/size") || 0_i64
      rotational   = SysFS.read_int("#{base}/queue/rotational") == 1

      devices << BlockDevice.new(
        name: entry,
        model: SysFS.read_line("#{base}/device/model").try(&.strip) || "Unknown",
        serial: SysFS.read_line("#{base}/device/serial").try(&.strip) || "",
        size_bytes: size_sectors.to_u64 * SECTOR_SIZE,
        rotational: rotational,
        scheduler: Parsers.parse_scheduler(SysFS.read_line("#{base}/queue/scheduler")),
        partitions: read_partitions(base, entry),
      )
    end

    devices
  end

  def self.swaps : Array(SwapDevice)
    devices = [] of SwapDevice

    SysFS.read_lines("/proc/swaps") do |line|
      next if line.starts_with?("Filename")
      fields = line.split
      next if fields.size < 5

      size_kb = fields[2].to_u64?(strict: false) || 0_u64
      used_kb = fields[3].to_u64?(strict: false) || 0_u64

      devices << SwapDevice.new(
        path: fields[0],
        kind: fields[1],
        size_bytes: size_kb * 1024,
        used_bytes: used_kb * 1024,
        priority: fields[4].to_i?(strict: false) || -1
      )
    end

    devices
  end

  private def self.read_partitions(base : String, device : String) : Array(Partition)
    partitions = [] of Partition

    SysFS.children(base).each do |entry|
      next unless entry.starts_with?(device)
      part_base = "#{base}/#{entry}"
      next unless File.exists?("#{part_base}/partition")

      size_sectors = SysFS.read_int("#{part_base}/size") || 0_i64
      partitions << Partition.new(
        name: entry,
        size_bytes: size_sectors.to_u64 * SECTOR_SIZE,
      )
    end

    partitions
  end
end
