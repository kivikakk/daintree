#!/usr/bin/env ruby

reloc_data = +"".b

state = :nothing
STDIN.lines.each do |line|
  case state
  when :nothing
    case line
    when /^Contents of section \.reloc:/
      state = :reloc
    end
  when :reloc
    case line
    when /^ [a-f0-9]{4} ([a-f0-9 ]{36}) /
      reloc_data << $1.scan(/[a-f0-9]{2}/).map { |b| b.to_i 16 }.pack('C*')
    else
      break
    end
  end
end

def decode_entry(e)
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

while reloc_data.length > 0
  page_rva, block_size = reloc_data.unpack('VV')
  entries = reloc_data[8...block_size].unpack('v*')
  reloc_data = reloc_data[block_size..-1]
  puts "Page RVA: 0x#{page_rva.to_s 16}"
  entries.map! { |e| decode_entry(e) }
  entries.select! { |relo_type, _| relo_type == :IMAGE_REL_BASED_DIR64 }
  puts "#{entries.length} relocations:"
  entries.each_slice(8) do |s|
    print "  "
    puts s.map { |_, offset| "0x#{(page_rva + offset).to_s 16}" }.join(" ")
  end
end

__END__

Contents of something:
 cfe0 aaaaaaaa bbbbbbbb dddddddd eeeeeeee  ................
Contents of section .reloc:
 d000 00a00000 40000000 a8acb8ac c8acd8ac  ....@...........
 d010 e8acf8ac 08ad18ad 28ad38ad 48ad58ad  ........(.8.H.X.
 d020 68ad78ad c8add8ad 10ae40ae 90aeb0ae  h.x.......@.....
 d030 f8ae00af 08af10af 48af88af b8afe0af  ........H.......
 d040 00b00000 74000000 10a040a0 70a0c0a0  ....t.....@.p...
 d050 00a160a1 88a1a0a1 10a240a2 70a2a0a2  ..`.......@.p...
 d060 d0a200a3 28a370a3 b0a3f8a3 50a4a0a4  ....(.p.....P...
 d070 b0a4c8a4 28a578a5 c0a510a6 80a6d0a6  ....(.x.........
 d080 20a778a7 c8a7e0a7 48a898a8 e8a838a9   .x.....H.....8.
 d090 c8a918aa 68aab8aa 08ab58ab a8abd8ab  ....h.....X.....
 d0a0 08ac40ac d0ac20ad 70adc0ad 18ae68ae  ..@... .p.....h.
 d0b0 a8ae0000                             ....

 Disassembly blah:
