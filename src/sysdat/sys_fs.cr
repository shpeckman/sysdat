# src/sysdat/sys_fs.cr
require "compress/gzip"

module Sysdat::SysFS
  extend self

  def read_line(path : String) : String?
    File.open(path) { |file| file.gets(chomp: true) }
  rescue IO::Error
    nil
  end

  def read_all(path : String) : String?
    File.read(path)
  rescue IO::Error
    nil
  end

  def read_gzip(path : String) : String?
    File.open(path) do |file|
      Compress::Gzip::Reader.open(file, &.gets_to_end)
    end
  rescue IO::Error | Compress::Gzip::Error
    nil
  end

  def read_int(path : String) : Int64?
    read_line(path).try(&.strip.to_i64?(strict: false))
  end

  def read_lines(path : String, & : String ->) : Bool
    file = begin
      File.open(path)
    rescue IO::Error
      return false
    end

    begin
      file.each_line { |line| yield line }
    rescue IO::Error
    ensure
      file.close
    end

    true
  end

  def children(path : String) : Array(String)
    Dir.children(path).sort!
  rescue IO::Error
    [] of String
  end

  def count_children(path : String) : UInt32
    count = 0_u32
    Dir.each_child(path) { count += 1 }
    count
  rescue IO::Error
    0_u32
  end

  def string_from(bytes) : String
    slice  = bytes.to_slice
    length = slice.index(0_u8) || slice.size
    String.new(slice[0, length])
  end

  def readlink(path : String) : String?
    File.readlink(path)
  rescue IO::Error
    nil
  end
end
