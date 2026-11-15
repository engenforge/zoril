# Zoril Benchmark & Measurement Records

Append-only history on the orphan `records` branch:
- `gate_history.tsv`: per-host benchmark gate baselines and runs
- `speed_history.tsv`: cross-language benchmark timings
- `runtime_history.tsv`: per-program runtime and gate-size instruction counts against `gcc -O2`
- `marker_density_history.tsv`: compiler raw-pointer marker density census
- `figures_history.tsv`: milestone safety figures per commit

Mount this worktree once per clone:
  git fetch origin records && git worktree add bench/records records
