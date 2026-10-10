/// Starting points for the style box. The first one is the prompt that
/// produced 星期六返嚟 (see happy-family-big-band/README.md).
class StylePreset {
  const StylePreset(this.label, this.style);
  final String label;
  final String style;

  static const all = <StylePreset>[
    StylePreset(
      '星期六返嚟',
      '一首關於星期六芬達結他搖滾香港歌手嘅歌曲富有90年代結他感覺。'
          '90s Hong Kong Cantopop guitar rock, jangly Fender clean tones, '
          'male vocal, 120 BPM, G major.',
    ),
    StylePreset(
      '90s 廣東情歌',
      '90s Cantopop ballad, piano and strings, warm female vocal, '
          'slow 70 BPM, emotional chorus.',
    ),
    StylePreset(
      '城市夜 Lo-fi',
      'Lo-fi city pop, Hong Kong night, soft Rhodes, tape hiss, '
          'relaxed groove, 85 BPM.',
    ),
    StylePreset(
      '家庭派對',
      'Upbeat family party pop, handclaps, brass stabs, '
          'sing-along chorus, 128 BPM.',
    ),
  ];
}
