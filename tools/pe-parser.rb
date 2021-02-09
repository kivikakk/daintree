#!/usr/bin/env ruby

def relo_decode(e)
  relo_type = {
    0 => :IMAGE_REL_BASED_ABSOLUTE,
    1 => :IMAGE_REL_BASED_HIGH,
    2 => :IMAGE_REL_BASED_LOW,
    3 => :IMAGE_REL_BASED_HIGHLOW,
    4 => :IMAGE_REL_BASED_HIGHADJ,
    5 => :IMAGE_REL_BASED_ARM_MOV32,  # Assuming ARM.
    10 => :IMAGE_REL_BASED_DIR64,
  }[e >> 12]
  raise "unknown relo_type #{e >> 12}" if !relo_type
  [relo_type, e & 0xfff]
end

pe = File.open(ARGV[0], "rb", &:read)

raise "no MZ" if pe[0...2] != "MZ"
coff_offset = pe[0x3c...0x40].unpack('V')[0]
raise "no PE signature" if pe[coff_offset...coff_offset+4] != "PE\x00\x00".b
machine, section_count, timestamp, _, _, optional_header_size, _ = pe[coff_offset+4...coff_offset+4+20].unpack('vvVVVvv')

printf "machine type: %04x\n", machine
puts "sections: #{section_count}"
puts "created: #{Time.at timestamp}"

if optional_header_size > 0
  opth = pe[coff_offset+4+20...coff_offset+4+20+optional_header_size]
  case magic = opth[0...2].unpack('v')[0]
  when 0x10b
    puts "PE32 (unimpl)"
  when 0x20b
    puts "PE32+"
    lvmaj, lvmin, code_size, init_data_size, uninit_data_size, entry_point_relative, code_base,
      image_base, section_alignment, file_alignment, osvermaj, osvermin, imagevermaj, imagevermin,
      subsysvermaj, subsysvermin, _, imgsize, hdrsize, _, subsys, _, _, _, _, _, _, dd_count =
      opth[2..-1].unpack('CCVVVVVQ<VVvvvvvvVVVVvvQ<Q<Q<Q<VV')
    puts "linker version #{lvmaj}.#{lvmin}"
    puts "sizes:        code: #{code_size}"
    puts "         init data: #{init_data_size}"
    puts "       uninit data: #{uninit_data_size}"
    printf "entry point: 0x%08x\n", entry_point_relative
    printf "bases:  code: 0x%08x\n", code_base
    printf "       image: 0x%08x\n", image_base
    puts "section align #{section_alignment}, file align #{file_alignment}"
    puts "requires OS version #{osvermaj}.#{osvermin}"
    puts "image version #{imagevermaj}.#{imagevermin}"
    puts "subsystem version #{subsysvermaj}.#{subsysvermin}"
    puts "  image size: #{imgsize}"
    puts "headers size: #{hdrsize}"
    puts "subsystem: #{subsys}#{subsys == 10 ? " (EFI application)" : ""}"
    dd_entries = opth[112...112+dd_count*8].unpack('V*').each_slice(2).to_a

    sections = Hash[pe[coff_offset+4+20+optional_header_size...coff_offset+4+20+optional_header_size+section_count*40].bytes.each_slice(40).map do |sect|
      name, virt_size, virt_addr, file_size, file_offset, _, _, _, _, _  = sect.pack('C*').unpack('Z8VVVVVVvvV')
      printf "section % 6s: virt 0x%08x len %08x -- phys 0x%08x len %08x\n", name, virt_addr, virt_size, file_offset, file_size
      [name, {
        virt_size: virt_size,
        virt_addr: virt_addr,
        file_size: file_size,
        file_offset: file_offset,
      }]
    end]

    if dd_entries[5]
      va, sz = dd_entries[5]
      reloc_data = pe[sections[".reloc"][:file_offset] - sections[".reloc"][:virt_addr] + va..-1][0...sz]
      while reloc_data.length > 0
        page_rva, block_size = reloc_data.unpack('VV')
        entries = reloc_data[8...block_size].unpack('v*')
        reloc_data = reloc_data[block_size..-1]
        puts "Page RVA: 0x#{page_rva.to_s 16}"
        entries.map! { |e| relo_decode(e) }
        entries.select! { |relo_type, _| relo_type == :IMAGE_REL_BASED_DIR64 }
        puts "#{entries.length} relocations:"
        entries.each_slice(8) do |s|
          print "  "
          puts s.map { |_, offset| sprintf("0x%04x", page_rva+offset) }.join(" ")
        end
      end
    end
  else
    raise "unknown optional header magic 0x#{magic.to_s 16}"
  end
end
