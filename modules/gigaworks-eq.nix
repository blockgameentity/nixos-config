# Sound processing for the Creative GigaWorks T20 Series II on the desktop's
# onboard ALC1220 rear line out (green jack, codec pin 0x1b). It is a PipeWire
# filter-chain sink, "Speakers (GigaWorks EQ)", in front of that one output, so
# headsets, the Scarlett and HDMI are untouched. Keep "Built-in Audio" at 100%,
# the T20's volume knob at max and its bass/treble knobs at flat (12 o'clock).
#
# What limits these speakers (listening tests with the user, 2026-11-24):
#  - The T20's input clips before its volume knob. Its peaks were clean at
#    -2.5 dBTP and clipped at -1 dBTP whatever the knob position, and the
#    codec's headphone amp (pin-ctl 0xc0, a hotter signal) distorted heavily.
#    So the limiter ceiling is -2.5 dBTP and loudness comes from the knob.
#  - Its amp then runs out of power on dense or bass-heavy material: driving
#    the limiter 3 dB harder at the same peaks clipped, and so did the T20's
#    own bass/treble knobs at 3/4 and EQ boosts at 75-85 Hz. So real bass below
#    90 Hz is cut and replaced by virtual bass, which needs far less power for
#    the same perceived bass.
#  - A resonance around 120-150 Hz rumbles.
#  - Windows plays music unprocessed: limusic's hot masters measured -6 to
#    -8 LUFS with true peaks up to +1.2 dBFS, i.e. hard-clipped in the DAC.
#    Why Windows still sounded louder is not known (the Windows-side settings were never checked).
#
# No published measurements exist for this speaker, so the tonal curve is by
# ear and by design, not a correction from a measured response. The dynamics
# were measured: the chain was run as a separate PipeWire client into a null
# sink, fed pink noise, tones and recorded music, and its output analysed.
# Results with these settings:
#  - True peaks on music stay at -2.5 dBTP (pink noise driven to +5 dBFS
#    slipped 0.4 dB past). swh's fast lookahead limiter, used first, limits
#    sample peaks only, and its true peaks overshot by ~2 dB.
#  - Hot masters come out 2.2 dB under the raw stream (the ceiling's cost);
#    mid-level music +3.5 dB, quiet music +4.2 dB, like Windows' "Loudness
#    Equalization".
#  - A 40 Hz tone comes out as its 80 Hz octave, 8 dB above what is left of
#    the fundamental (virtual bass).
#  - About 0.15 ms of DSP per 43 ms quantum.
#
# Chain, per channel unless noted:
#
#   in ─┬─ high-pass 55 Hz (24 dB/oct) ─ bass trim ─────────────┐
#       │                                                       mix ─ rumble cut ─ presence ─ crossover 160 Hz
#       └─ low-pass 100 Hz ─ |x| ─ high-pass 80 Hz ─ low-pass ──┘                              │          │
#          (virtual bass: rectifying the bass band makes its                         low band comp  high band comp
#           octave harmonics, which the ear hears as the bass                         (stereo SC4)   (stereo SC4)
#           itself; the woofer only has to play the harmonics)                                 └── sum ──┘
#                                                                                   true-peak limiter (stereo, LSP)
#
# Two compressor bands keep bass hits from pumping the vocals. Their low
# threshold plus makeup gain lifts quiet music and leaves loud music alone.
#
# Every number here can be tried live before it is written down, e.g.
#   pw-cli s <id of effect_input.gigaworks_eq> Props '{ params = [ "comphi:Makeup gain (dB)" 6.0 ] }'
# (per-channel nodes need both: "vmixL:Gain 2" and "vmixR:Gain 2"). LSP's gain
# controls are linear: "limiter:Input gain (G)" 1.413 is +3 dB.
{
  lib,
  pkgs,
  ...
}: let
  ladspaDir = "${pkgs.ladspaPlugins}/lib/ladspa";

  builtin = name: label: control: {
    type = "builtin";
    inherit name label control;
  };
  bw = name: label: freq: builtin name label { Freq = freq; Q = 0.707; };

  # Two cascaded Butterworth stages: a 4th-order Linkwitz-Riley filter. The LR4
  # low and high halves of the crossover sum back to a flat response.
  lr4 = prefix: label: freq: [ (bw "${prefix}1" label freq) (bw "${prefix}2" label freq) ];

  sc4 = name: c: {
    type = "ladspa";
    inherit name;
    plugin = "${ladspaDir}/sc4_1882.so";
    label = "sc4";
    control = {
      "RMS/peak" = 0.0; # RMS: reacts to loudness, not single transients
      "Knee radius (dB)" = 6.0;
      "Attack time (ms)" = c.attack;
      "Release time (ms)" = c.release;
      "Threshold level (dB)" = c.threshold;
      "Ratio (1:n)" = c.ratio;
      "Makeup gain (dB)" = c.makeup;
    };
  };

  # Serial links between nodes that use the builtin In/Out port names.
  chain = names:
    lib.zipListsWith (a: b: {
      output = "${a}:Out";
      input = "${b}:In";
    }) (lib.init names) (lib.tail names);

  channel = ch: {
    nodes =
      [ (builtin "in${ch}" "copy" { }) ]
      ++ lr4 "hp${ch}" "bq_highpass" 55.0
      # Real bass below the port, cut 5 dB: it is what runs the amp out of
      # power. The virtual bass makes up for it (the user preferred this to
      # -2 dB with less virtual bass).
      ++ [ (builtin "lows${ch}" "bq_lowshelf" { Freq = 90.0; Q = 0.707; Gain = -5.0; }) ]
      ++ lr4 "vlp${ch}" "bq_lowpass" 100.0
      ++ [ (builtin "vabs${ch}" "abs" { }) ]
      ++ lr4 "vhp${ch}" "bq_highpass" 80.0
      ++ [
        (bw "vtop${ch}" "bq_lowpass" 500.0)
        # Gain 2 is the amount of virtual bass: 1.2 was good, 1.7 better.
        # Too much sounds fuzzy.
        (builtin "vmix${ch}" "mixer" { "Gain 1" = 1.0; "Gain 2" = 1.7; })
        # Cabinet/desk resonance the user heard as rumble at 120-150 Hz.
        (builtin "rumble${ch}" "bq_peaking" { Freq = 135.0; Q = 2.0; Gain = -3.0; })
        # Flat: a -2 dB cut here sounded dull and made the user turn the
        # T20 treble knob up, which then distorted. Kept as a knob.
        (builtin "presence${ch}" "bq_peaking" { Freq = 2500.0; Q = 1.0; Gain = 0.0; })
      ]
      ++ lr4 "xlo${ch}" "bq_lowpass" 160.0
      ++ lr4 "xhi${ch}" "bq_highpass" 160.0
      ++ [ (builtin "sum${ch}" "mixer" { "Gain 1" = 1.0; "Gain 2" = 1.0; }) ];

    links =
      chain [ "in${ch}" "hp${ch}1" "hp${ch}2" "lows${ch}" ]
      ++ [ { output = "lows${ch}:Out"; input = "vmix${ch}:In 1"; } ]
      ++ chain [ "in${ch}" "vlp${ch}1" "vlp${ch}2" "vabs${ch}" "vhp${ch}1" "vhp${ch}2" "vtop${ch}" ]
      ++ [ { output = "vtop${ch}:Out"; input = "vmix${ch}:In 2"; } ]
      ++ [ { output = "vmix${ch}:Out"; input = "rumble${ch}:In"; } ]
      ++ chain [ "rumble${ch}" "presence${ch}" ]
      ++ chain [ "presence${ch}" "xlo${ch}1" "xlo${ch}2" ]
      ++ chain [ "presence${ch}" "xhi${ch}1" "xhi${ch}2" ];
  };

  side = { L = "Left"; R = "Right"; };
  bandLinks = band: ch: [
    { output = "x${band}${ch}2:Out"; input = "comp${band}:${side.${ch}} input"; }
    { output = "comp${band}:${side.${ch}} output"; input = "sum${ch}:In ${if band == "lo" then "1" else "2"}"; }
  ];

  l = channel "L";
  r = channel "R";
