# src/sysdat/collectors/host.cr
module Sysdat::Host
  VM_PRODUCT_MARKERS = {"KVM", "VirtualBox", "VMware", "Bochs"}
  VM_VENDOR_MARKERS  = {"QEMU"}

  CONTAINER_FILES = {
    {"/.dockerenv",        "Docker"},
    {"/run/.containerenv", "Podman/CRI-O"},
  }

  CONTAINER_CGROUP_MARKERS = {
    {"docker",   "Docker"},
    {"lxc",      "LXC"},
    {"kubepods", "Kubernetes"},
  }

  record Info,
    virtual_machine : String?,
    container       : String? do
    include JSON::Serializable

    def virtual_machine? : Bool
      !virtual_machine.nil?
    end

    def container? : Bool
      !container.nil?
    end
  end

  record User,
    name       : String,
    tty        : String,
    login_time : Time do
    include JSON::Serializable
  end

  class Collector
    include Sysdat::Collector(Info)

    def collect : Info
      product = SysFS.read_line("/sys/class/dmi/id/product_name") || ""
      vendor  = SysFS.read_line("/sys/class/dmi/id/sys_vendor") || ""

      virtual_machine = nil
      if VM_PRODUCT_MARKERS.any? { |marker| product.includes?(marker) } ||
         VM_VENDOR_MARKERS.any? { |marker| vendor.includes?(marker) }
        virtual_machine = product
      end

      Info.new(virtual_machine, Host.detect_container)
    end
  end

  def self.users : Array(User)
    users = [] of User

    LibSys.setutent
    begin
      loop do
        pointer = LibSys.getutent
        break if pointer.null?

        entry = pointer.value
        next unless entry.ut_type == LibSys::USER_PROCESS

        users << User.new(
          name: SysFS.string_from(entry.ut_user),
          tty: SysFS.string_from(entry.ut_line),
          login_time: Time.unix(entry.ut_tv.tv_sec.to_i64),
        )
      end
    ensure
      LibSys.endutent
    end

    users
  end

  protected def self.detect_container : String?
    CONTAINER_FILES.each do |(path, name)|
      return name if File.exists?(path)
    end

    container = nil
    SysFS.read_lines("/proc/1/cgroup") do |line|
      CONTAINER_CGROUP_MARKERS.each do |(marker, name)|
        if line.includes?(marker)
          container = name
          break
        end
      end
      break if container
    end

    container
  end

  class Facade
    def initialize(@system : Sysdat::System)
    end

    def info : Info
      Collector.new.collect
    end

    def users : Array(User)
      Host.users
    end
  end
end
