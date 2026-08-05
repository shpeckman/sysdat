# src/sysdat/storage.cr
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
    inodes_free     : UInt64

  record Mount,
    device          : String,
    mount_point     : String,
    fs_type         : String,
    total_bytes     : UInt64,
    free_bytes      : UInt64,
    available_bytes : UInt64

  record DiskIO,
    device           : String,
    reads_completed  : UInt64,
    writes_completed : UInt64,
    bytes_read       : UInt64,
    bytes_written    : UInt64,
    io_ticks         : UInt64

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
      next if fields.size < 3

      device, mount_point, fs_type = fields[0], fields[1], fields[2]
      next unless device.starts_with?('/') || POOLED_FS_TYPES.includes?(fs_type)
      next if SKIPPED_FS_TYPES.includes?(fs_type)

      usage = filesystem(mount_point)
      mounts << Mount.new(
        device: device,
        mount_point: mount_point,
        fs_type: fs_type,
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
end
