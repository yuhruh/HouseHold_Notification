# A 中華電信 繳費通知 (New Record › Choose Bill PDF) as pdf.js hands its text to the server: the pieces of
# the sample bill, placed as on the real page (its name and account numbers are made up). Used by the parser's tests and the bill_pdfs tests.
module BillPdfSample
  PX = 0.372 # the sample bill was drawn at 1600px across an A4 page (595pt)

  # A 中華電信 繳費通知 laid out as on the real bill: [text, x, y, w, h] in px of the 1600px picture
  CHT = [
    [ "中華電信股份有限公司", 560, 35, 450, 45 ],
    [ "桃園營運處 115 年 10 月繳費通知", 540, 92, 460, 30 ], [ "帳單查詢免付費客服專線：0800080123", 1085, 92, 410, 24 ],
    [ "電子信箱：billing_service@cht.com.tw", 1085, 120, 430, 24 ],
    [ "營利事業統一編號： 19683736", 1085, 145, 320, 24 ],
    [ "王小明", 236, 195, 100, 30 ],
    [ "應繳總金額(元)", 268, 375, 205, 28 ], [ "繳費期限", 667, 375, 115, 28 ], [ "繳費方式", 876, 375, 115, 28 ],
    [ "營運處代號", 1092, 375, 145, 28 ], [ "用戶號碼", 1322, 375, 115, 28 ],
    [ "（點選金額可立即線上繳費）", 240, 405, 260, 20 ],
    [ "$1, 299", 325, 430, 90, 30 ], [ "115/11/10", 652, 428, 130, 30 ], [ "定 期 付 款", 852, 428, 160, 30 ],
    [ "3", 1155, 428, 15, 30 ], [ "Y123456", 1325, 428, 105, 30 ],
    [ "用戶統一編號：", 150, 550, 180, 24 ], [ "用戶帳號：B10000000000001", 535, 550, 330, 24 ],
    [ "計費週期：第 4 週期", 920, 550, 200, 24 ], [ "帳單別：", 1335, 550, 90, 24 ],
    [ "通知單流水號：1200000000001", 150, 580, 360, 24 ], [ "彙寄編號：", 535, 580, 120, 24 ],
    [ "計費期間：115/09/16至115/10/15", 920, 580, 400, 24 ], [ "校對碼：5A", 1335, 580, 130, 24 ],
    [ "費 用 項 目", 185, 632, 200, 26 ], [ "金 額", 675, 632, 80, 26 ],
    [ "〔專案總額〕", 185, 678, 150, 26 ], [ "小計 1299", 505, 678, 120, 26 ],
    [ "電路統包專案月費", 185, 710, 210, 26 ], [ "1299", 712, 710, 55, 26 ],
    [ "說明：1.營業稅已併入各項應稅費用內。", 115, 1378, 1200, 22 ],
    [ "3.當期應繳金額若有變動，以銷帳後之金額開立發票。若有溢繳、重繳或短繳之費用，本公司將於繳費後次月扣抵(或可臨櫃", 185, 1437, 1320, 22 ],
    [ "辦理退費)或補繳方式辦理。", 210, 1466, 300, 22 ]
  ].freeze

  def words(rows) = rows.map { |s, x, y, w, h| { "s" => s, "x" => x * PX, "y" => y * PX, "w" => w * PX, "h" => h * PX } }

  # The same page with every piece split into single characters, as some PDFs come out of pdf.js
  def letters(rows)
    rows.flat_map do |s, x, y, w, h|
      step = w.to_f / s.length
      s.chars.each_with_index.map { |c, i| [ c, x + i * step, y, step, h ] }
    end
  end

  def cht_words = words(CHT)
end
