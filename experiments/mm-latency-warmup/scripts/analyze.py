"""One plot per config (run 1: sample index vs latency) and a table of mean +- std over all samples of all runs.

    python analyze.py [RESULTS_DIR] [GPU_NAME]     writes RESULTS_DIR/plots/<cfg>.png and RESULTS_DIR/summary.md
                                                   (defaults: results/ and MI210)
"""
import sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

RES = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'results'
GPU = sys.argv[2] if len(sys.argv) > 2 else 'MI210'
LABELS = {'A': 'original', 'B': 'current without warm-up and scrub', 'C': 'current without scrub',
          'D': 'current without warm-up', 'E': 'current (warm-up + scrub)'}
(RES / 'plots').mkdir(exist_ok=True)
rows = ['| cfg | description | mean ± std (cycles) |', '|---|---|---|']
for cfg, label in LABELS.items():
    runs = [np.loadtxt(f) for f in sorted(RES.glob(f'{cfg}/run*.txt'), key=lambda f: int(f.stem[3:]))]
    y = runs[0]
    fig, ax = plt.subplots(figsize=(12, 3.6))
    ax.plot(np.arange(len(y)), y, lw=0.7)
    ax.set_title(f'Main Memory Latency {GPU} - {cfg}: {label} (run 1)')
    ax.set_xlabel('Sample index'); ax.set_ylabel('Latency (cycles)')
    ax.set_ylim(*((400, 2400) if GPU == 'MI210' else (0, None))); ax.grid(True, ls='--', alpha=0.5)
    fig.tight_layout(); fig.savefig(RES / 'plots' / f'{cfg}.png', dpi=130); plt.close(fig)
    allsamples = np.concatenate(runs)
    rows.append(f'| {cfg} | {label} | {allsamples.mean():.0f} ± {allsamples.std():.0f} |')
(RES / 'summary.md').write_text('\n'.join(rows) + '\n')
print('\n'.join(rows))
