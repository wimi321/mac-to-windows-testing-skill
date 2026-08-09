#!/usr/bin/env python3
"""Score an AI fixture review against stable defect checkpoint IDs."""

from __future__ import annotations

import argparse
import json
import pathlib


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--review', required=True)
    parser.add_argument('--ground-truth', default='tests/fixtures/visual-ground-truth.json')
    args = parser.parse_args()
    truth = json.loads(pathlib.Path(args.ground_truth).read_text(encoding='utf-8-sig'))
    review = json.loads(pathlib.Path(args.review).read_text(encoding='utf-8-sig'))
    expected = set(truth['expected'])
    observed = {str(item.get('checkpoint', '')) for item in review.get('findings', [])}
    true_positive = len(expected & observed)
    false_positive = len(observed - expected)
    recall = true_positive / len(expected) if expected else 1.0
    fp_rate = false_positive / len(observed) if observed else 0.0
    result = {
        'recall': recall,
        'falsePositiveRate': fp_rate,
        'missed': sorted(expected - observed),
        'unexpected': sorted(observed - expected),
        'passed': recall >= truth['minimumRecall'] and fp_rate <= truth['maximumFalsePositiveRate'],
    }
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
