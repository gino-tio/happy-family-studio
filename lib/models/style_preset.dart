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
    // From @paragonrhythms "City Pop" step-sequencer reel: Am7 → Dm9 over
    // a syncopated bass with a chromatic A–D♭–D walk-up, guitar stabs on
    // the off-beats and horn stabs on top.
    StylePreset(
      'City Pop',
      '80s Japanese / Hong Kong city pop, 105 BPM, light swing, F major. '
          'Chords Am7 to Dm9, one bar each, looping. Warm Rhodes electric '
          'piano holding the chords, syncopated finger bass walking up '
          'chromatically A, D-flat, D into the Dm9, clean funky guitar '
          'chord stabs on the off-beats, bright brass section stabs on top. '
          'Tight kick, snare on 2 and 4, busy 16th-note hi-hats. '
          'Smooth Cantopop vocal.',
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
