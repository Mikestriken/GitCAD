from ..FCStdFileTool import *
import unittest
import shutil
import os
import json
import tempfile
from unittest.mock import patch
from freecad import project_utility as PU

FILE_NAME:str = "FCStdFileTool.py"

TEST_DIR:str = os.path.abspath(os.path.dirname(__file__))
TEMP_DIR:str = os.path.abspath(os.path.join(TEST_DIR, '/temp/'))

class Config:
    def __init__(self, config_dir:str):
        # Path
        self.config_path:str = os.path.relpath(os.path.join(config_dir, 'config.json'))
        
        self.enable_locking:bool = True
        self.enable_thumbnail:bool = True

        # Uncompressed directory structure
        self.dir_suffix:str = "_FCStd"
        self.dir_prefix:str = "FCStd_"
        self.subdir_enabled:bool = True
        self.subdir_name:str = "uncompressed"
        
        # Compressing
        self.enable_compressing:bool = True
        self.files_to_compress:list = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.max_size_gb:float = 2.0
        self.compression_level:int = 9
        self.zip_prefix:str = "compressed_binaries_"
        
    @property
    def json_config(self) -> dict:
        return {
            "require-lock-to-modify-FreeCAD-files": self.enable_locking,
            "include-thumbnails": self.enable_thumbnail,
            "uncompressed-directory-structure": {
                "uncompressed-directory-suffix": self.dir_suffix,
                "uncompressed-directory-prefix": self.dir_prefix,
                "subdirectory": {
                    "put-uncompressed-directory-in-subdirectory": self.subdir_enabled,
                    "subdirectory-name": self.subdir_name
                }
            },
            "compress-non-human-readable-FreeCAD-files": {
                "enabled": self.enable_compressing,
                "files-to-compress": self.files_to_compress,
                "max-compressed-file-size-gigabyte": self.max_size_gb,
                "compression-level": self.compression_level,
                "zip-file-prefix": self.zip_prefix
            }
        }

    def createTestConfig(self, config_data:dict = None) -> dict:
        if config_data is None:
            config_data:dict = self.json_config
        
        with open(self.config_path, 'w') as f:
            json.dump(config_data, f)
        return load_config_file(self.config_path)

