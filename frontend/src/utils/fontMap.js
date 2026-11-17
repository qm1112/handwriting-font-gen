export const FONT_FAMILY_MAP = {
  ma_shan_zheng: '"Ma Shan Zheng", "Kaiti SC", "STKaiti", cursive, serif',
  noto_sans: '"Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif',
  noto_serif: '"Noto Serif SC", "Songti SC", "SimSun", serif',
  zcool_xiaowei: '"ZCOOL XiaoWei", "Songti SC", serif',
  long_cang: '"Long Cang", "Xingkai SC", cursive',
  kaiti: '"Kaiti SC", "STKaiti", "KaiTi", "楷体", serif',
}

export function getFontFamily(fontKey) {
  return FONT_FAMILY_MAP[fontKey] || FONT_FAMILY_MAP.ma_shan_zheng
}
