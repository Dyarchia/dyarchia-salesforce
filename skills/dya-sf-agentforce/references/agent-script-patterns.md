# Agent Script Patterns — Reference (Winter '27 / API v68.0)

The standard ways to combine Agent Script constructs into reliable behaviour, each as rules plus a minimal example.

Syntax of every construct used here: `references/agent-script.md`. Traps: `references/agent-control-flow-pitfalls.md`.

## Choosing a pattern

| Requirement | Pattern |
|---|---|
| The LLM needs current data before it answers | 1. Fetch data before reasoning |
| Different prompt, action or route per state | 2. Conditionals |
| Several actions must run in a fixed order | 3. Action chaining |
| An option must not exist until a rule holds | 4. Filtering with `available when` |
| A step must happen before anything else | 5. Required flow |
| An ordered questionnaire across many turns | 6. Step variable across turns |
| Route each utterance to the right job | 7. Agent router |
| Move between subagents | 8. Transitions |
| Point the LLM at a specific value or tool | 9. Resource references |
| One subagent needs different global rules | 10. System overrides |
| Keep state across turns and subagents | 11. Variables and slot filling |
| Walk a list one item per turn | 12. List variables |
| Collect several fields, then create one record | 13. Collect then commit |
| Borrow another subagent and come back | 14. Delegation with return |
| Hand to a human or close the session | 15. Escalate and end |

General rules for every pattern:

- Start with the fewest instructions that work; add one line at a time and re-test for regressions.
- Use one term per concept across names and descriptions ("member" everywhere, never "member" here and "patron" there),
  in the words users actually say.
- Make names and descriptions of subagents, tools and variables specific and non-overlapping.
- Add determinism where a business rule or workflow must hold; leave conversation to the LLM.
- Reference the exact variable or tool in prompt text when the LLM must use it.

## 1. Fetch data before reasoning

- Run lookups at the top of `reasoning.instructions`, so the result is in the prompt before the LLM reads it.
- Guard each lookup on its target variable so it runs once, not on every turn.
- Store every output the prompt or a condition needs with `set`, then merge it with `{!...}`.

```agentscript
reasoning:
    instructions: ->
        if @variables.loan_summary == "":
            run @actions.get_loans
                with member_id = @variables.member_id
                set @variables.loan_summary = @outputs.summary
                set @variables.overdue_count = @outputs.overdue_count
        | The member's current loans: {!@variables.loan_summary}.
        if @variables.overdue_count > 0:
            | Remind them politely about the overdue items before anything else.
```

A sentinel default (`"NotLoaded"` instead of `""`) works when an empty string is a legitimate result.

## 2. Conditionals

- Decide in logic which instructions the LLM receives; it never sees the branches not taken.
- Use conditionals for three things: which `|` text is included, which action runs, which subagent comes next.
- Use `else if` for mutually exclusive cases; sequential `if` statements when several may apply.
- Default every variable a condition reads, and use `is None` only for "never assigned".

```agentscript
reasoning:
    instructions: ->
        | Help {!@variables.member_name} with their account.
        if @variables.tier == "student":
            | Mention that student cards allow 10 loans at once.
        else if @variables.tier == "senior":
            | Mention free home delivery for senior members.
        if @variables.fines_due > 20:
            transition to @subagent.fines
```

## 3. Action chaining

Four ways to guarantee order, from most to least deterministic:

| Form | Where | Inputs |
|---|---|---|
| Sequential `run` lines | `reasoning.instructions` or `after_reasoning` | Bound explicitly |
| Conditional chain (`run`, then `if` on its stored output, then `run`) | `reasoning.instructions` | Bound explicitly |
| `run` nested under a tool | `reasoning.actions` | Tool can slot-fill; chained `run` cannot |
| `transition to` under a tool | `reasoning.actions` | Handoff after the tool completes |

- Pass data between steps through variables: `set` the first output, bind it in the next `with`.
- A chained `run` fires every time the LLM calls its parent tool.

```agentscript
reasoning:
    instructions: ->
        | When the member names a title, use {!@actions.reserve_title}.
    actions:
        reserve_title: @actions.reserve_title
            with isbn = ...
            with member_id = @variables.member_id
            set @variables.hold_id = @outputs.hold_id
            run @actions.send_hold_notice
                with hold_id = @variables.hold_id
                set @variables.notice_sent = @outputs.sent
            transition to @subagent.hold_confirmation
```

