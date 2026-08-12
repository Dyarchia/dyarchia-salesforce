# Headless 360 Experience Layer & Lightning Types — Reference (Summer '26)

Full detail referenced from SKILL.md §5. Load this when an interaction must render across more than one channel, or when deciding between the Experience Layer and plain LWC/Aura.

## The Core Idea — Define Once, Render Everywhere

The **Headless Experience Layer (HXL)** — in its agent-facing form, the **Agentforce Experience Layer (AXL)** — is a runtime that **decouples what a capability does from how it appears**. You define a UI fragment / structured interaction once; the layer renders it natively per surface:

- Slack block / Slack thread component
- Microsoft Teams card
- Mobile card (native iOS/Android)
- Voice interaction
- A response inside ChatGPT, Claude, or Gemini
- Web

Business logic, data, and permissions stay **separate** from the rendering. You define **intent once**; each surface gets a native experience without per-channel rebuilding. Concrete examples: an approval card, a decision tile, a flight-rebooking flow — authored once, surfaced everywhere.

## Built on Lightning Types

The Experience Layer is built on **Lightning Types** (Custom Lightning Types, "CLT") — the metadata that describes a rich, structured response and how it maps to a rendering. This is the evolution of earlier Lightning Types work that already powered surfaces like Employee and Service agents.

- Define a **custom Lightning Type** to describe the shape of an interaction (fields, structure, the rendered component).
- The runtime maps that type to the right native rendering on each channel.
- You can author Lightning Types with natural language via the **Lightning Types MCP tool** (`create_lightning_type`) in the Salesforce DX MCP Server (Developer Preview), through Agentforce Vibes.

## Native React

For teams that want full control of the visual layer, Headless 360 supports **native React**: build custom interfaces in any design language/interaction model over the same headless capabilities. Use this when the Experience Layer's native renderings aren't enough and you need a bespoke front end — for example a custom web or Experience Cloud app consuming the same APIs/MCP tools.

## When to Use What

| Situation | Use |
|---|---|
| The same interaction must appear in Slack AND Teams AND voice AND a chat client | **Experience Layer + Lightning Types** (define once) |
| Agent output needs to render natively in a non-Salesforce surface (ChatGPT/Claude) | **AXL** |
| Rich, structured agent responses (approval cards, decision tiles) | **Lightning Types** |
| Full bespoke front end over headless capabilities | **Native React** |
| UI only ever shown in Lightning Experience | **LWC** (`decimatio-lwc`), or Aura (`decimatio-aura`) for the rare gap |
| Server-rendered PDF / Classic / email template | **Visualforce** (`decimatio-visualforce`) |

The decision pivot: **how many surfaces?** One Lightning surface → plain LWC. Many/agent surfaces → Experience Layer + Lightning Types. Don't reach for HXL to build a single Lightning page; don't rebuild per-channel UIs when HXL would define it once.

## Maturity Note

As of Summer '26 the **build-time** surface (authoring capabilities, MCP tooling, coding skills) is mature. The **runtime** Experience Layer already handles straightforward cases well — e.g. a support agent returning a case summary inside a Slack thread — and the cross-surface vision (the same capability delivered across voice, partner mobile apps, and any MCP-compatible client) is expanding through the release. Build with the "define once" model now; expect the set of natively-rendered surfaces to keep growing.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Rebuilding the same UI for each channel | Define once via Lightning Types; HXL renders per surface |
| Using HXL for a single Lightning-only screen | Plain LWC |
| Hand-coding per-channel renderings | Let the Experience Layer map the Lightning Type |
| Native React when a standard rendering suffices | Use Lightning Types' native renderings; React for bespoke needs |
| Putting business logic in the rendering layer | Keep logic/data/permissions separate from the surface |
