# src/sysdat/lib_sys.cr
@[Link("c")]
lib LibSys
  SC_PAGESIZE  = 30
  USER_PROCESS =  7

  struct StatVFS
    f_bsize : LibC::ULong
    f_frsize : LibC::ULong
    f_blocks : UInt64
    f_bfree : UInt64
    f_bavail : UInt64
    f_files : UInt64
    f_ffree : UInt64
    f_favail : UInt64
    f_fsid : LibC::ULong
    f_flag : LibC::ULong
    f_namemax : LibC::ULong
    f_type : LibC::UInt
    f_spare : StaticArray(LibC::Int, 5)
  end

  struct UtsName
    sysname : StaticArray(UInt8, 65)
    nodename : StaticArray(UInt8, 65)
    release : StaticArray(UInt8, 65)
    version : StaticArray(UInt8, 65)
    machine : StaticArray(UInt8, 65)
    domainname : StaticArray(UInt8, 65)
  end

  struct UtmpExit
    e_termination : Int16
    e_exit : Int16
  end

  struct UtmpTimeval
    tv_sec : Int32
    tv_usec : Int32
  end

  struct Utmp
    ut_type : Int16
    ut_pid : LibC::PidT
    ut_line : StaticArray(UInt8, 32)
    ut_id : StaticArray(UInt8, 4)
    ut_user : StaticArray(UInt8, 32)
    ut_host : StaticArray(UInt8, 256)
    ut_exit : UtmpExit
    ut_session : Int32
    ut_tv : UtmpTimeval
    ut_addr_v6 : StaticArray(Int32, 4)
    ut_reserved : StaticArray(UInt8, 20)
  end

  fun statvfs(path : LibC::Char*, buffer : StatVFS*) : LibC::Int
  fun sysconf(name : LibC::Int) : LibC::Long
  fun uname(buffer : UtsName*) : LibC::Int
  fun setutent : Void
  fun getutent : Utmp*
  fun endutent : Void
end
