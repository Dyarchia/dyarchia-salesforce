# Voice Agents — Reference (Winter '27 / API v68.0)

How a voice agent speaks, listens and connects: the `modality voice` block, voice models and personas, voice-specific instruction rules, and SIP telephony.

Agentforce Voice replaces IVR menus with a service agent that talks. The agent itself is an ordinary
Agent Script agent (`references/agent-script.md`); voice adds one block, a channel, and stricter
rules on what a turn may contain. Telephony routing and handoff to human reps: `dya-sf-omni-channel`.

## 1. What voice changes

| Concern | Text agent | Voice agent |
|---|---|---|
| Output | Markdown, lists, links, cards | Plain spoken sentences; formatting is read aloud or dropped |
| Turn length | A paragraph is fine | One or two sentences, then a question |
| Silence | Invisible | Dead air after a few seconds reads as a dropped call |
| Entities | Read on screen | Numbers, emails, Ids and product names must be pronounceable |
| Locale | Can adapt per message | Fixed; adaptive language mode is ignored on voice |
| Escalation | Messaging transfer | Call transfer back to telephony, then to a rep |

## 2. The `modality voice` block

`modality voice:` is a top-level block, and `voice` is the only modality it accepts. It has two
optional directions:

- `outbound` — how the agent speaks: persona, text-to-speech model, model parameters.
- `inbound` — how the agent listens: filler-word handling and keyword boosting. The speech-to-text
  model itself is not configurable.

```agentscript
modality voice:
    outbound:
        persona_id: "a029af9d692c"            # April (en_US), a Flash v2 voice
        model:
            id: "eleven_flash_v2"
            parameters:
                speed: 0.95
                stability: 0.7
    inbound:
        filler_words_detection: True
        keywords:
            - "warranty"
            - "serial number"
```

| Property | Meaning | Default |
|---|---|---|
| `outbound.persona_id` | The voice, as the hash Id from that model's voice list | The locale's default voice |
| `outbound.model.id` | Text-to-speech model | The language's default model |
| `outbound.model.parameters` | Name-value pairs passed to the model unvalidated; unknown names are ignored | The persona's own tuned values |
| `inbound.filler_words_detection` | Ignore "um" and "uh" in the caller's speech | `False` |
| `inbound.keywords` | Terms boosted during recognition | — |

Omit everything you do not need to change; an agent with no `outbound` section speaks with the
language's default model and the locale's default voice.

## 3. Choose a model, then a persona

Select a model first; each persona belongs to one model, and the same voice has a **different hash
Id under each model**. Use the Id from the list of the model you selected.

| Model | `model.id` | Choose it for | Parameters honoured |
|---|---|---|---|
| ElevenLabs v3 Conversational | `eleven_v3_conversational` | The default for most languages; most natural speech; reads numbers, emails and Ids correctly | `stability` only, default 0.5 |
| ElevenLabs Flash v2 | `eleven_flash_v2` | English only; lowest latency English; best custom pronunciation; steadier UK and Australian accents than v3 | `speed`, `stability`, `similarity` |
| ElevenLabs Flash v2.5 | `eleven_flash_v2_5` | Non-English languages with lower latency; best adherence to regional accents (Argentine Spanish, Canadian French, European Portuguese) | `speed`, `stability`, `similarity`; no custom pronunciation |
| Kotoba | `kotoba` | Japanese (`ja`), where it is the default | None; omit `parameters` |

| Parameter | Range on the Flash models | Effect |
|---|---|---|
| `speed` | 0.7 – 1.2 | Speaking rate |
| `stability` | 0 – 1 | Low is expressive and variable, high is steady |
| `similarity` | 0 – 1 | How closely output keeps the source voice's character |

- **Keep the default model unless a requirement names a reason**: latency, an accent, a language, or
  custom pronunciation.
- **Select non-default models in Agent Script only.** Agentforce Builder's canvas has no model
  selector, shows no catalogue for non-default models, and does not filter its voice picker by a
  script override.
- **Do not round-trip a voice change through the canvas.** Canvas and script store voice differently;
  editing the voice in one and returning to the other can leave the configuration inconsistent.
- **Judge a voice in a live preview conversation**, never from a static sample.
- **Set parameters only to override the persona.** Each persona ships tuned defaults; a value right
  for one persona is wrong for another.

