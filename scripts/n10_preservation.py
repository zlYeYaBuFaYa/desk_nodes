"""History-independent N10 preservation check, anchored to reviewed baseline bytes."""
import hashlib
import json
from pathlib import Path
import stat


def verify_protected_files(root):
    root = Path(root)
    manifest = json.loads((Path(__file__).with_name('n10-protected-files.json')).read_text())
    expected = set(manifest)
    fixed = ['docs/macos-native-plan.md', *[f'docs/native-n{i}.md' for i in range(1, 10)]]
    actual = {name for name in fixed if (root / name).exists()}
    spec = root / 'docs/spec'
    # Reject symlink directories as well as files; never follow them outside the tree.
    for path in [root / 'docs', spec, *spec.rglob('*')]:
        if path.is_symlink():
            raise AssertionError(f'N10 protected path is a symlink: {path.relative_to(root)}')
        if path.is_file():
            actual.add(path.relative_to(root).as_posix())
    if actual != expected:
        raise AssertionError(f'N10 protected paths changed: missing={sorted(expected-actual)}, added={sorted(actual-expected)}')
    for name, entry in manifest.items():
        path = root / name
        mode = path.lstat().st_mode
        if not stat.S_ISREG(mode):
            raise AssertionError(f'N10 protected file is not regular: {name}')
        git_mode = '100755' if mode & 0o111 else '100644'
        if git_mode != entry['mode'] or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            raise AssertionError(f'N10 protected file changed: {name}')
