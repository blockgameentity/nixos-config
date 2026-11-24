# EQ for the Focal Bathys, which reach the desktop through the Avantree DG60P
# Bluetooth transmitter (a USB audio device; its USB descriptor calls it
# "Mpow HC5"). Two PipeWire filter-chain sinks:
#
#   everything ──────────────► "Headphones (Bathys EQ)" ─► DG60P
#   limusic ─► "Bathys music tilt" ─┘   (correction)
#              (V-shape)
#
#  1. "Headphones (Bathys EQ)": correction to the Harman over-ear target, from
#     oratory1990's measurement via AutoEq (results/oratory1990/over-ear/
#     Focal Bathys, all 10 filters, AutoEq's -4 dB preamp; largest boost
#     +3.8 dB). RTINGS' (B&K 5128) and Super Review's wireless measurements
#     agree on the main faults it fixes: a dip at ~800 Hz and recessed 2.2 and
#     4.2 kHz. This is the sink to pick in the volume popup.
#  2. "Bathys music tilt": a V-shape for limusic only, by request ("punchy"):
#     +4.5 dB low shelf at 150 Hz, +2.5 dB high shelf at 6 kHz, -0.5 dB
#     preamp. It plays into sink 1. Through both, the largest boost is
#     +4.1 dB against -4.5 dB of preamp, so nothing clips (filter-chain links
#     are float, so the boost between the two stages does not clip either).
#
# The WirePlumber hook below sends limusic to the tilt only while limusic
# would otherwise be linked to sink 1, so limusic still follows the default
# output to the speakers and elsewhere.
#
# Try changes live before writing them down, e.g.
#   pw-cli s <id of effect_input.bathys_music> Props '{ params = [ "bass:Gain" 6.0 ] }'
# (filter-chain runs these mono graphs once per channel and applies a control
# to both copies). Keep each path's preamp at least as low as its largest boost.
{ ... }: let
  dg60p = "alsa_output.usb-Qualcomm_Avantree_DG60P_A4DC15BF41D315C5E505-02.analog-stereo";

  bq = name: label: freq: q: gain: {
    type = "builtin";
    inherit name label;
    control = { Freq = freq; Q = q; Gain = gain; };
  };
  preamp = mult: {
    type = "builtin";
    name = "preamp";
    label = "linear";
    control = { Mult = mult; Add = 0.0; };
  };

  # A stereo sink running `nodes` in series and playing into `target`.
  sink = { id, description, nodes, target }: let
    names = map (n: n.name) nodes;
  in {
    name = "libpipewire-module-filter-chain";
    args = {
      "node.description" = description;
      "media.name" = description;
      "filter.graph" = {
        inherit nodes;
        links = builtins.genList (i: {
          output = "${builtins.elemAt names i}:Out";
          input = "${builtins.elemAt names (i + 1)}:In";
        }) (builtins.length names - 1);
      };
      "audio.channels" = 2;
      "audio.position" = [ "FL" "FR" ];
      "capture.props" = {
        "node.name" = "effect_input.${id}";
        "media.class" = "Audio/Sink";
      };
      "playback.props" = {
        "node.name" = "effect_output.${id}";
        "node.passive" = true;
        "target.object" = target;
        # With the target gone, stay silent rather than falling back to the
        # default sink (the speakers).
        "node.dont-fallback" = true;
        "stream.dont-remix" = true;
      };
    };
  };
in {
  services.pipewire.extraConfig.pipewire."60-bathys-eq" = {
    "context.modules" = [
      (sink {
        id = "bathys_eq";
        description = "Headphones (Bathys EQ)";
        target = dg60p;
        nodes = [
          (preamp 0.631) # -4.0 dB
          (bq "c1" "bq_lowshelf" 105.0 0.70 (-0.3))
          (bq "c2" "bq_peaking" 642.0 0.24 (-3.5))
          (bq "c3" "bq_peaking" 831.0 1.99 7.1)
          (bq "c4" "bq_peaking" 4157.0 1.67 3.6)
          (bq "c5" "bq_peaking" 2185.0 3.03 4.3)
          (bq "c6" "bq_highshelf" 10000.0 0.70 0.7)
          (bq "c7" "bq_peaking" 86.0 0.96 (-0.3))
          (bq "c8" "bq_peaking" 199.0 1.78 0.5)
          (bq "c9" "bq_peaking" 2995.0 4.09 (-0.6))
          (bq "c10" "bq_peaking" 381.0 2.53 (-0.4))
        ];
      })
      (sink {
        id = "bathys_music";
        description = "Bathys music tilt (limusic)";
        target = "effect_input.bathys_eq";
        nodes = [
          (preamp 0.944) # -0.5 dB
          (bq "bass" "bq_lowshelf" 150.0 0.70 4.5)
          (bq "treble" "bq_highshelf" 6000.0 0.70 2.5)
        ];
      })
    ];
  };

  # Runs in WirePlumber's select-target chain after its own target choice
  # (default, defined target, smart filters) and before the link is made. Also
  # runs on rescans, e.g. when the default output changes.
  services.pipewire.wireplumber.extraScripts."bathys-music.lua" = ''
    lutils = require ("linking-utils")
    log = Log.open_topic ("s-linking")

    local APP = "Limusic"
    local HEADPHONES = "effect_input.bathys_eq"
    local TILT = "effect_input.bathys_music"

    SimpleEventHook {
      name = "linking/bathys-music",
      after = "linking/get-filter-from-target",
      before = "linking/prepare-link",
      interests = {
        EventInterest {
          Constraint { "event.type", "=", "select-target" },
        },
      },
      execute = function (event)
        local source, om, si, si_props, si_flags, target =
            lutils:unwrap_select_target_event (event)
        if target == nil or target.properties ["node.name"] ~= HEADPHONES then
          return
        end
        local node = si:get_associated_proxy ("node")
        if node == nil or node.properties ["application.name"] ~= APP then
          return
        end
        local tilt = om:lookup {
          type = "SiLinkable",
          Constraint { "node.name", "=", TILT },
        }
        if tilt == nil then
          return
        end
        log:info (si, "... " .. APP .. " headed for the Bathys: via the music tilt")
        si_flags.can_passthrough = false
        event:set_data ("target", tilt)
      end
    }:register ()
  '';
  services.pipewire.wireplumber.extraConfig."60-bathys-music" = {
    "wireplumber.components" = [
      {
        name = "bathys-music.lua";
        type = "script/lua";
        provides = "custom.bathys-music";
      }
    ];
    "wireplumber.profiles".main."custom.bathys-music" = "required";
  };
}