### Per-language voice

For a non-default model on one language, nest the outbound settings under `language_settings`:

```agentscript
modality voice:
    language:
        default_locale: "ja"
    language_settings:
        ja:
            outbound:
                persona_id: "e5d63b40f254"    # Azawa (ja), the Kotoba default
                model:
                    id: "kotoba"
```

### Voice catalogue

The catalogue is a per-release snapshot; read the current list before choosing. Locales covered:

| Model | Locales |
|---|---|
| v3 Conversational | 32 locales: Arabic (EG, SA, AE), Chinese (simplified, traditional), Croatian, Czech, Danish, Dutch, English (AU, GB, US), Filipino, Finnish, French (CA, FR), German, Greek, Hindi, Indonesian, Italian, Korean, Malay, Norwegian Bokmål, Polish, Portuguese (BR, PT), Romanian, Spanish (Latin America `es_MX`, Spain `es`), Swedish, Turkish |
| Flash v2 | English: `en_AU`, `en_GB`, `en_US` |
| Flash v2.5 | 19 non-English locales, from Arabic to Turkish |
| Kotoba | `ja` |

Defaults when `persona_id` is omitted under Flash: `en_US` Mark (`f64af13e6fb0`), `en_GB` Noah
(`16c896e36f6b`), `en_AU` Jack (`1ef01b886887`) on Flash v2; `es` Raquel (`3b7b09534aa5`), `es_MX`
José (`1c69047a1dac`), `fr` Louis (`4f708167ff27`), `de` Anton (`83707dbabdbd`), `it` Giulia
(`04c0407e1ee3`), `pt_BR` Thiago (`783560f2adaf`) on Flash v2.5.

## 4. Legacy flat format

Older scripts set voice keys directly under `modality voice`, without `outbound` / `model` nesting.
The flat format still runs but **cannot select a model**, and **the two formats cannot be mixed** in
one script; converting means rewriting the whole block by hand.

```agentscript
modality voice:
    voice_id: "<voice identifier>"
    outbound_speed: 1.0
    inbound_filler_words_detection: True
    inbound_keywords:
        keywords:
            - "warranty"
    pronunciation_dict:
        - grapheme: "Acmezyme"
          phoneme: "ˈækmiˌzaɪm"
          type: "IPA"
    outbound_filler_sentences:
        - waiting: ["One moment while I check.", "Still looking, thanks for waiting."]
    additional_configs:
        speak_up_config:
            speak_up_first_wait_time_ms: 15000
            speak_up_follow_up_wait_time_ms: 20000
            speak_up_message: "Are you still on the line?"
        endpointing_config:
            max_wait_time_ms: 1200
        beepboop_config:
            max_wait_time_ms: 2000
```

| Key | Range | Effect |
|---|---|---|
| `voice_id` | — | Outbound voice; required for a live voice channel in this format |
| `outbound_speed` | 0.5 – 2.0 | Speaking rate, 1.0 normal |
| `outbound_style_exaggeration` | 0.0 – 1.0 | Expressiveness of the voice's style |
| `pronunciation_dict` | — | Entries of `grapheme`, `phoneme`, and `type` `"IPA"` or `"CMU"` |
| `outbound_filler_sentences` | — | `waiting` phrases spoken while an action runs |
| `speak_up_first_wait_time_ms` / `speak_up_follow_up_wait_time_ms` | 10000 – 300000 | Silence before the agent speaks up, first and repeated |
| `speak_up_message` | — | What it says when it speaks up |
| `endpointing_config.max_wait_time_ms` | 500 – 60000 | How long to wait for the caller to continue before closing their turn |
| `beepboop_config.max_wait_time_ms` | 500 – 60000 | How long to analyse an automated tone (fax, answering machine) |

The published reference documents `pronunciation_dict`, `outbound_filler_sentences` and
`additional_configs` only in this flat format, and model selection only in the nested format.
Choose the format by the feature you need, validate, and never combine keys from both.

## 5. Instruction rules for voice

Branch on the channel instead of writing a voice-only agent: `@system_variables.current_modality`
is `"voice"` on telephony connections, `"text"` on messaging and Enhanced Chat v2, and `None` on
anything else.

