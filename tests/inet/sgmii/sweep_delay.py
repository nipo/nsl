#!/usr/bin/env python3
"""Sweep the tb delay generics through one bit period and report pass/fail.

Runs the ./simulator.exe wrapper (which ends in `tb "$@"`), passing
-g<generic>=<integer picoseconds> plus --stop-time so a stuck aligner cannot run forever.

Example:
  ./sweep_delay.py --sim ./simulator.exe --start 0 --stop 800 --step 25 \
      --stop-time 2ms --csv sweep.csv
"""
import argparse
import csv
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

STOP_MSG = "simulation stopped by --stop-time"


def run_one(args, offset_ps):
    clk_ps = args.clk_base_ps
    data_ps = args.data_base_ps
    if args.sweep == "data":
        data_ps += offset_ps
    else:
        clk_ps += offset_ps

    cmd = [
        args.sim,
        f"-g{args.clk_generic}={clk_ps}",
        f"-g{args.data_generic}={data_ps}",
        f"--stop-time={args.stop_time}",
    ]
    try:
        p = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=args.timeout,
        )
    except subprocess.TimeoutExpired as e:
        out = e.stdout.decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return offset_ps, "TIMEOUT", out

    out = p.stdout
    if STOP_MSG in out:
        status = "STOPTIME"          # sim never finished: aligner stuck
    elif p.returncode != 0:
        status = "FAIL"
    elif args.fail_regex and re.search(args.fail_regex, out):
        status = "FAIL"
    elif args.pass_regex and not re.search(args.pass_regex, out):
        status = "FAIL"
    else:
        status = "PASS"
    return offset_ps, status, out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", default="./simulator.exe", help="simulator wrapper script")
    ap.add_argument("--sweep", choices=["data", "clk"], default="data",
                    help="which delay to sweep (default: data)")
    ap.add_argument("--data-generic", default="data_delay_ps_c",
                    help="integer generic holding the data delay in ps")
    ap.add_argument("--clk-generic", default="clk_delay_ps_c",
                    help="integer generic holding the clock delay in ps")
    ap.add_argument("--data-base-ps", type=int, default=2000, help="base data delay (ps)")
    ap.add_argument("--clk-base-ps", type=int, default=3000, help="base clock delay (ps)")
    ap.add_argument("--start", type=int, default=0, help="first offset (ps)")
    ap.add_argument("--stop", type=int, default=800, help="last offset, inclusive (ps)")
    ap.add_argument("--step", type=int, default=25, help="offset step (ps); tap is 57 ps, so <=25 is safe")
    ap.add_argument("--stop-time", default="2ms",
                    help="GHDL --stop-time; must exceed a normal passing run")
    ap.add_argument("--timeout", type=float, default=600, help="wall-clock timeout per run (s)")
    ap.add_argument("--jobs", type=int, default=4, help="parallel simulations")
    ap.add_argument("--pass-regex", help="output must match this to count as PASS")
    ap.add_argument("--fail-regex", help="output matching this counts as FAIL")
    ap.add_argument("--csv", help="write results to this CSV file")
    ap.add_argument("--show-failures", action="store_true",
                    help="print the last lines of output for failing runs")
    args = ap.parse_args()

    offsets = list(range(args.start, args.stop + 1, args.step))
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        results = sorted(ex.map(lambda o: run_one(args, o), offsets))

    base = args.data_base_ps if args.sweep == "data" else args.clk_base_ps
    print(f"Sweeping {args.sweep} delay, base {base} ps")
    print(f"{'offset_ps':>9} {'delay_ps':>9}  result")
    for off, status, out in results:
        print(f"{off:>9} {base + off:>9}  {status}")
        if args.show_failures and status != "PASS":
            tail = "\n".join(out.strip().splitlines()[-5:])
            print("    " + tail.replace("\n", "\n    "))

    npass = sum(1 for _, s, _ in results if s == "PASS")
    print(f"\n{npass}/{len(results)} passed")

    if args.csv:
        with open(args.csv, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["offset_ps", "delay_ps", "result"])
            for off, status, _ in results:
                w.writerow([off, base + off, status])

    return 0 if npass == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
