"""The scanner must never execute inspected code or expose literal/env values."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('inventory', REPO / 'scripts/code_env_inventory.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='levmet-inventory-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def names(self, result):
        return {row['name'] for row in result['variables']}

    def test_aliases_constants_and_path_wrappers_without_execution(self):
        marker = self.root / 'must-not-exist'
        self.write('app.py', f'''
from pathlib import Path
Path({str(marker)!r}).write_text("executed")
import os as operating
from os import getenv as read_value
ENV_DIR = "LEVMET_PRICE_ARCHIVE_DIR"
def folder(env_name, fallback):
    return operating.environ.get(env_name, fallback)
folder(ENV_DIR, "private-literal-default")
read_value("SENDGRID_API_KEY", "secret-literal-default")
operating.environ["user_email"]
''')
        report = MODULE.inventory(self.root)
        self.assertEqual(self.names(report), {'LEVMET_PRICE_ARCHIVE_DIR', 'SENDGRID_API_KEY', 'user_email'})
        self.assertFalse(marker.exists())
        self.assertNotIn('secret-literal-default', json.dumps(report))
        self.assertNotIn('private-literal-default', json.dumps(report))

    def test_broken_legacy_source_still_finds_literals(self):
        self.write('broken.py', 'import os\nos.environ["LEVMET_EMAIL_PASSWORD"]\ninvalid ???')
        report = MODULE.inventory(self.root)
        self.assertIn('LEVMET_EMAIL_PASSWORD', self.names(report))
        self.assertTrue(report['unresolved'])

    def test_models_notebooks_and_shell_variables(self):
        self.write('settings.py', '''
from pydantic_settings import BaseSettings
class Settings(BaseSettings):
    db_url: str = Field(validation_alias="RISK_DB_URL")
    paths: PathsSettings
''')
        notebook = {'cells': [{'cell_type': 'code', 'source': ['os.getenv("LEVMET_DOCS_ROOT")'], 'outputs': [{'text': 'os.getenv("NOT_SOURCE")'}]}]}
        self.write('analysis.ipynb', json.dumps(notebook))
        self.write('run.ps1', '$env:PYTHONUTF8 = "1"')
        report = MODULE.inventory(self.root)
        self.assertTrue({'RISK_DB_URL','DB_URL','PATHS','LEVMET_DOCS_ROOT','PYTHONUTF8'} <= self.names(report))
        self.assertNotIn('NOT_SOURCE', self.names(report))

    def test_venv_exclusion_dynamic_access_and_hardcoded_paths(self):
        self.write('.venv-office/ignored.py', 'os.getenv("DEPENDENCY_ONLY")')
        self.write('app.py', 'import os\nos.getenv(variable_name())\np = r"C:\\Users\\OldUser\\data"')
        report = MODULE.inventory(self.root)
        self.assertNotIn('DEPENDENCY_ONLY', self.names(report))
        self.assertEqual(len(report['unresolved']), 1)
        self.assertEqual(len(report['hardcodedPathReferences']), 1)
        self.assertNotIn('OldUser', json.dumps(report))


if __name__ == '__main__':
    unittest.main()