```agentscript
subagent claim_status:
    description: "Tell a caller or chatter the status of their warranty claim"
    reasoning:
        instructions: ->
            run @actions.get_claim_status
                with claim_id = @variables.claim_id
                set @variables.claim_status = @outputs.status
            if @system_variables.current_modality == "voice":
                | Say the status in one short sentence: {!@variables.claim_status}.
                  Then ask whether the caller needs anything else.
                  No lists, no links, no symbols.                         # ✅ speakable
            else:
                | Show the status {!@variables.claim_status} with the next steps as a short list.
```

- **One idea per turn.** Answer, then ask one question; long turns invite barge-in and lose the
  caller.
- **No visual formatting.** No bullets, tables, links, emoji or markdown in spoken output.
- **Spell out what must be heard exactly.** Ask the model to read codes and Ids in short groups and
  to confirm them back; v3 Conversational handles entities best, Flash v2 accepts custom
  pronunciation, Flash v2.5 does not.
- **Teach the vocabulary twice.** Boost domain terms in `inbound.keywords` so they are recognised,
  and give brand or drug names a pronunciation entry so they are spoken right.
- **Confirm before acting.** Restate what will happen and wait for a yes before any consequential
  action; mishearing is the voice channel's normal failure (`references/agent-design.md`).
- **Cover slow actions.** Keep `include_in_progress_indicator: True` on slow actions and provide
  filler sentences so the caller does not hear silence.
- **Keep the response path short.** Fewer tools per subagent, outputs reduced to what the turn
  speaks, and lookups run once and cached in variables. Every tool enlarges every request, and a
  slow model call is heard as silence.
- **Weigh the post-processing.** `config.runtime.citation` and `groundedness` add latency; keep
  groundedness on for knowledge answers, and turn citation off on voice, which cannot render it.
- **Leave `config.runtime.streaming` on** for voice so speech starts before the turn completes.
- **Fix the locale.** Set `language.default_locale`; adaptive mode is ignored on voice and only
  raises a warning.
- **Keep the call Id.** A linked variable with `source: @VoiceCall.Id` carries the call into actions
  and handoffs.

## 6. SIP telephony

Customers reach a voice agent over PSTN, SIP, or Dynamic Voice Routing. SIP needs a **verified
Agentforce Voice with SIP partner**: the contact-centre platform (CCaaS) does the onboarding with
Salesforce; the customer then follows the Help pages *Create a Voice-Enabled Service Agent* and
*Connect a Service Agent to Partner Telephony*.

### Connection requirements

| Item | Requirement |
|---|---|
| Signalling | SIP over TLS, TCP/TLS port 5061; mutual TLS is not supported |
| Media | SRTP, mandatory |
| Addresses | Static signalling and media IPv4 ranges, allow-listed per region |
| Codecs | G.711 PCMU and PCMA |
| Call context | UUI header, hex-encoded; or custom SIP X-headers when enabled |
| Disconnect handling | SIP REFER, when the customer needs it |
| Certificates | Partner CA certificate installed on Salesforce's edge |

The UUI header (or the X-header alternative) carries the parameters Salesforce routes on; custom
headers also carry intent, language preference, or authentication context into the agent.

### Partner onboarding sequence

1. Assess: TLS, SRTP, static IPs, codecs, hex-encoded UUI, regional IP ranges, data-centre location.
2. Complete the SIP Signalling Configuration Form (trunk regions, signalling subnet and ports, media
   subnet and ports when they differ, certificate details) and send it through the Salesforce team.
3. After Salesforce confirms the integration, run a connectivity test per region: a call carrying the
   hex-encoded UUI `{"orgId":"echo-test-org","scrt2Domain":"afv-wss-echo:7442"}` must return an echo;
   compare SIP traces on both ends.
4. Run end to end: inbound call to the partner, transfer over SIP to the agent, escalation back to
   partner telephony, routing to a rep in Salesforce Voice, with the Agentforce Voice call record
   linked to the rep's Voice Call.
5. Review the setup with Salesforce; publish supported regions once endorsed.

### Regions

Connect each country to its recommended region; the SBC FQDN is shared by every partner in a region.

