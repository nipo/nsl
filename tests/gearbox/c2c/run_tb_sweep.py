#!/usr/bin/env python3
"""
Sweep test-bench generics and run the ./tb binary for each combination.

Constraint enforced when generating cases:
  - One data width must be an integer multiple `k` of the other.
  - The SAME multiple `k` must apply to the clock periods.
  - The slower clock (bigger period) goes with the bigger width.

i.e. if output_width_c = k * input_width_c
     then output_clock_period_ns_c = k * input_clock_period_ns_c   (output side is slower)

and symmetrically if input_width_c = k * output_width_c
     then input_clock_period_ns_c = k * output_clock_period_ns_c   (input side is slower)
"""

import subprocess
import sys
from dataclasses import dataclass, field

TB_BINARY = "./tb"

# ---- Sweep parameters ------------------------------------------------

BASE_WIDTHS = [4, 8, 16]          # "smaller" width candidates
MULTIPLIERS = [1, 2]           # k: how many times bigger the other width/clock is
BASE_CLOCK_PERIOD_NS = 8          # period (ns) of the faster clock, paired with the smaller width
LEFT_TO_RIGHT_VALUES = [True, False]


@dataclass
class TestCase:
    input_width_c: int
    output_width_c: int
    input_clock_period_ns_c: int   # ns
    output_clock_period_ns_c: int  # ns
    left_to_right_c: bool

    def generic_args(self):
        return [
            f"-ginput_width_c={self.input_width_c}",
            f"-goutput_width_c={self.output_width_c}",
            f"-ginput_clock_period_ns_c={self.input_clock_period_ns_c}",
            f"-goutput_clock_period_ns_c={self.output_clock_period_ns_c}",
            f"-gleft_to_right_c={'true' if self.left_to_right_c else 'false'}",
        ]

    def __str__(self):
        return (
            f"input_width={self.input_width_c}, output_width={self.output_width_c}, "
            f"input_clk={self.input_clock_period_ns_c}, output_clk={self.output_clock_period_ns_c}, "
            f"left_to_right={self.left_to_right_c}"
        )


def generate_test_cases():
    """Generate TestCase objects that satisfy the width/clock multiple rule."""
    cases = []
    seen = set()

    for base_width in BASE_WIDTHS:
        for k in MULTIPLIERS:
            base_clock = BASE_CLOCK_PERIOD_NS

            # Case A: output is the bigger side (output_width = k * input_width,
            # output_clock = k * input_clock, since bigger width -> slower clock)
            in_w, out_w = base_width, base_width * k
            in_clk, out_clk = base_clock, base_clock * k
            for ltr in LEFT_TO_RIGHT_VALUES:
                key = (in_w, out_w, in_clk, out_clk, ltr)
                if key not in seen:
                    seen.add(key)
                    cases.append(TestCase(in_w, out_w, in_clk, out_clk, ltr))

            # Case B: input is the bigger side (input_width = k * output_width,
            # input_clock = k * output_clock)
            in_w, out_w = base_width * k, base_width
            in_clk, out_clk = base_clock * k, base_clock
            for ltr in LEFT_TO_RIGHT_VALUES:
                key = (in_w, out_w, in_clk, out_clk, ltr)
                if key not in seen:
                    seen.add(key)
                    cases.append(TestCase(in_w, out_w, in_clk, out_clk, ltr))

    return cases


def run_case(case: TestCase, binary=TB_BINARY, timeout=60):
    cmd = [binary] + case.generic_args()
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout
        )
        passed = result.returncode == 0
        return passed, result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, None, "", "TIMEOUT"
    except FileNotFoundError:
        print(f"Error: could not find binary '{binary}'. Build it first (make).")
        sys.exit(1)


def main():
    cases = generate_test_cases()
    print(f"Generated {len(cases)} test cases.\n")

    results = []
    for i, case in enumerate(cases, start=1):
        print(f"[{i}/{len(cases)}] {case}")
        passed, rc, stdout, stderr = run_case(case)
        results.append((case, passed, rc))

        status = "PASS" if passed else "FAIL"
        print(f"    -> {status} (return code: {rc})")
        if not passed:
            # show tail of output to help debugging without flooding the terminal
            tail = (stdout + stderr).strip().splitlines()[-10:]
            for line in tail:
                print(f"       {line}")
        print()

    # ---- Summary ----
    n_pass = sum(1 for _, passed, _ in results if passed)
    n_fail = len(results) - n_pass
    print("=" * 60)
    print(f"Summary: {n_pass} passed, {n_fail} failed, {len(results)} total")

    if n_fail:
        print("\nFailed cases:")
        for case, passed, rc in results:
            if not passed:
                print(f"  - {case} (rc={rc})")
        sys.exit(1)


if __name__ == "__main__":
    main()
