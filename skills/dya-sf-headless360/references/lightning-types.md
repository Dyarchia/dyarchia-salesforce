# Lightning Types — Reference (Winter '27 / API v68.0)

Load from `dya-sf-headless360` when building the structured interactions the Experience Layer renders.

## What they are

A Lightning type describes the shape of what an agent or app returns and carries the UI for editing
and rendering it.

**Standard types**, each with a default editor and renderer:

```text
lightning__booleanType     lightning__numberType
lightning__dateType        lightning__objectType
lightning__dateTimeType    lightning__richTextType
lightning__dateTimeStringType
lightning__textType
lightning__integerType     lightning__timeType
lightning__multilineTextType
lightning__urlType
```

Each has type-specific keywords, much like JSON Schema. **Support varies by application** — check
before assuming a type renders everywhere.

**Custom types** (`LightningTypeBundle`, **API version 64.0**+) override the default interface for
complex interactions.

## Bundle structure

```text
+--myMetadataPackage
    +--lightningTypes
        +--TYPE_NAME
           +--schema.json
           +--CHANNEL_NAME
              +--editor.json  OR  +--renderer.json
```

- **`schema.json`** — the JSON schema driving validation. Required.
- **Channel folders are optional**, needed only to override the UI for a specific application:

| Channel folder | Renders in |
|---|---|
| `lightningDesktopGenAi` | Agentforce Employee agent in Lightning Experience |
| `enhancedWebChat` | Agentforce Service agent via Enhanced Chat v2 |
| `lightningMobileGenAi` | Employee agent on mobile, and Service agent via Enhanced Chat v2 on mobile |
| `experienceBuilder` | Experience Builder |

- **`editor.json`** carries the custom editing UI, **`renderer.json`** the custom display UI.
  **`renderer.json` is not supported in `experienceBuilder`.**

**HXL widgets (Beta) invert this.** When a custom type references a widget, put `renderer.json` at
the **root**, parallel to `schema.json`, with **no channel folder and no `editor.json`**. The
channel-folder pattern fails quietly there.

The Connect REST resource `/connect/lightning-types` lists the custom and standard types deployed
in an org.

## Apex-backed custom types

These exist because of namespaced orgs and managed packages; skipping them fails at invocation, not
at deploy.

- **Top-level classes only.** Every class in its own file; **no inner classes**.
- **`global` visibility on all of them.** `public` or `private` fails in namespaced orgs and managed
  packages.
- **`@AuraEnabled` on every field** required in the response, including fields inside objects used as
  an `@InvocableVariable`.
- **`@JsonAccess(serializable='always' deserializable='always')` on every class**, so the internal
  invocation layer can process the data.
- **Namespace prefix**: `c` for local org classes; the registered namespace for a managed package.

**Supported data types**: primitives (Integer, Double, Long, Date, Datetime, Time, String, ID,
Boolean), sObjects generic or specific, collections (lists or arrays of primitives, sObjects,
user-defined classes and collections; maps whose key is always a String), and user-defined Apex
classes.

> **If an agent action was created before the Apex met these requirements, delete and recreate the
> action after fixing the classes.** Updating the Apex alone does not re-register the change; the
> action keeps its old behaviour.

## When to use them

When the target is only Lightning Experience, a plain LWC is simpler and better supported; see
`dya-sf-lwc`.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Building a custom type for something a standard type covers | Standard types already ship with an editor and renderer |
| Assuming every standard type renders in every application | Support varies by application — verify for your channel |
| `renderer.json` inside a channel folder for an HXL widget | Root level, parallel to `schema.json`, no `editor.json` |
| `renderer.json` under `experienceBuilder` | Not supported there |
| Inner classes, or `public` visibility, in Apex-backed types | Top-level and `global`, or it fails in namespaced orgs |
| Omitting `@JsonAccess` | The invocation layer cannot process the data |
| Fixing the Apex and expecting the agent action to follow | Delete and recreate the action to re-register it |
| Lightning Types for a single-channel Lightning Experience UI | A plain LWC |
