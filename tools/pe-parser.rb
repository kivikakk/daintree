#!/usr/bin/env ruby

pe = File.open(ARGV[0], "rb", &:read)

raise "no MZ" if pe[0...2] != "MZ"
coff_offset = pe[0x3c...0x40].unpack('V')[0]
raise "no PE signature" if pe[coff_offset...coff_offset+4] != "PE\x00\x00".b
machine, section_count, timestamp, _, _, optional_header_size, _ = pe[coff_offset+4...coff_offset+4+20].unpack('vvVVVvv')

puts "machine type: #{machine.to_s(16).rjust(4, "0")}"
puts "sections: #{section_count}"
puts "created: #{Time.at timestamp}"

if optional_header_size > 0
  opth = pe[coff_offset+4+20...coff_offset+4+20+optional_header_size]
  case magic = opth[0...2].unpack('v')[0]
  when 0x10b
    puts "PE32 (unimpl)"
  when 0x20b
    puts "PE32+"
    lvmaj, lvmin, code_size, init_data_size, uninit_data_size, entry_point_relative, code_base, data_base =
      opth[2..-1].unpack('CCVVVVVV')
    puts "linker version #{lvmaj}.#{lvmin}"
    puts "sizes:        code: #{code_size}"
    puts "         init data: #{init_data_size}"
    puts "       uninit data: #{uninit_data_size}"
    puts "entry point: 0x#{entry_point_relative.to_s 16}"
    puts "bases: code: 0x#{code_base.to_s 16}"
    puts "       data: 0x#{data_base.to_s 16}"
  else
    raise "unknown optional header magic 0x#{magic.to_s 16}"
  end
end
