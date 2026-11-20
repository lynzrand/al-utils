"""Regression checks for benchmark state rejection and timing availability."""

from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('comparison', Path(__file__).with_name('summarize-shadow-comparison.py'))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


def run(state):
    return {'path': Path('trial.json'), 'metadata': {'Start': deepcopy(state), 'End': deepcopy(state)}}


class ShadowComparisonTests(unittest.TestCase):
    def setUp(self):
        self.state = dict.fromkeys(comparison.STATE_FIELDS, 'same')
        self.state.update(Focused=True, URP={'renderScale': 1},
                          Cameras=[{'name': 'Main Camera', 'Position': [1.0, 2.0, 3.0]}])

    def test_different_snapshot_timestamps_are_not_render_state(self):
        a, b = run(self.state), run(self.state)
        a['metadata']['Start']['At'] = 'first'
        b['metadata']['End']['At'] = 'later'
        self.assertEqual(comparison.compare_recorded_state([a, b]), [])

    def test_small_camera_drift_is_rejected_and_located(self):
        a, b = run(self.state), run(self.state)
        b['metadata']['End']['Cameras'][0]['Position'][1] += 1e-6
        problems = comparison.compare_recorded_state([a, b])
        self.assertEqual(len(problems), 1)
        self.assertIn('End: Cameras[0].Position[1]', problems[0])

    def test_urp_change_and_focus_loss_are_both_rejected(self):
        a, b = run(self.state), run(self.state)
        b['metadata']['Start']['Focused'] = False
        b['metadata']['Start']['URP']['renderScale'] = .85
        problems = comparison.compare_recorded_state([a, b])
        self.assertEqual(len(problems), 2)
        self.assertTrue(any('URP.renderScale' in problem for problem in problems))
        self.assertTrue(any('unfocused' in problem for problem in problems))

    def test_missing_nested_field_and_camera_are_rejected(self):
        a, b = run(self.state), run(self.state)
        del b['metadata']['Start']['Cameras'][0]['name']
        b['metadata']['End']['Cameras'] = []
        problems = comparison.compare_recorded_state([a, b])
        self.assertTrue(any('Cameras[0].name: field missing' in p for p in problems))
        self.assertTrue(any('Cameras: length 1 -> 0' in p for p in problems))

    def test_unavailable_cpu_timing_does_not_become_zero_cost(self):
        self.assertIn('UnityCpuFrameMs', comparison.TIMINGS)
        self.assertIsNone(comparison.timing_summary([{'UnityCpuFrameMs': ''}, {'UnityCpuFrameMs': '0'}], 'UnityCpuFrameMs'))
        stats = comparison.timing_summary([{'UnityCpuFrameMs': ''}, {'UnityCpuFrameMs': '12.5'}], 'UnityCpuFrameMs')
        self.assertEqual(stats['n'], 1)
        self.assertEqual(stats['p50'], 12.5)

    def test_invalid_frame_intervals_fail_instead_of_disappearing(self):
        for value in ('', '0', '-1', 'nan', 'inf'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                comparison.timing_summary([{'FrameIntervalMs': value}], 'FrameIntervalMs')


if __name__ == '__main__':
    unittest.main()
