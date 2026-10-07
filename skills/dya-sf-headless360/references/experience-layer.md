# Headless 360 Experience Layer & Lightning Types — Reference (Winter '27 / API v68.0)

Detail for SKILL.md §5. Load when an interaction must render across more than one channel, or when deciding between the Experience Layer and plain LWC/Aura.

## The Core Idea — Define Once, Render Everywhere

The **Headless Experience Layer (HXL)** — in its agent-facing form, the **Agentforce Experience Layer (AXL)** — is a runtime that **decouples what a capability does from how it appears**. Define a UI fragment / structured interaction once; the layer renders it natively per surface:

- Slack block / Slack thread component
- Microsoft Teams card
- Mobile card (native iOS/Android)
- Voice interaction
- A response inside ChatGPT, Claude, or Gemini
- Web

Business logic, data, and permissions stay **separate** from the rendering. Define **intent once**; each surface gets a native experience without per-channel rebuilding — e.g. an approval card, a decision tile, a flight-rebooking flow.

## Built on Lightning Types

The Experience Layer is built on **Lightning Types** (Custom Lightning Types, "CLT") — the metadata describing a rich, structured response and how it maps to a rendering. It evolves earlier Lightning Types work that already powered surfaces like Employee and Service agents.

- Define a **custom Lightning Type** to describe the shape of an interaction (fields, structure, the rendered component).
- The runtime maps that type to the right native rendering on each channel.
- Author Lightning Types in natural language via the **Lightning Types MCP tool** (`create_lightning_type`) in the Salesforce DX MCP Server (Developer Preview), through Agentforce Vibes.

## Native React

For full control of the visual layer, Headless 360 supports **native React**: custom interfaces in any design language/interaction model over the same headless capabilities. Use it when the Experience Layer's native renderings aren't enough and you need a bespoke front end — e.g. a custom web or Experience Cloud app consuming the same APIs/MCP tools.

## When to Use What

| Situation | Use |
|---|---|
| The same interaction must appear in Slack AND Teams AND voice AND a chat client | **Experience Layer + Lightning Types** (define once) |
| Agent output needs to render natively in a non-Salesforce surface (ChatGPT/Claude) | **AXL** |
| Rich, structured agent responses (approval cards, decision tiles) | **Lightning Types** |
| Full bespoke front end over headless capabilities | **Native React** |
| UI only ever shown in Lightning Experience | **LWC** (`dya-sf-lwc`), or Aura (`dya-sf-aura`) for the rare gap |
| Server-rendered PDF / Classic / email template | **Visualforce** (`dya-sf-visualforce`) |

The pivot: **how many surfaces?** One Lightning surface → plain LWC. Many/agent surfaces → Experience Layer + Lightning Types.

## Maturity Note

The **build-time** surface (authoring capabilities, MCP tooling, coding skills) is mature. The **runtime** Experience Layer handles straightforward cases well — e.g. a support agent returning a case summary inside a Slack thread — and the cross-surface vision (the same capability delivered across voice, partner mobile apps, and any MCP-compatible client) is expanding through the release. Build with the "define once" model now; the set of natively-rendered surfaces will keep growing.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Rebuilding the same UI for each channel | Define once via Lightning Types; HXL renders per surface |
| Using HXL for a single Lightning-only screen | Plain LWC |
| Hand-coding per-channel renderings | Let the Experience Layer map the Lightning Type |
| Native React when a standard rendering suffices | Use Lightning Types' native renderings; React for bespoke needs |
| Putting business logic in the rendering layer | Keep logic/data/permissions separate from the surface |