class TestFCStdFileTool(unittest.TestCase):
    def setUp(self):
        # Create temp dir
        os.makedirs(TEMP_DIR, exist_ok=True)
        self.temp_dir:str = tempfile.mkdtemp(dir=TEMP_DIR)
        
        # Create config file
        self.config_file:Config = Config(self.temp_dir)
        
        # Copy CAD files to temp dir
        self.temp_BIMExample_path:str = os.path.relpath(os.path.join(self.temp_dir, 'BIMExample.FCStd'))
        self.temp_AssemblyExample_path:str = os.path.relpath(os.path.join(self.temp_dir, 'AssemblyExample.FCStd'))
        shutil.copy(os.path.join(TEST_DIR, 'BIMExample.FCStd'), self.temp_dir)
        shutil.copy(os.path.join(TEST_DIR, 'AssemblyExample.FCStd'), self.temp_dir)

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def test_get_FCStd_dir_path(self):
        # Test with subdir enabled
        self.config_file.dir_suffix = " f u n n y"
        self.config_file.dir_prefix = "no cap "
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "frfr"

        FCStdFileTool_Config:dict = self.config_file.createTestConfig()

        path:str = get_FCStd_dir_path('/path/to/file.FCStd', FCStdFileTool_Config)
        expected:str = os.path.relpath(os.path.join('/path/to/', self.config_file.subdir_name, f"{self.config_file.dir_prefix}file{self.config_file.dir_suffix}"))
        self.assertEqual(path, expected, msg=f"ERR: Expected path '{expected}', got '{path}'")

        # Test without subdir
        self.config_file.subdir_enabled = False
        FCStdFileTool_Config:dict = self.config_file.createTestConfig()
        
        path:str = get_FCStd_dir_path('/path/to/file.FCStd', FCStdFileTool_Config)
        expected:str = os.path.relpath(os.path.join('/path/to', f"{self.config_file.dir_prefix}file{self.config_file.dir_suffix}"))
        self.assertEqual(path, expected, msg=f"ERR: Expected path '{expected}', got '{path}'")

    def test_no_config_export(self):
        with patch('sys.argv', [FILE_NAME, '--export', self.temp_AssemblyExample_path, os.path.join(self.temp_dir, 'output_dir')]):
            main()
        
        docXML_path:str = os.path.join(self.temp_dir, 'output_dir', 'Document.xml')
        thumbnail_path:str = os.path.join(self.temp_dir, 'output_dir', 'thumbnails', 'Thumbnail.png')
        
        self.assertTrue(os.path.exists(docXML_path), msg=f"ERR: '{docXML_path}' does not exist.")
        self.assertTrue(os.path.exists(thumbnail_path), msg=f"ERR: '{thumbnail_path}' does not exist.")

    def test_config_export(self):
        # Create config file
        config_data:dict = self.config_file.createTestConfig()
        
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # Get expected output dir
        expected_dir:str = get_FCStd_dir_path(self.temp_AssemblyExample_path, config_data)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')

        self.assertTrue(os.path.exists(docXML_path), msg=f"ERR: '{docXML_path}' does not exist.")

        # Check for compressed binaries zip
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        self.assertTrue(len(zip_files) > 0, msg=f"ERR: Num zip files '{len(zip_files)}' is <= 0")

        # Check for lockfile
        self.assertTrue(os.path.exists(lockfile_path), msg=f"ERR: '{lockfile_path}' does not exist.")

    def test_no_config_export_import(self):
        # First, export to create a directory
        with patch('sys.argv', [FILE_NAME, '--export', self.temp_AssemblyExample_path, os.path.join(self.temp_dir, 'temp_export_dir')]):
            main()

        # Now import back
        output_file:str = os.path.join(self.temp_dir, 'output.FCStd')
        with patch('sys.argv', [FILE_NAME, '--import', os.path.join(self.temp_dir, 'temp_export_dir'), output_file]):
            main()

        self.assertTrue(os.path.exists(output_file), msg=f"ERR: '{output_file}' does not exist.")

    def test_config_export_import__explicit_defaults(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = True

        # Uncompressed directory structure
        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        # Compressing
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        config_data:dict = self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # First, export with config to create directory
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # Check correct export
        expected_dir:str = get_FCStd_dir_path(self.temp_AssemblyExample_path, config_data)
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        no_extension_dir:str = os.path.join(expected_dir, NO_EXTENSION_SUBDIR_NAME)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        brp_files:list = [f for f in os.listdir(expected_dir) if f.endswith('.brp')]
        
        # Check Dirs
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(no_extension_dir), f"ERR: '{no_extension_dir}' does not exist.")
        self.assertTrue(os.path.exists(os.path.basename(thumbnail_path)), f"ERR: '{os.path.basename(thumbnail_path)}' does not exist.")
        
        # Check files
        self.assertFalse(len(os.listdir(no_extension_dir)) > 0, f"ERR: '{no_extension_dir}' is not empty (files should be compressed).")
        self.assertFalse(os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' exists (thumbnail should be compressed).")
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        self.assertFalse(len(brp_files) > 0, f"ERR: Num brp files '{len(brp_files)}' is > 0 (files should be compressed).")
        self.assertTrue(len(zip_files) > 0, f"ERR: Num zip files '{len(zip_files)}' is <= 0.")
        for zip_file in zip_files:
            zip_file_size_gb:float = os.path.getsize(os.path.join(expected_dir, zip_file))/(1024 ** 3)
            self.assertLessEqual(zip_file_size_gb, self.config_file.max_size_gb, f"ERR: Zip file '{zip_file} size'={zip_file_size_gb} GB is greater than 'max allowed'={self.config_file.max_size_gb} GB.")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        
        # Now import with config
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # Check correct Import
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{os.path.exists(self.temp_AssemblyExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")

    def test_config_export_import__no_lock_thumb(self):
        # SET CONFIGS:
        self.config_file.enable_locking = False
        self.config_file.enable_thumbnail = False

        # Uncompressed directory structure
        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        # Compressing
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        config_data:dict = self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # First, export with config to create directory
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # Check correct export
        expected_dir:str = get_FCStd_dir_path(self.temp_AssemblyExample_path, config_data)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        self.assertTrue(len(zip_files) > 0, f"ERR: Num zip files '{len(zip_files)}' is <= 0")
        
        self.assertFalse(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' should NOT exist.")
        self.assertFalse(os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' should NOT exist.")
        
        # Now import with config
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # Check correct Import
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{os.path.exists(self.temp_AssemblyExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")

    def test_config_export_import__no_compress(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = True

        # Uncompressed directory structure
        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        # Compressing
        self.config_file.enable_compressing = False
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        config_data:dict = self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # First, export with config to create directory
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # Check correct export
        expected_dir:str = get_FCStd_dir_path(self.temp_AssemblyExample_path, config_data)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        # No zip check since compressing disabled
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        
        # Now import with config
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # Check correct Import
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{os.path.exists(self.temp_AssemblyExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")

    def test_config_export_import__no_subdir(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = True

        # Uncompressed directory structure
        self.config_file.dir_suffix = "_test"
        self.config_file.dir_prefix = "test_"
        self.config_file.subdir_enabled = False
        self.config_file.subdir_name = "uncompressed"
        
        # Compressing
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        config_data:dict = self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # First, export with config to create directory
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # Check correct export
        expected_dir:str = get_FCStd_dir_path(self.temp_AssemblyExample_path, config_data)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        self.assertTrue(len(zip_files) > 0, f"ERR: Num zip files '{len(zip_files)}' is <= 0")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        
        # Now import with config
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # Check correct Import
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{os.path.exists(self.temp_AssemblyExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")

    def test_config_export_import__new_name(self):
        # Create config
        config_data:dict = self.config_file.createTestConfig()
        
        CAD_file_path:str = os.path.join(self.temp_dir, "output_config.FCStd")
        
        shutil.move(self.temp_AssemblyExample_path, CAD_file_path)

        # First, export with config to create directory
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', CAD_file_path]):
            main()

        # Check correct export
        expected_dir:str = get_FCStd_dir_path(CAD_file_path, config_data)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(docXML_path), msg=f"ERR: '{docXML_path}' does not exist.")

        # Now import with config
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', CAD_file_path]):
            main()

        self.assertTrue(os.path.exists(CAD_file_path), msg=f"ERR: '{CAD_file_path}' does not exist.") # Low-key useless test, just checks for thrown errors in main code

    @patch('sys.argv', [FILE_NAME, '--help'])
    def test_help_flag(self):
        # Should not raise exception
        main()

    @patch('sys.argv', [FILE_NAME, '--SILENT', '--export', 'dummy.FCStd', 'dummy_dir'])
    def test_silent_flag(self):
        with self.assertRaises(FileNotFoundError, msg=f"ERR: Expected FileNotFoundError to be raised."):
            main()

    @patch('sys.argv', [FILE_NAME])  # No flags
    def test_invalid_args(self):
        # Should not raise exception, prints help
        main()

if __name__ == "__main__":
    unittest.main()