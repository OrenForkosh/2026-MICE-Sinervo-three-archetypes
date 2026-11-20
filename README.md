# Three behavioral archetypes bound continuous personality variation in group-living male mice

Code and data behind every figure and statistic of the Letter.

Forkosh O, Niv L, Mordechay S, Sinervo B.

## Running it

First get ParTI, which is not bundled here (see below):

```bash
git clone https://github.com/AlonLabWIS/ParTI external/ParTI
```

Then open MATLAB and run `figures_v2.m`. It puts the bundled toolbox and ParTI
on the path, reads the tables in `data/`, prints each statistic reported in the
Letter, and writes the panels to `Res/`. If ParTI is missing it stops at once
and says so, rather than failing somewhere inside the fit.

Developed and checked on MATLAB R2026b. The Statistics and Machine Learning
Toolbox is required.

## ParTI

The triangle is fitted with SISAL from the Pareto Task Inference package of the
Alon lab (Hart et al. 2015, *Nat Methods* 12: 233–235), which lives in its own
repository and carries its own terms:

- <https://github.com/AlonLabWIS/ParTI>
- documentation: <http://www.weizmann.ac.il/mcb/UriAlon/download/ParTI>

Clone it to `external/ParTI` and the script finds it; otherwise put it on the
MATLAB path yourself. Any checkout containing `sisal.m` will do.

## What is here

| Path | |
|---|---|
| `figures_v2.m` | the analysis: Identity Domains, the triangle, the archetype profiles, the replication, and every panel |
| `data/PersonalityNew3.mat` | behavioral readouts of the original cohort, one row per mouse and day |
| `data/THREE_CHAMBER-exp.csv` | behavioral readouts of the replication cohort (176 mice, 44 groups) |
| `data/behaviors.v02.csv` | the readouts: name, display label, and type |
| `data/tracking.mat` | per-cell occupancy and chase counts, for Figures 2B and 2C |
| `toolbox/` | the lab functions the script calls |
| `external/ParTI/` | not included; clone it here (see below) |
| `Res/` | created on the first run |

## The two cohorts

The **original cohort** is the published data set of Forkosh et al. (2019,
*Nat Neurosci* 22: 2023–2028). Its readouts are included here so that this
repository runs on its own; the Identity Domain method and its own code are at
<https://orenforkosh.github.io/IdentityDomains/>.

The **replication cohort** was recorded at the Hebrew University and played no
part in building the personality space. Its readouts are released here for the
first time.

Neither the projection onto the Identity Domains nor the reference triangle is
refitted anywhere in this script. Both are the published 2019 ones.

## Notes

`figures_v2.m` is the working script with four paths rewritten so that they
resolve against this repository rather than the lab's directory layout:
`data_path`, `opt.outDir`, the line that loads `tracking.mat`, and the `Path`
now passed to `Identity.GetProps`, which would otherwise look beside its own
source file. Nothing else differs, and no analysis, parameter, or random seed
was changed.

`toolbox/` holds only the files this analysis reaches, not the full lab
library. It was derived from MATLAB's own dependency analysis and then checked
by running the script with the lab repository off the path, which is how the
list settled: static analysis alone misses `sisal`, because ParTI is invoked
through `evalc` by name.

The shape test and the bootstrap resample, so a rerun reproduces the reported
*P* values to Monte Carlo error rather than exactly.