| Agentforce Voice region | Countries | SBC FQDN |
|---|---|---|
| US-WEST | USA West | `gateway.afvsip.thb01.uengage1.sfdc-lywfpd.salesforce-ccaas.com` |
| US-EAST (N. Virginia) | USA East | `gateway.afvsip.thb01.uengage1.sfdc-yfeipo.salesforce-ccaas.com` |
| CANADA | Canada | `gateway.afvsip.thb01.uengage1.sfdc-58ktaz.salesforce-ccaas.com` |
| SÃO PAULO | Brazil | `gateway.afvsip.thb01.uengage1.sfdc-xwy4ub.salesforce-ccaas.com` |
| LONDON | UK, Ireland (some partners) | `gateway.afvsip.thb01.uengage1.sfdc-5pakla.salesforce-ccaas.com` |
| FRANKFURT | Continental Europe and Turkey, Ireland (some partners) | `gateway.afvsip.thb01.uengage1.sfdc-yzvdd4.salesforce-ccaas.com` |
| MUMBAI | India | `gateway.afvsip.thb01.uengage1.sfdc-y37hzm.salesforce-ccaas.com` |
| SINGAPORE | Singapore | `gateway.afvsip.thb01.uengage1.sfdc-hvhps.salesforce-ccaas.com` |
| TOKYO | Japan | `gateway.afvsip.thb01.uengage1.sfdc-mchho0.salesforce-ccaas.com` |
| SYDNEY | Australia, New Zealand | `gateway.afvsip.thb01.uengage1.sfdc-vwfla6.salesforce-ccaas.com` |

Verified partners, per the published chart: Genesys (all ten regions), AMC Technology (all except
Canada and São Paulo), Vonage (US-West, US-East, Singapore, London, Sydney, Frankfurt), Five9
(US-West and US-East). Check the chart before promising a region; it changes monthly.

### TLS certificate rotation

- **Coordinate every partner certificate change with Salesforce Voice Operations**
  (`thb-voiceops@salesforce.com`); an unannounced rotation breaks calls immediately.
- **Give at least 14 days' notice** for a scheduled rotation; Salesforce tests before accepting it.
- **Emergency rotation** (compromise, expiry) needs a written justification and is not guaranteed
  within hours. Track certificate expiry so it never becomes an emergency.
- Each notice states the partner name, standard or emergency, the target date, and a technical
  contact for the window.

## 7. Mobile SDK entry points

Pointers only; the SDK guide holds the setup.

| Platform | Entry point |
|---|---|
| iOS | `enableVoice: true` in the SDK feature flags; `AgentforceVoiceView`, a SwiftUI view for the voice session |
| Android | `enableVoice: true` in the SDK feature flags |
| React Native | `@salesforce/react-native-agentforce` bridge, voice enabled through a JavaScript feature flag; employee and service agents |

| Connection path | Setup | Human escalation | Transcript | Routing |
|---|---|---|---|---|
| Agent API (telephony) | A Telephony connection in Agentforce Studio | Not supported | Not available | Direct to the agent |
| Enhanced Chat v2 | Embedded Service deployment with an ECv2 channel | Supported | Through Service Cloud | Omni-Channel with queue fallback |

Voice settings live on the agent and apply to every connection, so the mobile app inherits the
`modality voice` block.

## 8. Testing a voice agent

- Preview converses in text and does not support escalation; it proves routing and wording, not
  speech.
- Test the voice itself, pronunciation, silence handling and transfer on a real telephony
  connection after publish and activation.
- Write test utterances the way callers speak: fillers, corrections, spelled-out numbers, partial
  sentences (`references/testing-and-evaluation.md`).

## 9. Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Changing the model "for quality" without a reason | Keep the language default; switch for latency, accent, language or pronunciation |
| A `persona_id` copied from another model's list | The hash Id from the selected model's list |
| `speed` or `similarity` on v3 Conversational | Only `stability` applies there; use a Flash model for fine control |
| Editing voice in the canvas after setting it in script | Keep voice configuration in one place, the script |
| Mixing flat and nested voice keys | One format per block |
| Adaptive language on a voice agent | A fixed `default_locale` |
| Lists, links and markdown in spoken turns | Branch on `current_modality` and speak plain sentences |
| Reading a long Id in one breath | Short groups, confirmed back |
| Silent slow actions | Progress indicator plus filler sentences, and leaner actions |
| Rotating the SIP certificate unannounced | 14 days' notice to Voice Operations |
| Promising a SIP region from memory | Check the partner chart |
| Testing voice only in preview | Test speech and transfer on the live telephony channel |