```agentscript
reasoning:
    instructions: ->
        run @actions.check_card_status
            with member_id = @variables.member_id
            set @variables.card_active = @outputs.active
        if @variables.card_active == True:
            run @actions.get_recommendations
                with member_id = @variables.member_id
                set @variables.picks = @outputs.titles
            | Suggest these titles: {!@variables.picks}.
        else:
            | Explain that the card has expired and how to renew it at a branch.
```

## 4. Filtering with `available when`

- Hide a tool or a route entirely until its business rule holds; a hidden tool cannot be talked into.
- Gate every side-effecting tool, every sensitive route, and every tool that should run at most once.
- Group mixed `and` / `or` with parentheses.
- Filtering removes options; it does not force a step. Use pattern 5 for that.

```agentscript
reasoning:
    actions:
        cancel_hold: @actions.cancel_hold
            with hold_id = @variables.hold_id
            available when @variables.is_verified == True and @variables.hold_id != ""
        waive_fine: @actions.waive_fine
            available when @variables.is_staff == True and (@variables.fines_due < 5 or @variables.first_offence == True)
```

## 5. Required flow

| Approach | Use when |
|---|---|
| `available when` | The LLM may choose among the options that remain |
| Conditional `transition to` at the top of instructions | A step must happen first; no LLM choice |
| Step variable across turns (pattern 6) | Several required steps in an order that depends on answers |

- Put the guarding `if ... transition to` as the **first** statements: anything resolved before a transition is thrown
  away, and actions run there still cost time and money.
- When the condition holds, no prompt is sent and no classification happens; the target subagent runs instead.
- Works in `start_agent` (gate everything) and in any subagent (gate one prerequisite).

```agentscript
start_agent library_router:
    description: "Route members to lending, reservations or account help."
    reasoning:
        instructions: ->
            if @variables.is_verified == False:
                transition to @subagent.verify_member
            | Pick the tool that matches what the member wants.
        actions:
            go_to_loans: @utils.transition to @subagent.loans
                description: "Renewals, due dates and returns of books on loan."
            go_to_reservations: @utils.transition to @subagent.reservations
                description: "Placing or cancelling holds on titles."
```

```agentscript
subagent reservations:
    description: "Place or cancel holds on titles."
    reasoning:
        instructions: ->
            if @variables.pickup_branch == "":
                transition to @subagent.choose_branch
            | Help the member place a hold for pickup at {!@variables.pickup_branch}.
```

## 6. Step variable across turns

- Keep a single step variable; the router transitions on its value at the top of its instructions.
- Each step subagent owns one question: it keeps asking until the answer is adequate, then sets the next step with
  `@utils.setVariables`.
- Use explicit step values (`"Card"`, `"Branch"`, `"Done"`), never numbers.
- Reserve this for long or branching sequences; one prerequisite only needs pattern 5.

```agentscript
start_agent intake_router:
    description: "Drive the membership application one step at a time."
    reasoning:
        instructions: ->
            if @variables.step == "Residency":
                transition to @subagent.residency
            if @variables.step == "Age":
                transition to @subagent.age_check
            if @variables.step == "Closed":
                transition to @subagent.close_application

subagent residency:
    description: "Confirm the applicant lives in the library district."
    reasoning:
        instructions: ->
            | Ask whether the applicant lives in the district and for their postcode.
              If they qualify, call {!@actions.set_step} with step "Age".
              If they do not, call {!@actions.set_step} with step "Closed".
        actions:
            set_step: @utils.setVariables
                description: "Record the next application step."
                with step = ...
```

## 7. Agent router

- `start_agent` runs first for each utterance: welcome, classify, route, and gate.
- Expose one `go_to_<destination>` transition tool per routable subagent, each with a description of what that
  subagent handles, in the user's words.
- Leave out of the router any subagent reachable only by transition from another subagent.
- Start with the essential subagents; every extra route is another classification decision.
- Combine the router with pattern 4 (hide routes by state) and pattern 5 (force routes by state).
- Keep `model://sfdc_ai__DefaultEinsteinHyperClassifier` on the router only when it needs nothing but transitions.

## 8. Transitions

