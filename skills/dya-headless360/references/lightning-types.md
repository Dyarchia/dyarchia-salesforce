# Lightning Types — Reference (Winter '27 / API v68.0)

Load from `dya-headless360` when building the structured interactions the Experience Layer renders.
Lightning Types are what "define once, render natively everywhere" is actually made of.

## What they are

**JSON-based data types that structure, validate and display data.** A Lightning type describes the
shape of something an agent or app returns, and carries the UI for editing and rendering it — so the
same definition can surface as a Slack block, a mobile card or an in-app component without a
per-channel rebuild.

**Standard types** ship with the platform, each with a default editor and renderer, so you write
neither:

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

**Custom types** override the default interface for complex interactions. They are metadata:
**`LightningTypeBundle`**, available from **API version 64.0**.

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
- **Channel folders are optional** and only needed to override the UI for a specific application:

| Channel folder | Renders in |
|---|---|
| `lightningDesktopGenAi` | Agentforce Employee agent in Lightning Experience |
| `enhancedWebChat` | Agentforce Service agent via Enhanced Chat v2 |
| `lightningMobileGenAi` | Employee agent on mobile, and Service agent via Enhanced Chat v2 on mobile |
| `experienceBuilder` | Experience Builder |

- **`editor.json`** carries the custom editing UI, **`renderer.json`** the custom display UI.
  **`renderer.json` is not supported in `experienceBuilder`.**

**HXL widgets (Beta) invert this.** When a custom type references a widget, put `renderer.json` at
the **root**, parallel to `schema.json`, with **no channel folder and no `editor.json`**. Applying the
channel-folder pattern here is a quiet failure.

To list the custom and standard types deployed in an org, call the Connect REST resource
`/connect/lightning-types`.

## Apex-backed custom types — the requirements that bite

These exist because of namespaced orgs and managed packages, and skipping them fails at invocation
rather than at deploy.

- **Top-level classes only.** Every class in its own file; **no inner classes**.
- **`global` visibility on all of them.** `public` or `private` causes failures in namespaced orgs and
  managed packages.
- **`@AuraEnabled` on every field** required in the response — including fields inside objects used as
  an `@InvocableVariable`.
- **`@JsonAccess(serializable='always' deserializable='always')` on every class**, so the internal
  invocation layer can process the data.
- **Namespace prefix**: `c` for local org classes; the registered namespace for a managed package.

**Supported data types**: primitives (Integer, Double, Long, Date, Datetime, Time, String, ID,
Boolean), sObjects generic or specific, collections (lists or arrays of primitives, sObjects,
user-defined classes and collections; maps whose key is always a String), and user-defined Apex
classes.

> **If an agent action was created before the Apex met these requirements, delete and recreate the
> action after fixing the classes.** Updating the Apex alone does not re-register the change, and the
> symptom is an action that keeps behaving as it did before.

## When to use them

Use Lightning Types when the **same capability must appear across several channels** — that is the
whole point of separating definition from rendering. When the target is only Lightning Experience,
a plain LWC is simpler and better supported; see `dya-lwc`.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| Building a custom type for something a standard type covers | Standard types ship with an editor and renderer already |
| Assuming every standard type renders in every application | Support varies by application — verify for your channel |
| `renderer.json` inside a channel folder for an HXL widget | Root level, parallel to `schema.json`, no `editor.json` |
| `renderer.json` under `experienceBuilder` | Not supported there |
| Inner classes, or `public` visibility, in Apex-backed types | Top-level and `global`, or it fails in namespaced orgs |
| Omitting `@JsonAccess` | The invocation layer cannot process the data |
| Fixing the Apex and expecting the agent action to follow | Delete and recreate the action to re-register it |
| Lightning Types for a single-channel Lightning Experience UI | A plain LWC |
