# Data Custom Code — Python Transforms Inside Data 360

For transformation logic that Data Streams, formulas and Calculated Insights cannot express: Python
on Data 360 compute, reading and writing DLOs and DMOs directly.

Use it when the transform needs a library — statistical work, fuzzy matching, parsing a format
nobody else supports — not because Python is more familiar than SQL. Anything expressible as
a Calculated Insight is cheaper as one.

## Two shapes

| Shape | CLI | Runs |
|---|---|---|
| **Script** | `sf data-code-extension script …` | Batch, on a schedule or on demand |
| **Function** | `sf data-code-extension function …` | Real-time, per event |

## Toolchain

```bash
sf plugins install @salesforce/plugin-data-code-extension
pip install salesforce-data-customcode
```

**Python 3.11 exactly**, not 3.12 or 3.10. On this machine that means `py -3.11`; install 3.11 if it
is missing.

**Docker is required for `deploy`, not for `run`**, so iterating locally needs no container.

## Commands

```bash
sf data-code-extension script init --name my_transform
sf data-code-extension script scan                      # generates config.json by static analysis
sf data-code-extension script run                       # local, against REAL Data 360 data
sf data-code-extension script deploy --package-dir ./payload --cpu-size CPU_2XL
```

**`--package-dir` must point at `./payload`, not the project root**; otherwise deploy fails with an
error that does not say so.

## Project shape

```text
my_transform/
    payload/
        entrypoint.py
        config.json
    requirements.txt
```

`config.json` declares what the code may touch and how much compute it gets:

```json
{
    "permissions": {
        "read":  ["Order__dll"],
        "write": ["OrderEnriched__dlm"]
    },
    "resources": { "cpu_size": "CPU_2XL" }
}
```

`script scan` generates it by statically analysing the entrypoint; rerun it after changing which
objects the code reads or writes rather than hand-editing the file.

## The Python API

```python
from datacustomcode import Client

client = Client()

df = client.read_dlo('Order__dll')          # or client.read_dmo('UnifiedOrder__dlm')
# ... transform with pandas, numpy, whatever requirements.txt declares ...
client.write_to_dlo('OrderScored__dll', df, 'overwrite')
client.write_to_dmo('OrderScored__dlm', df, 'upsert')
```

Write modes differ by target, and the wrong one is accepted at authoring time:

| Target | Modes |
|---|---|
| DLO | `overwrite`, `append` |
| DMO | `upsert`, `insert` |

The function shape uses `FunctionClient(context)` with a `transform(event, context)` entry point
instead.

## Sizing

`--cpu-size` takes `CPU_L`, `CPU_XL`, `CPU_2XL` or `CPU_4XL`, defaulting to **`CPU_2XL`**. Rough
bands:

```text
< 1M records        CPU_L
1M - 5M             CPU_XL
5M - 10M            CPU_2XL   (the default)
> 10M               CPU_4XL
```

The default is two steps up, so a small transform is over-provisioned unless sized down, and Data 360
compute is credit-metered (SKILL.md §8).

## Local runs hit real data

**`script run` executes against real Data 360 data**; there is no local fixture layer, so a run that
writes will write. Develop against a dataspace you are willing to dirty, and keep the write call
commented out until the transform's output looks right.