| Kind | Syntax | Decided by |
|---|---|---|
| LLM-chosen | `go_to_x: @utils.transition to @subagent.x` in `reasoning.actions` | LLM |
| Gated LLM-chosen | Same, plus `available when` | LLM within the rule |
| Deterministic | `transition to @subagent.x` in instructions, `before_reasoning` or `after_reasoning` | Runtime |
| After an action | `transition to @subagent.x` under a tool or `run` | Runtime, once the action completes |

- Use deterministic transitions only where routing must be guaranteed; otherwise let the LLM choose.
- Name the transition tool in prompt text when the moment to use it is subtle: `go to {!@actions.go_to_fines}`.
- Transitions are one-way; add an explicit transition back when the flow must return, and expect the target to start
  from its top.
- Break cycles: never let A's logic send to B while B's logic sends straight back to A.

```agentscript
subagent fines:
    description: "Explain and settle overdue fines."
    reasoning:
        instructions: ->
            | Explain the fines and offer {!@actions.pay_fines}.
              When the member is done with fines, use {!@actions.go_back_to_loans}.
        actions:
            pay_fines: @actions.pay_fines
                with member_id = @variables.member_id
                set @variables.fines_due = @outputs.remaining
            go_back_to_loans: @utils.transition to @subagent.loans
                description: "Return to loan help once fines are handled."
    after_reasoning:
        if @variables.fines_due == 0:
            transition to @subagent.loans
```

## 9. Resource references

- Merge exact values into the prompt: `{!@variables.x}`, including formatted summaries the LLM must reproduce.
- Name the tool to use: `{!@actions.tool_name}`; it is a stronger signal than a description alone.
- Reference transition tools the same way, so the LLM knows when to leave.
- Add a reference when the subagent has many tools or similar tools; skip it when the choice is obvious.

```agentscript
reasoning:
    instructions: ->
        | Reply in exactly this format:
          Title: {!@variables.title}
          Due back: {!@variables.due_date}
          Renewals left: {!@variables.renewals_left}
          To extend the loan use {!@actions.renew_loan}. If the member is upset, use {!@actions.go_to_librarian}.
```

## 10. System overrides

- A subagent's own `system.instructions` replaces the global ones for that subagent; restate every global rule it still
  needs.
- Use an override when a global rule contradicts what the subagent must do; leaving the contradiction makes behaviour
  unpredictable.
