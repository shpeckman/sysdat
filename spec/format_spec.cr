# spec/format_spec.cr
require "./spec_helper"

describe Sysdat::Format do
  describe ".bytes" do
    it "renders sub-kibibyte values without a decimal" do
      Sysdat::Format.bytes(0).should eq("0 B")
      Sysdat::Format.bytes(512).should eq("512 B")
    end

    it "scales into binary units" do
      Sysdat::Format.bytes(1024).should eq("1.0 KiB")
      Sysdat::Format.bytes(1536).should eq("1.5 KiB")
      Sysdat::Format.bytes(5_368_709_120).should eq("5.0 GiB")
    end

    it "supports decimal units" do
      Sysdat::Format.bytes(1500, binary: false).should eq("1.5 KB")
    end

    it "preserves the sign for negative values" do
      Sysdat::Format.bytes(-2048).should eq("-2.0 KiB")
    end
  end

  describe ".bytes_per_second" do
    it "appends a per-second suffix" do
      Sysdat::Format.bytes_per_second(2_500_000.0).should eq("2.4 MiB/s")
      Sysdat::Format.bytes_per_second(0.0).should eq("0 B/s")
    end
  end

  describe ".hertz" do
    it "keeps sub-gigahertz values in MHz" do
      Sysdat::Format.hertz(800.0).should eq("800.0 MHz")
    end

    it "promotes gigahertz-scale values" do
      Sysdat::Format.hertz(2100.0).should eq("2.1 GHz")
      Sysdat::Format.hertz(3600.5).should eq("3.6 GHz")
    end
  end
end
