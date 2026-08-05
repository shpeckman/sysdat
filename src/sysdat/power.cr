# src/sysdat/power.cr
module Sysdat
  struct PowerSupply
    getter name             : String
    getter kind             : String
    getter status           : String
    getter present          : Bool
    getter online           : Bool?
    getter capacity_percent : Int32?
    getter energy_now_uwh   : Int64?
    getter energy_full_uwh  : Int64?
    getter power_now_uw     : Int64?
    getter voltage_now_uv   : Int64?
    getter charge_now_uah   : Int64?
    getter charge_full_uah  : Int64?
    getter current_now_ua   : Int64?
    getter time_remaining   : Time::Span?

    def initialize(@name, @kind, @status, @present, @online, @capacity_percent,
                   @energy_now_uwh, @energy_full_uwh, @power_now_uw, @voltage_now_uv,
                   @charge_now_uah, @charge_full_uah, @current_now_ua, @time_remaining)
    end

    def charging? : Bool
      status == "Charging"
    end

    def discharging? : Bool
      status == "Discharging"
    end
  end

  def self.power_supplies : Array(PowerSupply)
    SysFS.children("/sys/class/power_supply").map { |name| read_power_supply(name) }
  end

  private def self.read_power_supply(name : String) : PowerSupply
    base = "/sys/class/power_supply/#{name}"

    kind = SysFS.read_line("#{base}/type") || ""
    kind = "Unknown" if kind.empty?

    online  = SysFS.read_int("#{base}/online").try { |value| value > 0 }
    present = (SysFS.read_int("#{base}/present") || 0) > 0

    status = SysFS.read_line("#{base}/status") || ""
    if status.empty?
      status = case online
               when true  then "Online"
               when false then "Offline"
               else            "Unknown"
               end
    end

    energy_now  = SysFS.read_int("#{base}/energy_now")
    energy_full = SysFS.read_int("#{base}/energy_full")
    power_now   = SysFS.read_int("#{base}/power_now")
    voltage_now = SysFS.read_int("#{base}/voltage_now")
    charge_now  = SysFS.read_int("#{base}/charge_now")
    charge_full = SysFS.read_int("#{base}/charge_full")
    current_now = SysFS.read_int("#{base}/current_now")

    capacity = SysFS.read_int("#{base}/capacity").try(&.to_i32)
    if capacity.nil?
      if energy_now && energy_full && energy_full > 0
        capacity = (energy_now * 100 // energy_full).to_i32
      elsif charge_now && charge_full && charge_full > 0
        capacity = (charge_now * 100 // charge_full).to_i32
      end
    end

    if power_now.nil? && current_now && voltage_now && voltage_now > 0
      power_now = current_now.abs * voltage_now // 1_000_000
    end

    time_remaining = nil
    if status == "Charging" || status == "Discharging"
      charging  = status == "Charging"
      rate      = 0.0
      remaining = 0.0

      if power_now && power_now > 0 && energy_now && energy_full && energy_full > 0
        rate      = power_now.to_f
        remaining = charging ? (energy_full - energy_now).to_f : energy_now.to_f
      elsif current_now && charge_now && charge_full && charge_full > 0
        rate      = current_now.abs.to_f
        remaining = charging ? (charge_full - charge_now).to_f : charge_now.to_f
      end

      time_remaining = span_from_hours(remaining / rate) if rate > 0.0 && remaining > 0.0
    end

    PowerSupply.new(
      name: name,
      kind: kind,
      status: status,
      present: present,
      online: online,
      capacity_percent: capacity,
      energy_now_uwh: energy_now,
      energy_full_uwh: energy_full,
      power_now_uw: power_now,
      voltage_now_uv: voltage_now,
      charge_now_uah: charge_now,
      charge_full_uah: charge_full,
      current_now_ua: current_now,
      time_remaining: time_remaining,
    )
  end
end
