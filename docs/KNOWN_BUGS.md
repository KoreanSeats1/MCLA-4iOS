# Known bugs — 0.1.0 initial beta

This list distinguishes confirmed reports from fixes awaiting broader verification. It is part of the initial release, not a list of promises that every issue is solved.

| Issue | Evidence/status | Workaround / next step |
|---|---|---|
| Blue distant light/traffic glows | User screenshot: nearby taillights red, distant glows blue. Root cause unresolved. Packed-color GPU tests passing does not validate the offending gameplay path. | Report a repeatable location/time; the build has a bounded color-source trace with Retail Mode off. No verified color workaround. |
| Two missing shader programs | VS `D866F0D1394908B8`, PS `F1DAD9A46DA1A834` observed in the latest 60 FPS M5 run; 4 adapter rejected draws. Not among the 603 packaged programs. | Some geometry/effects may be absent when this pair is needed. Recovery/offline compilation pending. |
| Road texture flicker or shimmer | User-reported. Hidden material LOD sharpening was removed; full root-cause/regression verification outstanding. | Try the default scene resolution/filtering when reporting. Do not assume all flicker is a texture issue; depth/overlap must be checked. |
| Missing or wrong checkpoint smoke | Prior race reports on both devices; shader coverage and packed-color corrections added. Correct red/yellow start/checkpoint colors across all routes unconfirmed. | Include race/location and whether the smoke is absent or wrong-colored. |
| Look-behind/title fades remain confined to 16:9 | User-reported; full-screen rectangle classifier now automatic. Coverage of each actual fade shader/path still unverified. | Supply a clip showing the complete device screen and transition. |
| New-game rear tire in ground / incorrect ride height | Air report persisted after driving and affected handling. Existing hitch guard does not establish a root-cause fix. | Record car, start location, fresh/imported save, timing mode and repro steps. Preserve/export your save before destructive tests. |
| Refocus-like blur during rapid camera movement | User reported near/distant blur distinct from motion blur. Motion blur and DoF controls exist; not all potential blur paths are proven identified. | Compare separately with Disable Motion Blur and Disable Depth of Field, and report both settings. |
| Experimental 60 FPS correctness and thermals | Real-delta and smoothing math/pacers tested. Long races, collisions, traffic, warm-device and long-session behavior not broadly validated. | Use standard 30 FPS for a conservative baseline. Higher scene resolution and heat can prevent sustained 60 FPS. |
| Intro/cinematic timing | Upstream documents accelerated intro movies with real-delta unlocking. Exact iOS regression coverage is incomplete. | Skip intros where the game allows; report audio/video drift and selected timing mode. |
| Dithered foliage/shadow edges | Upstream reports this; different output scales can expose alpha-pattern artifacts. Exact iOS scope unverified. | Report scene resolution, output aspect and a still image. |
| Device/signing compatibility | Gameplay testing limited to Air and M5 iPad Pro. iOS 18 deployment target does not imply every iOS 18 device can run it well. Public re-signing routes not tested across every tool/version. | Include exact device/OS/signing tool and error. No promise of older-device support. |
| Source rebuild preparation | Public sources exclude original game data, generated AOT and local capture/compiler caches. Current tools require staged user-owned inputs. | Follow DEVELOPMENT.md; source ZIP alone is not a turnkey playable build. |

The standard app does not implement MetalFX frame generation, online multiplayer acceptance, or every feature in desktop LARecomp's settings. A desktop feature existing upstream is not proof it is active on iOS.
