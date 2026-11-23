# Builds the two test bills for New Record › Choose Bill PDF (test/system/bill_pdf_test.rb):
# cht_bill.pdf, a 中華電信 繳費通知 laid out like the real one (its name and numbers are made up), and
# cht_bill_locked.pdf, the same bill locked with the password "A123456789" (RC4 40-bit, as old e-bills are).
# The Chinese font isn't embedded (Adobe-CNS1, MSung-Light), so each file is a few KB; pdf.js reads its
# text through the cmaps in public/vendor. Run: ruby test/fixtures/files/cht_bill/generate.rb
require "digest"

ROWS = [ # [text, left, top, size] in pt from the top left of an A4 page
  [ "中華電信股份有限公司", 210, 12, 18 ], [ "桃園營運處 115 年 10 月繳費通知", 200, 34, 11 ],
  [ "帳單查詢免付費客服專線：0800080123", 404, 34, 8.5 ], [ "營利事業統一編號： 19683736", 404, 54, 8.5 ],
  [ "王小明", 88, 72, 11 ],
  [ "應繳總金額(元)", 100, 139, 10 ], [ "繳費期限", 248, 139, 10 ], [ "繳費方式", 326, 139, 10 ],
  [ "營運處代號", 406, 139, 10 ], [ "用戶號碼", 492, 139, 10 ],
  [ "（點選金額可立即線上繳費）", 89, 151, 7 ],
  [ "$1,299", 121, 160, 11 ], [ "115/11/10", 243, 159, 11 ], [ "定 期 付 款", 317, 159, 10 ], [ "3", 430, 159, 11 ], [ "Y123456", 493, 159, 11 ],
  [ "用戶帳號：B10000000000001", 199, 205, 9 ], [ "計費週期：第 4 週期", 342, 205, 9 ],
  [ "通知單流水號：1200000000001", 56, 216, 9 ], [ "計費期間：115/09/16至115/10/15", 342, 216, 9 ],
  [ "電路統包專案月費", 69, 264, 9.5 ], [ "1299", 265, 264, 9.5 ],
  [ "3.當期應繳金額若有變動，以銷帳後之金額開立發票。", 69, 535, 8 ]
].freeze

PAD = [ 0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
        0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A ].pack("C*").b
FILE_ID = Digest::MD5.digest("cht_bill").b

def rc4(key, data)
  s = (0..255).to_a
  j = 0
  256.times { |i| j = (j + s[i] + key.getbyte(i % key.bytesize)) % 256; s[i], s[j] = s[j], s[i] }
  i = j = 0
  data.bytes.map { |byte| i = (i + 1) % 256; j = (j + s[i]) % 256; s[i], s[j] = s[j], s[i]; byte ^ s[(s[i] + s[j]) % 256] }.pack("C*")
end

def padded(password) = (password.b + PAD)[0, 32]

def content
  ROWS.map do |text, left, top, size|
    hex = text.encode("UTF-16BE").unpack1("H*").upcase
    format("BT /F1 %<size>s Tf %<x>s %<y>s Td <%<hex>s> Tj ET", size:, x: left, y: (842 - top - size).round(1), hex:)
  end.join("\n")
end

def build(path, password: nil)
  objects = {
    1 => "<< /Type /Catalog /Pages 2 0 R >>",
    2 => "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    3 => "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
    5 => "<< /Type /Font /Subtype /Type0 /BaseFont /MSung-Light /Encoding /UniCNS-UCS2-H /DescendantFonts [6 0 R] >>",
    6 => ->(seal) { "<< /Type /Font /Subtype /CIDFontType0 /BaseFont /MSung-Light /CIDSystemInfo << /Registry #{seal.call(6, 'Adobe')} /Ordering #{seal.call(6, 'CNS1')} /Supplement 4 >> /FontDescriptor 7 0 R /DW 1000 >>" },
    7 => "<< /Type /FontDescriptor /FontName /MSung-Light /Flags 6 /FontBBox [-160 -249 1015 888] /ItalicAngle 0 /Ascent 880 /Descent -120 /CapHeight 880 /StemV 93 >>"
  }
  stream = content.b
  encrypt = nil
  seal = ->(_n, text) { "(#{text})" } # a string; in a locked file every string is encrypted with its object's key
  if password
    p_value = -44 # print and copy allowed
    owner = rc4(Digest::MD5.digest(padded("owner"))[0, 5], padded(password))
    key = Digest::MD5.digest(padded(password) + owner + [ p_value ].pack("l<") + FILE_ID)[0, 5]
    user = rc4(key, PAD)
    object_key = ->(n) { Digest::MD5.digest(key + [ n ].pack("V")[0, 3] + "\x00\x00".b)[0, 10] }
    stream = rc4(object_key.call(4), stream)
    seal = ->(n, text) { "<#{rc4(object_key.call(n), text.b).unpack1('H*')}>" }
    objects[8] = "<< /Filter /Standard /V 1 /R 2 /O <#{owner.unpack1('H*')}> /U <#{user.unpack1('H*')}> /P #{p_value} >>"
    encrypt = "/Encrypt 8 0 R "
  end
  objects[6] = objects[6].call(seal)
  objects[4] = "<< /Length #{stream.bytesize} >>\nstream\n".b + stream + "\nendstream".b

  out = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
  offsets = {}
  objects.keys.sort.each do |n|
    offsets[n] = out.bytesize
    out << "#{n} 0 obj\n".b << objects[n].b << "\nendobj\n".b
  end
  xref = out.bytesize
  size = objects.keys.max + 1
  out << "xref\n0 #{size}\n0000000000 65535 f \n".b
  (1...size).each { |n| out << format("%010d 00000 n \n", offsets.fetch(n)).b }
  id = FILE_ID.unpack1("H*")
  out << "trailer\n<< /Size #{size} /Root 1 0 R #{encrypt}/ID [<#{id}> <#{id}>] >>\nstartxref\n#{xref}\n%%EOF\n".b
  File.binwrite(path, out)
end

dir = __dir__
build(File.join(dir, "cht_bill.pdf"))
build(File.join(dir, "cht_bill_locked.pdf"), password: "A123456789")
