# src/sysdat/devices.cr
module Sysdat
  struct USBDevice
    getter vendor_id : String
    getter product_id : String
    getter manufacturer : String
    getter product : String

    def initialize(@vendor_id, @product_id, @manufacturer, @product)
    end
  end

  struct PCIDevice
    getter address : String
    getter vendor_id : String
    getter device_id : String
    getter class_id : String

    def initialize(@address, @vendor_id, @device_id, @class_id)
    end
  end

  struct KernelModule
    getter name : String
    getter size_bytes : UInt64
    getter ref_count : UInt32

    def initialize(@name, @size_bytes, @ref_count)
    end
  end

  def self.usb_devices : Array(USBDevice)
    SysFS.children("/sys/bus/usb/devices").compact_map do |entry|
      base = "/sys/bus/usb/devices/#{entry}"
      vendor_id = SysFS.read_line("#{base}/idVendor")
      next unless vendor_id

      USBDevice.new(
        vendor_id: vendor_id,
        product_id: SysFS.read_line("#{base}/idProduct") || "Unknown",
        manufacturer: SysFS.read_line("#{base}/manufacturer") || "",
        product: SysFS.read_line("#{base}/product") || "Unknown Device",
      )
    end
  end

  def self.pci_devices : Array(PCIDevice)
    SysFS.children("/sys/bus/pci/devices").map do |entry|
      base = "/sys/bus/pci/devices/#{entry}"

      PCIDevice.new(
        address: entry,
        vendor_id: hex_id("#{base}/vendor"),
        device_id: hex_id("#{base}/device"),
        class_id: hex_id("#{base}/class"),
      )
    end
  end

  def self.kernel_modules : Array(KernelModule)
    modules = [] of KernelModule

    SysFS.read_lines("/proc/modules") do |line|
      fields = line.split
      next if fields.size < 3

      modules << KernelModule.new(
        name: fields[0],
        size_bytes: fields[1].to_u64? || 0_u64,
        ref_count: fields[2].to_u32? || 0_u32,
      )
    end

    modules
  end

  private def self.hex_id(path : String) : String
    (SysFS.read_line(path) || "").strip.lchop("0x")
  end
end