in {
  services.pipewire.extraConfig.pipewire."60-gigaworks-t20-eq" = {
    "context.modules" = [
      {
        name = "libpipewire-module-filter-chain";
        args = {
          "node.description" = "Speakers (GigaWorks EQ)";
          "media.name" = "Speakers (GigaWorks EQ)";
          "filter.graph" = {
            nodes =
              l.nodes
              ++ r.nodes
              ++ [
                # 2:1 with a 40 ms attack lets kick drums through; 2.5:1 at 25 ms sounded squashed.
                (sc4 "complo" { attack = 40.0; release = 250.0; threshold = -18.0; ratio = 2.0; makeup = 5.0; })
                (sc4 "comphi" { attack = 8.0; release = 150.0; threshold = -18.0; ratio = 2.0; makeup = 5.0; })
                {
                  type = "ladspa";
                  name = "limiter";
                  plugin = "${pkgs.lsp-plugins}/lib/ladspa/lsp-plugins-ladspa.so";
                  label = "http://lsp-plug.in/plugins/ladspa/limiter_stereo";
                  control = {
                    # Raising this is the "louder still" knob: +3 dB (1.413)
                    # measured +1 dB on hot masters but squashed them to a 5 dB
                    # crest factor, so it stays at unity.
                    "Input gain (G)" = 1.0;
                    "Threshold (G)" = 0.75; # -2.5 dBTP ceiling, the highest level the T20 input took cleanly
                    # Mode 1 with 10 ms lookahead/attack, for smoother gain changes
                    # than mode 0 (5 ms); meant to reduce limiter crunch on treble,
                    # not confirmed by ear. Still holds -2.5 dBTP on music.
                    "Operating mode" = 1;
                    "Gain boost" = 0.0; # output stays at the ceiling, no auto makeup
                    # Automatic level regulation is a slow gain rider on top of
                    # the limiter; left on, it held output 4-5 dB under the raw
                    # stream whatever the drive.
                    "Automatic level regulation" = 0.0;
                    "Lookahead (ms)" = 10.0;
                    "Attack time (ms)" = 10.0;
                    "Release time (ms)" = 20.0;
                    # LADSPA does not expose this enum's names. Measured with
                    # the limiter driven +3 dB: 0-2 let true peaks through,
                    # 4-10 and 22 held exactly -1.0 dBTP, 12-20 overshot.
                    "Oversampling" = 6;
                  };
                }
              ];
            links =
              l.links
              ++ r.links
              ++ lib.concatMap (band: bandLinks band "L" ++ bandLinks band "R") [ "lo" "hi" ]
              ++ [
                { output = "sumL:Out"; input = "limiter:Input L"; }
                { output = "sumR:Out"; input = "limiter:Input R"; }
              ];
            inputs = [ "inL:In" "inR:In" ];
            outputs = [ "limiter:Output L" "limiter:Output R" ];
          };
          "audio.channels" = 2;
          "audio.position" = [ "FL" "FR" ];
          "capture.props" = {
            "node.name" = "effect_input.gigaworks_eq";
            "media.class" = "Audio/Sink";
          };
          "playback.props" = {
            "node.name" = "effect_output.gigaworks_eq";
            "node.passive" = true;
            "target.object" = "alsa_output.pci-0000_00_1f.3.analog-stereo";
            "stream.dont-remix" = true;
          };
        };
      }
    ];
  };
}
