from ..FCStdFileTool import *
import unittest
import shutil
import os
import json
import zipfile
import io
from unittest.mock import patch, MagicMock
from freecad import project_utility as PU

FILE_NAME:str = "FCStdFileTool.py"

class Config:
    def __init__(self, config_dir:str):
        # Path
        self.config_path = os.path.join(config_dir, 'config.json')
        
        self.enable_locking = True
        self.enable_thumbnail = True

        # Uncompressed directory structure
        self.dir_suffix = "_FCStd"
        self.dir_prefix = "FCStd_"
        self.subdir_enabled = True
        self.subdir_name = "uncompressed"
        
        # Compressing
        self.enable_compressing = True
        self.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.max_size_gb = 2.0
        self.compression_level = 9
        self.zip_prefix = "compressed_binaries_"
        
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
        self.test_dir:str = os.path.dirname(__file__)
        
        # Create temp dir
        self.temp_dir:str = os.path.join(os.path.dirname(__file__), '/temp/')
        os.makedirs(self.temp_dir, exist_ok=True)
        
        # Create config file
        self.config_file:Config = Config(self.temp_dir)
        
        # Copy CAD files
        shutil.copy(os.path.join(self.test_dir, 'BIMExample.FCStd'), self.temp_dir)
        shutil.copy(os.path.join(self.test_dir, 'AssemblyExample.FCStd'), self.temp_dir)

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
        self.assertEqual(path, expected)

        # Test without subdir
        self.config_file.subdir_enabled = False
        FCStdFileTool_Config:dict = self.config_file.createTestConfig()
        
        path:str = get_FCStd_dir_path('/path/to/file.FCStd', FCStdFileTool_Config)
        expected:str = os.path.relpath(os.path.join('/path/to', f"{self.config_file.dir_prefix}file{self.config_file.dir_suffix}"))
        self.assertEqual(path, expected)

    @patch('sys.argv', [FILE_NAME, '--export', 'input.FCStd', 'output_dir'])
    def test_parse_args_export(self):
        args:argparse.Namespace = parseArgs()
        self.assertEqual(args.export_flag, ['input.FCStd', 'output_dir'])
        self.assertIsNone(args.import_flag)
        self.assertIsNone(args.config_file_path)
        self.assertFalse(args.silent_flag)
        self.assertFalse(args.help_flag)

if __name__ == "__main__":
    unittest.main()