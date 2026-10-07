# Known issues — 1.0

This list distinguishes confirmed reports from fixes awaiting broader verification. Version 1.0 retains open reports; it is not a promise that every issue is solved.

| Issue | Evidence/status | Workaround / next step |
|---|---|---|
| Blue distant light/traffic glows | Live M5 pixel history shows two post-tonemap glow passes adding blue over a red signal. Version 1.0 corrects their packed COLOR0 view; Metal tests pass, the updated M5 frame shows red signal glow, and the user confirms lights seem fixed. Small blue/purple street-name signs are blue at source and also appear in original console references; no forced green recolor is applied. Other sign materials require separate validation. | Compare red signals and taillight glows in the 1.0 build. Broader effect coverage remains unverified. |
| Two missing shader programs | VS `D866F0D1394908B8`, PS `F1DAD9A46DA1A834` observed in the latest 60 FPS M5 run; 4 adapter rejected draws. Not among the 603 packaged programs. | Some geometry/effects may be absent when this pair is needed. Recovery/offline compilation pending. |
| Road texture flicker or shimmer | User-reported. Hidden material LOD sharpening was removed; full root-cause/regression verification outstanding. | Try the default scene resolution/filtering when reporting. Do not assume all flicker is a texture issue; depth/overlap must be checked. |
| Missing or wrong checkpoint smoke | Prior race reports on both devices; shader coverage and packed-color corrections added. Correct red/yellow start/checkpoint colors across all routes unconfirmed. | Include race/location and whether the smoke is absent or wrong-colored. |
| Look-behind/title fades remain confined to 16:9 | User-reported; full-screen rectangle classifier now automatic. Coverage of each actual fade shader/path still unverified. | Supply a clip showing the complete device screen and transition. |
| New-game rear tire in ground / incorrect ride height | Air report persisted after driving and affected handling. Existing hitch guard does not establish a root-cause fix. | Record car, start location, fresh/imported save, timing mode and repro steps. Preserve/export your save before destructive tests. |
| Refocus-like blur during rapid camera movement | On Oct 6 the user confirmed the effect persists with both blur switches enabled or disabled. Source audit confirms the DoF hook clears object+0xF0 before composite upload. Motion-blur hooks suppress two parameter lookups; uploads then return early for zero handles, rather than explicitly writing zero into the parameters. Shader defaults/stale inputs and other passes remain unverified possibilities. | Capture moving-camera composite inputs and intermediate targets with both bypasses active; do not treat the preferences alone as the explanation. |
| Experimental 60 FPS correctness and thermals | Real-delta and smoothing math/pacers tested. Long races, collisions, traffic, warm-device and long-session behavior not broadly validated. | Use standard 30 FPS for a conservative baseline. Higher scene resolution and heat can prevent sustained 60 FPS. |
| Intro/cinematic timing | Upstream documents accelerated intro movies with real-delta unlocking. Exact iOS regression coverage is incomplete. | Skip intros where the game allows; report audio/video drift and selected timing mode. |
| Dithered foliage/shadow edges | Upstream reports this; different output scales can expose alpha-pattern artifacts. Exact iOS scope unverified. | Report scene resolution, output aspect and a still image. |
| Device/signing compatibility | Gameplay testing limited to Air and M5 iPad Pro. iOS 18 deployment target does not imply every iOS 18 device can run it well. Public re-signing routes not tested across every tool/version. | Include exact device/OS/signing tool and error. No promise of older-device support. |
| Source rebuild preparation | Public sources exclude original game data, generated AOT and local capture/compiler caches. Current tools require staged user-owned inputs. | Follow DEVELOPMENT.md; source ZIP alone is not a turnkey playable build. |

The standard app does not implement MetalFX frame generation, online multiplayer acceptance, or every feature in desktop LARecomp's settings. A desktop feature existing upstream is not proof it is active on iOS.

## HUD border and pavement follow-ups

The remaining lower-left map ring was traced to a padded quad outside the fill classifier. Version 1.0 applies the exact same map transform to that quad. The Oct 6 follow-up also recognizes its larger rotating footprint and orbiting GPS decorations, and inspects mixed triangle/quad batches up to 4,096 vertices. All 360-heading regressions pass and the follow-up was installed on Air/M5. Live fast-camera alignment and broader HUD/menu/fade coverage remain open.

Sun-reflection math and road specular inputs are present. Missing gold pavement shine has not been established from a night-versus-sunset comparison. Matching original-game time, weather and view angle is needed before changing reflection strength.


### Intro skip / title logo — October 6 follow-up

The user confirmed the MCLA logo remained absent with Skip Intro Videos selected.
The early Apple jump bypassed the legals/SWF constructor and context push. The
new Apple hook preserves both, skips the startup video play call at 0x822C2F48,
and sets the initialized SWF object's existing skip-request byte. Its timer,
context and natural completion/render-state fields are retained. Uninitialized
objects fall back to normal startup. Both configuration manifests carry the
hook; generated source wiring and the initialized-object helper pass checks.
The signed build is installed on Air and M5. Visual title-logo acceptance remains
pending; this is not yet documented as a confirmed graphics fix. Missing shader
coverage and the reported black patches remain separate open findings.
