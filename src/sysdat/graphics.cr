# src/sysdat/graphics.cr
module Sysdat
  GPU_VENDORS = {
    "0x8086" => "Intel",
    "0x1002" => "AMD",
    "0x10de" => "NVIDIA",
  }

  struct GPU
    getter name : String
    getter vendor : String
    getter busy_percent : Int32?
    getter vram_total_mb : UInt64
    getter vram_used_mb : UInt64
    getter core_mhz : Float64

    def initialize(@name, @vendor, @busy_percent, @vram_total_mb, @vram_used_mb, @core_mhz)
    end
  end

  struct Display
    getter name : String
    getter connected : Bool
    getter resolution : String
    getter dpms_state : String

    def initialize(@name, @connected, @resolution, @dpms_state)
    end
  end

  def self.gpus : Array(GPU)
    SysFS.children("/sys/class/drm").compact_map do |entry|
      next unless entry.starts_with?("card") && !entry.includes?('-')

      base = "/sys/class/drm/#{entry}"
      vendor_id = SysFS.read_line("#{base}/device/vendor").try(&.strip.downcase)

      GPU.new(
        name: entry,
        vendor: vendor_id.try { |id| GPU_VENDORS[id]? } || "Unknown",
        busy_percent: SysFS.read_int("#{base}/device/gpu_busy_percent").try(&.to_i32),
        vram_total_mb: megabytes(SysFS.read_int("#{base}/device/mem_info_vram_total")),
        vram_used_mb: megabytes(SysFS.read_int("#{base}/device/mem_info_vram_used")),
        core_mhz: SysFS.read_int("#{base}/gt_cur_freq_mhz").try(&.to_f) || 0.0,
      )
    end
  end

  def self.displays : Array(Display)
    SysFS.children("/sys/class/drm").compact_map do |entry|
      next unless entry.starts_with?("card")

      _, separator, connector = entry.partition('-')
      next if separator.empty?

      base = "/sys/class/drm/#{entry}"
      connected = SysFS.read_line("#{base}/status") == "connected"

      Display.new(
        name: connector,
        connected: connected,
        resolution: (connected ? SysFS.read_line("#{base}/modes") : nil) || "",
        dpms_state: (connected ? SysFS.read_line("#{base}/dpms") : nil) || "",
      )
    end
  end

  private def self.megabytes(bytes : Int64?) : UInt64
    bytes && bytes > 0 ? (bytes // (1024 * 1024)).to_u64 : 0_u64
  end
end
