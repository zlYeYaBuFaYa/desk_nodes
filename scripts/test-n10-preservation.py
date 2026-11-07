#!/usr/bin/env python3
"""Run the real N10 checker in independent, minimal Git repositories."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
ORIGINAL = '5e6443371a6181f63fe30cd41d8c6f023ea8410b'


class PreservationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='native-n10-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                        GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                        PYTHONDONTWRITEBYTECODE='1')
        # Only the checker and its actual inputs; no clone, alternates, or author objects.
        manifest = json.loads((SOURCE/'scripts/n10-protected-files.json').read_text())
        files = list(manifest) + [
            'scripts/check-n10.py', 'scripts/n10_preservation.py',
            'scripts/n10-protected-files.json', 'scripts/build-macos.sh',
            'Resources/Info.plist', 'Resources/DeskNodes.icns', 'Resources/DeskNodes-icon.png',
            *[f'Sources/DeskNodesApp/{name}.swift' for name in
              ['NotePanel', 'WindowChrome', 'SettingsWindow', 'Application', 'DeletionToast', 'DockController']]]
        for name in files:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE/name, target)
        self.git('init', '--quiet')
        self.commit('independent baseline')
        self.assertNotEqual(self.git('rev-parse', 'HEAD').stdout.strip(), ORIGINAL)
        self.assertNotEqual(self.git('cat-file', '-e', ORIGINAL, check=False).returncode, 0)
        self.assertFalse((self.root/'.git/objects/info/alternates').exists())

    def git(self, *args, check=True):
        return subprocess.run(['git', *args], cwd=self.root, env=self.env,
                              capture_output=True, text=True, check=check)

    def commit(self, message):
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', message)

    def audit(self, passes=True):
        result = subprocess.run(['python3', str(self.root/'scripts/check-n10.py')],
                                cwd='/', env=self.env, capture_output=True, text=True)
        if passes:
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertIn('N10 protected', result.stderr)

    def test_review_committed_and_followup_histories(self):
        (self.root/'review.txt').write_text('uncommitted N10 review')
        self.audit()
        self.commit('integrated N10 on unrelated parent')
        self.audit()
        (self.root/'review.txt').write_text('followup')
        self.commit('N10 reproducibility followup')
        self.audit()

    def test_changes_to_each_protected_category_fail(self):
        for name in ['docs/spec/macos-native/requirements.md', 'docs/macos-native-plan.md',
                     *[f'docs/native-n{i}.md' for i in range(1, 10)]]:
            with self.subTest(name=name):
                path = self.root/name
                original = path.read_bytes()
                path.write_bytes(original+b'\naltered\n')
                self.audit(False)
                self.git('add', name)  # staged changes must also fail
                self.audit(False)
                path.write_bytes(original)
                self.git('add', name)

    def test_altered_parent_and_followup_cannot_redefine_baseline(self):
        path = self.root/'docs/native-n9.md'
        path.write_bytes(path.read_bytes()+b'\naltered in alternate parent\n')
        self.commit('different parent with changed protected content')
        (self.root/'review.txt').write_text('N10')
        self.commit('N10 integration')
        (self.root/'review.txt').write_text('followup')
        self.commit('followup')
        self.audit(False)

    def test_added_deleted_mode_and_symlink_fail(self):
        extra = self.root/'docs/spec/extra.txt'
        extra.write_text('unexpected')
        self.audit(False)
        extra.unlink()
        path = self.root/'docs/native-n1.md'
        original = path.read_bytes()
        path.unlink()
        self.audit(False)
        path.write_bytes(original)
        path.chmod(0o755)
        self.audit(False)
        path.unlink()
        path.symlink_to(self.root/'docs/native-n2.md')
        self.audit(False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
