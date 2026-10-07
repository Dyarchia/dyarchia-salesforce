# Headless 360 Experience Layer & Lightning Types — Reference (Winter '27 / API v68.0)

Detail for SKILL.md §5. Load when an interaction must render across more than one channel, or when deciding between the Experience Layer and plain LWC/Aura.

## Define Once, Render Everywhere

The **Headless Experience Layer (HXL)** — agent-facing form: the **Agentforce Experience Layer (AXL)** — is a runtime. A UI fragment or structured interaction defined once renders natively as:

- Slack block / Slack thread component
- Microsoft Teams card
- Mobile card (native iOS/Android)
- Voice interaction
- A response inside ChatGPT, Claude, or Gemini
- Web

Examples: an approval card, a decision tile, a flight-rebooking flow.

## Built on Lightning Types

**Lightning Types** (Custom Lightning Types, "CLT") are the metadata describing a rich, structured response and how it maps to a rendering. They evolve earlier Lightning Types work that already powered Employee and Service agents.

- Define a **custom Lightning Type** to describe the shape of an interaction (fields, structure, the rendered component).
- The runtime maps that type to the native rendering on each channel.
- Author Lightning Types in natural language via the **Lightning Types MCP tool** (`create_lightning_type`, in the `lwc-experts` toolset of the Beta Salesforce DX MCP Server; the tool itself is Developer Preview), through Agentforce Vibes.

## Native React

Use **native React** when the Experience Layer's native renderings are not enough and you need a bespoke front end — e.g. a custom web or Experience Cloud app consuming the same APIs/MCP tools.

## When to Use What

| Situation | Use |
|---|---|
| The same interaction must appear in Slack AND Teams AND voice AND a chat client | **Experience Layer + Lightning Types** (define once) |
| Agent output needs to render natively in a non-Salesforce surface (ChatGPT/Claude) | **AXL** |
| Rich, structured agent responses (approval cards, decision tiles) | **Lightning Types** |
| Full bespoke front end over headless capabilities | **Native React** |
| UI only ever shown in Lightning Experience | **LWC** (`dya-sf-lwc`), or Aura (`dya-sf-aura`) for the rare gap |
| Server-rendered PDF / Classic / email template | **Visualforce** (`dya-sf-visualforce`) |

Decide by **how many surfaces**: one Lightning surface → plain LWC; many or agent surfaces → Experience Layer + Lightning Types.

## Maturity

Build with the "define once" model now; the set of natively-rendered surfaces will grow. The **build-time** surface — authoring capabilities, MCP tooling and coding skills — is mature. The cross-surface **runtime** vision — the same capability delivered across voice, partner mobile apps and any MCP-compatible client — is expanding through the release.

## Anti-Patterns

| Anti-Pattern | Correct Approach |
|---|---|
| Hand-coding per-channel renderings | Let the Experience Layer map the Lightning Type |
| Native React when a standard rendering suffices | Use Lightning Types' native renderings; React for bespoke needs |
| Putting business logic in the rendering layer | Keep logic/data/permissions separate from the surface |
