"""Round 2 (WARMUP_HOPS x SAMPLE_SIZE on config E): one plot per config (run 1), a 5x5 grid of all run-1 plots,
and a table of mean +- std. Mean and std are computed per run, then averaged over the 10 runs.

    python analyze_round2.py [RESULTS_DIR] [GPU_NAME]   writes RESULTS_DIR/plots/*.png and RESULTS_DIR/summary.md
                                                        (defaults: results/round2 and MI210)
"""
import sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

RES = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'results' / 'round2'
GPU = sys.argv[2] if len(sys.argv) > 2 else 'MI210'
HOPS = [0, 128, 512, 2048, 8192]
SIZES = [256, 512, 1024, 2048, 4096]
YLIM = (400, 2400) if GPU == 'MI210' else (0, None)


def load(h, n):
    files = sorted(RES.glob(f'W{h}_S{n}/run*.txt'), key=lambda f: int(f.stem[3:]))
    return [np.loadtxt(f) for f in files]


(RES / 'plots').mkdir(exist_ok=True)
grid, axes = plt.subplots(len(SIZES), len(HOPS), figsize=(4 * len(HOPS), 2.6 * len(SIZES)), squeeze=False)
rows = ['| SAMPLE_SIZE \\ WARMUP_HOPS | ' + ' | '.join(map(str, HOPS)) + ' |', '|---' * (len(HOPS) + 1) + '|']
for r, n in enumerate(SIZES):
    cells = []
    for c, h in enumerate(HOPS):
        runs = load(h, n)
        y = runs[0]
        fig, ax = plt.subplots(figsize=(12, 3.6))
        ax.plot(np.arange(len(y)), y, lw=0.7)
        ax.set_title(f'Main Memory Latency {GPU} - WARMUP_HOPS={h}, SAMPLE_SIZE={n} (run 1)')
        ax.set_xlabel('Sample index'); ax.set_ylabel('Latency (cycles)')
        ax.set_ylim(*YLIM); ax.grid(True, ls='--', alpha=0.5)
        fig.tight_layout(); fig.savefig(RES / 'plots' / f'W{h}_S{n}.png', dpi=130); plt.close(fig)

        g = axes[r, c]
        g.plot(np.arange(len(y)), y, lw=0.5)
        g.set_ylim(*YLIM); g.grid(True, ls='--', alpha=0.4)
        g.set_title(f'WARMUP_HOPS={h}, SAMPLE_SIZE={n}', fontsize=9)
        if c == 0: g.set_ylabel('Latency (cycles)')
        if r == len(SIZES) - 1: g.set_xlabel('Sample index')

        cells.append(f'{np.mean([x.mean() for x in runs]):.0f} ± {np.mean([x.std() for x in runs]):.0f}')
    rows.append(f'| **{n}** | ' + ' | '.join(cells) + ' |')
grid.suptitle(f'Main Memory Latency {GPU}, config E - run 1 of each WARMUP_HOPS x SAMPLE_SIZE configuration')
grid.tight_layout(); grid.savefig(RES / 'plots' / 'grid.png', dpi=110)
(RES / 'summary.md').write_text('\n'.join(rows) + '\n')
print('\n'.join(rows))
