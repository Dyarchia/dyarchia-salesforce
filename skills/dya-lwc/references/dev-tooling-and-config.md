# Component Configuration and Dev Tooling — Reference (Winter '27 / API v68.0)

Load from `dya-lwc` when configuring a component bundle or setting up the local development loop.

## The bundle's meta XML

Every component has a `<component>.js-meta.xml` beside its JavaScript. It decides where the component
can be dropped and what an admin can configure.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>68.0</apiVersion>
    <isExposed>true</isExposed>
    <targets>
        <target>lightning__RecordPage</target>
        <target>lightning__RecordAction</target>
    </targets>
    <targetConfigs>
        <targetConfig targets="lightning__RecordAction">
            <actionType>ScreenAction</actionType>
        </targetConfig>
    </targetConfigs>
</LightningComponentBundle>
```

`isExposed` false means the component can only be used by other components — the right default for a
building block. A component with no `targets` cannot be placed on a page at all, which is the usual
cause of "my component doesn't appear in the Lightning App Builder".

The `apiVersion` here is the one that decides the component's runtime semantics, and it is per bundle,
not per org.

## SLDS styling hooks for Flow Screen components

For a component targeting `lightning__FlowScreen`, expose colour, radius, weight and other CSS custom
properties through `<targetConfig>`. They then appear on the Flow Builder **Style** tab, so an admin
themes the component without touching its code. Group related hooks so the panel reads as a design
system rather than a list of variables.

## Local development

```bash
# Preview one component in the browser
sf lightning dev component --name myComponent

# Preview the whole app, desktop or mobile
sf lightning dev app --target-org myOrg
```

In VS Code: install the Salesforce Extension Pack, then Command Palette › *SFDX: Open in Lightning
Preview*. Live preview supports public LDS wire adapters, `@salesforce` scoped modules, and Apex
controllers, so most components run without deploying.

Hot Module Reloading applies an edit without a full page reload, which is what makes the loop worth
using at all.

These commands need a **DX project** — a directory containing an `sfdx-project.json` that names the
package directories. Outside one, `sf` has nothing to resolve component paths against. See
`references/shared/org-model.md`.

## TypeScript

Install `@salesforce/lightning-types` for official base-component type definitions. TypeScript source
compiles locally and only the resulting `.js` is deployed, so the org never sees TypeScript and no
runtime behaviour depends on it.

## Dynamic Lists virtualization — Developer Preview

`lightning-dynamic-list-container` and `lightning-dynamic-list-item` render only the rows currently in
the viewport, which is the standard answer for lists of thousands of records. It is **Developer
Preview**: not available in production orgs, and not something to design a delivery around yet. Until
it advances, page the data instead — GraphQL's `first` and `after` with `endCursor`.

## Anti-Patterns

| Anti-Pattern | Correct approach |
|---|---|
| A component that does not appear in App Builder | Check `isExposed` and `targets` in the meta XML |
| `isExposed` true on an internal building block | Leave it false; expose only what an admin should place |
| Hardcoded colours in a Flow Screen component | SLDS styling hooks through `<targetConfig>` |
| Deploying to test every change | `sf lightning dev component` with hot reloading |
| Running `sf lightning dev` outside a DX project | Run it from a directory with an `sfdx-project.json` |
| Shipping Dynamic Lists virtualization to production | Developer Preview — page with GraphQL `first`/`after` instead |
