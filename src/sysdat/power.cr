# src/sysdat/power.cr
module Sysdat
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
      status == "Charging"
    end

    def discharging? : Bool
      status == "Discharging"
    end

    def health_percent : Int32?
      if (ef = energy_full_uwh) && (efd = energy_full_design_uwh) && efd > 0
        (ef * 100 // efd).to_i32
      elsif (cf = charge_full_uah) && (cfd = charge_full_design_uah) && cfd > 0
        (cf * 100 // cfd).to_i32
      else
        nil
      end
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

    energy_now         = SysFS.read_int("#{base}/energy_now")
    energy_full        = SysFS.read_int("#{base}/energy_full")
    energy_full_design = SysFS.read_int("#{base}/energy_full_design")
    power_now          = SysFS.read_int("#{base}/power_now")
    voltage_now        = SysFS.read_int("#{base}/voltage_now")
    charge_now         = SysFS.read_int("#{base}/charge_now")
    charge_full        = SysFS.read_int("#{base}/charge_full")
    charge_full_design = SysFS.read_int("#{base}/charge_full_design")
    current_now        = SysFS.read_int("#{base}/current_now")
    cycle_count        = SysFS.read_int("#{base}/cycle_count").try(&.to_i32)

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
      energy_full_design_uwh: energy_full_design,
      power_now_uw: power_now,
      voltage_now_uv: voltage_now,
      charge_now_uah: charge_now,
      charge_full_uah: charge_full,
      charge_full_design_uah: charge_full_design,
      current_now_ua: current_now,
      cycle_count: cycle_count,
      time_remaining: time_remaining,
    )
  end
end
