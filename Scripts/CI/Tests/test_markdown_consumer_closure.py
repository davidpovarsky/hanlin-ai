import copy
import json
from pathlib import Path
import unittest

from Scripts.CI.prepare_markdown_consumer_closure import verify, verify_checkouts

ROOT = Path(__file__).resolve().parents[3]


class MarkdownConsumerClosureTests(unittest.TestCase):
    def setUp(self):
        self.contract = json.loads((ROOT/'docs/chat-diagnostics/markdown-consumer-closure-2026-11-15.json').read_text(encoding='utf-8'))
        self.lock = copy.deepcopy(self.contract['original_renderer_lock'])
        states = {p['identity']: p['state'] for p in self.contract['runtime_pin_projection']}
        for pin in self.lock['pins']:
            if pin['identity'] in states:
                pin['state'] = copy.deepcopy(states[pin['identity']])

    def test_app_runtime_states_and_original_test_dependencies_are_admitted(self):
        verify(self.lock, self.contract)
        self.assertEqual(len(self.lock['pins']), 10)
        syntax = next(p for p in self.lock['pins'] if p['identity'] == 'swift-syntax')
        self.assertEqual(syntax['state']['version'], '603.0.2')

    def test_old_parser_and_macro_closure_cannot_be_reused(self):
        with self.assertRaises(AssertionError):
            verify(self.contract['original_renderer_lock'], self.contract)

    def test_unknown_or_duplicate_dependencies_fail_instead_of_silent_pruning(self):
        for changed in [self.lock['pins'] + [self.lock['pins'][0]], self.lock['pins'][:-1]]:
            with self.assertRaises(AssertionError):
                verify({'pins': changed}, self.contract)

    def test_same_version_wrong_revision_or_repository_is_rejected(self):
        for field in ['revision', 'repository']:
            changed = copy.deepcopy(self.lock)
            pin = next(p for p in changed['pins'] if p['identity'] == 'swift-cmark')
            if field == 'revision':
                pin['state']['revision'] = '0' * 40
            else:
                pin['location'] = 'https://example.invalid/swift-cmark'
            with self.assertRaises(AssertionError):
                verify(changed, self.contract)

    def test_lock_alone_cannot_accept_old_actual_checkout(self):
        actual = [{'directory':p['identity'], 'revision':p['state']['revision']} for p in self.lock['pins']]
        verify_checkouts(actual, self.contract)
        next(x for x in actual if x['directory'] == 'swift-cmark')['revision'] = '924936d0427cb25a61169739a7660230bffa6ea6'
        with self.assertRaises(AssertionError):
            verify_checkouts(actual, self.contract)