- Use it to change tone or persona per subagent (formal for fines, playful for children's events).

```agentscript
system:
    instructions: "Assist adult library members. Never recommend titles rated for mature audiences to anyone."

subagent adult_book_club:
    description: "Plan the monthly adult book club reading list."
    system:
        instructions: "Assist adult book club members. Mature-rated titles are allowed here; flag them as mature."
    reasoning:
        instructions: ->
            | Propose three titles for next month and say why each suits the group.
```

## 11. Variables and slot filling

- Store in a variable anything a condition, an `available when`, another action or another subagent will read.
- Do not store what nothing reads; each variable needs a named consumer.
- Initialise text that is fetched later to `""`, flags to `False`; leave unset only values that must be supplied.
- Describe every variable the LLM sets, including its allowed values.
- Share state between subagents by writing a variable in one and reading it in the other.
- Slot fill with `@utils.setVariables` and `with v = ...`, or with `...` on a tool input. Slot filling works on tool
  inputs the LLM calls, never on a chained or deterministic `run`.
- Bind tool inputs to variables sparingly: a tool becomes selectable only once all its bound inputs are known.

```agentscript
variables:
    preferred_genre: mutable string = ""
        description: "Genre the member asks for, one of fiction, history, science, children."

subagent recommendations:
    description: "Recommend titles by genre."
    reasoning:
        instructions: ->
            | Ask which genre they enjoy and store it with {!@actions.save_genre}.
              Then use {!@actions.search_titles}.
        actions:
            save_genre: @utils.setVariables
                description: "Save the member's preferred genre."
                with preferred_genre = ...
            search_titles: @actions.search_titles
                with genre = @variables.preferred_genre
                available when @variables.preferred_genre != ""
```

## 12. List variables

- Iterate deterministically: hold a zero-based index variable, read the current item in instructions, advance the index
  in `after_reasoning`.
- Compare the index with `len(...)` before advancing so it never runs past the end; decide in logic what happens after
  the last item (transition, flag, or router instruction).
- Store an action's list output in a `list[object]` variable and read fields with `[i].data.<Field>`; use `json_path`
  only when the bracketed JSON form is wanted.

```agentscript
variables:
    q_index: mutable number = 0
    survey: mutable list[string] = ["How often do you visit?", "Which branch do you use?", "What should we stock more of?"]

subagent visitor_survey:
    description: "Ask the visitor survey one question per turn."
    reasoning:
        instructions: ->
            | This is question {!@variables.q_index + 1} of {!len(@variables.survey)}.
              Ask: {!@variables.survey[@variables.q_index]}
    after_reasoning:
        if @variables.q_index + 1 < len(@variables.survey):
            set @variables.q_index = @variables.q_index + 1
        else:
            transition to @subagent.survey_thanks
```

## 13. Collect then commit

Creates exactly one record, only after every field is known, and confirms only what actually happened.

- Capture fields with one `@utils.setVariables` tool, defaulting each to `""`.
- Gate the capture tool on "not yet committed" so a second record cannot start.
- In `after_reasoning`, run the create action only when every field is filled and no record ID exists yet.
- Transition to a confirmation subagent only when the action returned a record ID.
- Tell the LLM never to claim creation itself; the confirmation subagent owns that message.

```agentscript
subagent new_card:
    description: "Collect details and issue a new library card."
    reasoning:
        instructions: ->
            | Ask for full name, email and postcode in one message, then only for what is missing.
              Store details with {!@actions.capture}. Never say the card was issued.
        actions:
            capture: @utils.setVariables
                description: "Store applicant details as they are given."
                with full_name = ...
                with email = ...
                with postcode = ...
                available when @variables.card_number == ""
    after_reasoning:
        if @variables.full_name != "" and @variables.email != "" and @variables.postcode != "" and @variables.card_number == "":
            run @actions.issue_card
                with full_name = @variables.full_name
                with email = @variables.email
                with postcode = @variables.postcode
                set @variables.card_number = @outputs.card_number
        if @variables.card_number != "":
            transition to @subagent.card_issued
```

Make the backing Flow or Apex idempotent (look up before insert) and return an empty ID on failure, so the gate never
fires on a failed write. See `dya-sf-flow` and `dya-sf-apex`.

## 14. Delegation with return

- List a subagent as a tool (`@subagent.x`) when the caller still has work to do after it; control comes back.
- Use `@utils.transition to` instead when the target owns the rest of the conversation.
- If the delegated subagent itself transitions, that path runs to its end before control returns.

```agentscript
reasoning:
    actions:
        look_up_titles: @subagent.catalogue_search
            description: "Search the catalogue by author, subject or ISBN."
            available when @variables.is_verified == True
```

## 15. Escalate and end

- Expose `@utils.escalate` as a gated tool (business hours, explicit request) and describe exactly when it applies;
  the agent needs a `connection messaging` block.
- State in the router or subagent instructions when not to escalate (for example, never on frustration alone unless
  the member asks for a person), when that is policy.
- Expose `@utils.end_session` for a clean close, either in the subagent that finishes the task or in a dedicated
  closing subagent the router transitions to.

```agentscript
subagent closing:
    description: "The member says they need nothing else."
    reasoning:
        instructions: ->
            | Thank the member and end the conversation.
        actions:
            close: @utils.end_session
                description: "End the session now."
```

## Anti-Patterns

| Anti-pattern | Replacement |
|---|---|
| A lookup at the bottom of instructions, after the prompt that needs it | Run it first, store it, merge it |
| A lookup with no "already loaded" guard | Guard on the target variable or a sentinel |
| Prose saying "only offer X to verified members" | `available when @variables.is_verified == True` |
| `available when` used to force verification | Conditional `transition to` at the top |
| Work placed before a guarding transition | Transition first; it discards everything before it |
| Numbered step prose expected to enforce order | A step variable and router (pattern 6) |
| Creating a record from an LLM tool the user can trigger twice | Collect then commit, gated on the record ID |
| A global rule that contradicts one subagent | A subagent `system` override restating the rest |
| Index advanced in the prompt ("move to the next question") | `set` the index in `after_reasoning` |
| Transition back expecting to resume mid-subagent | Re-entry starts at the top; guard with state |
