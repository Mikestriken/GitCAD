from ..FCStdFileTool import *
import unittest
import shutil
import os
import json
import tempfile
from unittest.mock import patch
from io import StringIO
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

        # Test with no file
        with self.assertRaises(FileNotFoundError, msg=f"ERR: Expected FileNotFoundError to be raised"):
            get_FCStd_dir_path('/path/to/file.FCStd', FCStdFileTool_Config)
            
        # Test with subdir
        path:str = get_FCStd_dir_path(self.temp_AssemblyExample_path, FCStdFileTool_Config)
        expected:str = os.path.relpath(os.path.join(self.temp_dir, self.config_file.subdir_name, f"{self.config_file.dir_prefix}AssemblyExample{self.config_file.dir_suffix}"))
        self.assertEqual(path, expected, msg=f"ERR: Expected path '{expected}', got '{path}'")

        # Test without subdir
        self.config_file.subdir_enabled = False
        FCStdFileTool_Config:dict = self.config_file.createTestConfig()
        
        path:str = get_FCStd_dir_path(self.temp_AssemblyExample_path, FCStdFileTool_Config)
        expected:str = os.path.relpath(os.path.join(self.temp_dir, f"{self.config_file.dir_prefix}AssemblyExample{self.config_file.dir_suffix}"))
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

        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # EXPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # CHECK EXPORT
        FCStd_dir_name:str = os.path.splitext(os.path.basename(self.temp_AssemblyExample_path))[0]
        expected_dir:str = os.path.join(self.temp_dir, "uncompressed", f"FCStd_{FCStd_dir_name}_FCStd")
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        no_extension_dir:str = os.path.join(expected_dir, NO_EXTENSION_SUBDIR_NAME)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        brp_files:list = [f for f in os.listdir(expected_dir) if f.endswith('.brp')]
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(no_extension_dir), f"ERR: '{no_extension_dir}' does not exist.")
        self.assertTrue(os.path.exists(os.path.dirname(thumbnail_path)), f"ERR: '{os.path.dirname(thumbnail_path)}' does not exist.")
        
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        self.assertTrue(len(os.listdir(no_extension_dir)) == 0, f"ERR: '{no_extension_dir}' is not empty (files should be compressed).")
        self.assertTrue(not os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' exists (thumbnail should be compressed).")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        self.assertTrue(len(brp_files) == 0, f"ERR: Num brp files '{len(brp_files)}' is != 0 (files should be compressed).")
        self.assertTrue(len(zip_files) > 0, f"ERR: Num zip files '{len(zip_files)}' is <= 0.")
        
        for zip_file in zip_files:
            zip_file_size_gb:float = os.path.getsize(os.path.join(expected_dir, zip_file))/(1024 ** 3)
            self.assertLessEqual(zip_file_size_gb, self.config_file.max_size_gb, f"ERR: Zip file '{zip_file} size'={zip_file_size_gb} GB is greater than 'max allowed'={self.config_file.max_size_gb} GB.")
        
        # IMPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # CHECK IMPORT
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{os.path.exists(self.temp_AssemblyExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")
        
        with zipfile.ZipFile(self.temp_AssemblyExample_path, 'r') as zf:
            self.assertTrue(not any('./' in file_name for file_name in zf.namelist()), f"ERR: Phantom './' files found in created .FCStd file.")

    def test_config_export_import__different_file(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = True

        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_BIMExample_path)
        
        # EXPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_BIMExample_path]):
            main()

        # CHECK EXPORT
        FCStd_dir_name:str = os.path.splitext(os.path.basename(self.temp_BIMExample_path))[0]
        expected_dir:str = os.path.join(self.temp_dir, "uncompressed", f"FCStd_{FCStd_dir_name}_FCStd")
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        no_extension_dir:str = os.path.join(expected_dir, NO_EXTENSION_SUBDIR_NAME)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        brp_files:list = [f for f in os.listdir(expected_dir) if f.endswith('.brp')]
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(no_extension_dir), f"ERR: '{no_extension_dir}' does not exist.")
        self.assertTrue(os.path.exists(os.path.dirname(thumbnail_path)), f"ERR: '{os.path.dirname(thumbnail_path)}' does not exist.")
        
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        self.assertTrue(len(os.listdir(no_extension_dir)) == 0, f"ERR: '{no_extension_dir}' is not empty (files should be compressed).")
        self.assertTrue(not os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' exists (thumbnail should be compressed).")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        self.assertTrue(len(brp_files) == 0, f"ERR: Num brp files '{len(brp_files)}' is != 0 (files should be compressed).")
        self.assertTrue(len(zip_files) > 0, f"ERR: Num zip files '{len(zip_files)}' is <= 0.")
        
        for zip_file in zip_files:
            zip_file_size_gb:float = os.path.getsize(os.path.join(expected_dir, zip_file))/(1024 ** 3)
            self.assertLessEqual(zip_file_size_gb, self.config_file.max_size_gb, f"ERR: Zip file '{zip_file} size'={zip_file_size_gb} GB is greater than 'max allowed'={self.config_file.max_size_gb} GB.")
        
        # IMPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_BIMExample_path]):
            main()

        # CHECK IMPORT
        new_size:int = os.path.getsize(self.temp_BIMExample_path)
        
        self.assertTrue(os.path.exists(self.temp_BIMExample_path), f"ERR: '{os.path.exists(self.temp_BIMExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")
        
        with zipfile.ZipFile(self.temp_BIMExample_path, 'r') as zf:
            self.assertTrue(not any('./' in file_name for file_name in zf.namelist()), f"ERR: Phantom './' files found in created .FCStd file.")
        
    def test_config_export_import__no_locking_no_thumbnail(self):
        # SET CONFIGS:
        self.config_file.enable_locking = False
        self.config_file.enable_thumbnail = False

        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # EXPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # CHECK EXPORT
        FCStd_dir_name:str = os.path.splitext(os.path.basename(self.temp_AssemblyExample_path))[0]
        expected_dir:str = os.path.join(self.temp_dir, "uncompressed", f"FCStd_{FCStd_dir_name}_FCStd")
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        no_extension_dir:str = os.path.join(expected_dir, NO_EXTENSION_SUBDIR_NAME)
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        brp_files:list = [f for f in os.listdir(expected_dir) if f.endswith('.brp')]
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(no_extension_dir), f"ERR: '{no_extension_dir}' does not exist.")
        
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        self.assertTrue(len(os.listdir(no_extension_dir)) == 0, f"ERR: '{no_extension_dir}' is not empty (files should be compressed).")
        self.assertTrue(not os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' should NOT exist.")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' should exist.")
        self.assertTrue(len(brp_files) == 0, f"ERR: Num brp files '{len(brp_files)}' is != 0 (files should be compressed).")
        self.assertTrue(len(zip_files) > 0, f"ERR: Num zip files '{len(zip_files)}' is <= 0")
        
        for zip_file in zip_files:
            zip_file_size_gb:float = os.path.getsize(os.path.join(expected_dir, zip_file))/(1024 ** 3)
            self.assertLessEqual(zip_file_size_gb, self.config_file.max_size_gb, f"ERR: Zip file '{zip_file} size'={zip_file_size_gb} GB is greater than 'max allowed'={self.config_file.max_size_gb} GB.")
        
        # IMPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # CHECK IMPORT
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{os.path.exists(self.temp_AssemblyExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")
        
        with zipfile.ZipFile(self.temp_AssemblyExample_path, 'r') as zf:
            self.assertTrue(not any('./' in file_name for file_name in zf.namelist()), f"ERR: Phantom './' files found in created .FCStd file.")

    def test_config_export_import__no_compress(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = True

        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = False
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # EXPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # CHECK EXPORT
        FCStd_dir_name:str = os.path.splitext(os.path.basename(self.temp_AssemblyExample_path))[0]
        expected_dir:str = os.path.join(self.temp_dir, "uncompressed", f"FCStd_{FCStd_dir_name}_FCStd")
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        no_extension_dir:str = os.path.join(expected_dir, NO_EXTENSION_SUBDIR_NAME)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        brp_files:list = [f for f in os.listdir(expected_dir) if f.endswith('.brp')]
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(no_extension_dir), f"ERR: '{no_extension_dir}' does not exist.")
        
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        self.assertTrue(len(os.listdir(no_extension_dir)) > 0, f"ERR: '{no_extension_dir}' is empty (files should not be compressed).")
        self.assertTrue(os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' does not exist (compressing is disabled).")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        self.assertTrue(len(brp_files) > 0, f"ERR: Num brp files '{len(brp_files)}' is <= 0 (files should not be compressed).")
        self.assertTrue(len(zip_files) == 0, f"ERR: Num zip files '{len(zip_files)}' is != 0 (compressing is disabled).")
        
        # IMPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # CHECK EXPORT
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{os.path.exists(self.temp_AssemblyExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")
        
        with zipfile.ZipFile(self.temp_AssemblyExample_path, 'r') as zf:
            self.assertTrue(not any('./' in file_name for file_name in zf.namelist()), f"ERR: Phantom './' files found in created .FCStd file.")

    def test_config_export_import__no_subdir(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = True

        self.config_file.dir_suffix = "_test"
        self.config_file.dir_prefix = "test_"
        self.config_file.subdir_enabled = False
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # EXPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # CHECK EXPORT
        FCStd_dir_name:str = os.path.splitext(os.path.basename(self.temp_AssemblyExample_path))[0]
        expected_dir:str = os.path.join(self.temp_dir, f"test_{FCStd_dir_name}_test")
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        no_extension_dir:str = os.path.join(expected_dir, NO_EXTENSION_SUBDIR_NAME)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        brp_files:list = [f for f in os.listdir(expected_dir) if f.endswith('.brp')]
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}', does not exist.")
        self.assertTrue(os.path.exists(no_extension_dir), f"ERR: '{no_extension_dir}' does not exist.")
        self.assertTrue(os.path.exists(os.path.dirname(thumbnail_path)), f"ERR: '{os.path.dirname(thumbnail_path)}' does not exist.")
        
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}', does not exist.")
        self.assertTrue(len(os.listdir(no_extension_dir)) == 0, f"ERR: '{no_extension_dir}' is not empty (files should be compressed).")
        self.assertTrue(not os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' exists (thumbnail should be compressed).")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        self.assertTrue(len(brp_files) == 0, f"ERR: Num brp files '{len(brp_files)}' is != 0 (files should be compressed).")
        self.assertTrue(len(zip_files) > 0, f"ERR: Num zip files '{len(zip_files)}' is <= 0")
        
        for zip_file in zip_files:
            zip_file_size_gb:float = os.path.getsize(os.path.join(expected_dir, zip_file))/(1024 ** 3)
            self.assertLessEqual(zip_file_size_gb, self.config_file.max_size_gb, f"ERR: Zip file '{zip_file} size'={zip_file_size_gb} GB is greater than 'max allowed'={self.config_file.max_size_gb} GB.")
        
        # IMPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # CHECK IMPORT
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{os.path.exists(self.temp_AssemblyExample_path)}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")
        
        with zipfile.ZipFile(self.temp_AssemblyExample_path, 'r') as zf:
            self.assertTrue(not any('./' in file_name for file_name in zf.namelist()), f"ERR: Phantom './' files found in created .FCStd file.")

    def test_config_export_import__too_small_max_size_gb(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = True

        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 0.0001
        self.config_file.compression_level = 0
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()
        
        # EXPORT
        with self.assertRaises(ValueError, msg=f"ERR: Expected ValueError to be raised for setting compression level and max_size_gb to too small values."):
            with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
                main()

    def test_config_export_import__multi_zip_small_max_size_gb(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = True

        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = True
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 0.0005
        self.config_file.compression_level = 0
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # EXPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # CHECK EXPORT
        FCStd_dir_name:str = os.path.splitext(os.path.basename(self.temp_AssemblyExample_path))[0]
        expected_dir:str = os.path.join(self.temp_dir, "uncompressed", f"FCStd_{FCStd_dir_name}_FCStd")
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        no_extension_dir:str = os.path.join(expected_dir, NO_EXTENSION_SUBDIR_NAME)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        brp_files:list = [f for f in os.listdir(expected_dir) if f.endswith('.brp')]
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}' does not exist.")
        self.assertTrue(os.path.exists(no_extension_dir), f"ERR: '{no_extension_dir}' does not exist.")
        self.assertTrue(os.path.exists(os.path.dirname(thumbnail_path)), f"ERR: '{os.path.dirname(thumbnail_path)}' does not exist.")
        
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}' does not exist.")
        self.assertTrue(len(os.listdir(no_extension_dir)) == 0, f"ERR: '{no_extension_dir}' is not empty (files should be compressed).")
        self.assertTrue(not os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' exists (thumbnail should be compressed).")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        self.assertTrue(len(brp_files) == 0, f"ERR: Num brp files '{len(brp_files)}' is != 0 (files should be compressed).")
        self.assertTrue(len(zip_files) > 1, f"ERR: Num zip files '{len(zip_files)}' is <= 1. Small max size set, expected more than 1 zip.")
        
        for zip_file in zip_files:
            zip_file_size_gb:float = os.path.getsize(os.path.join(expected_dir, zip_file))/(1024 ** 3)
            self.assertLessEqual(zip_file_size_gb, self.config_file.max_size_gb, f"ERR: Zip file '{zip_file}' size={zip_file_size_gb} GB is greater than 'max allowed'={self.config_file.max_size_gb} GB.")
        
        # IMPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # CHECK IMPORT
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{self.temp_AssemblyExample_path}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")
        
        with zipfile.ZipFile(self.temp_AssemblyExample_path, 'r') as zf:
            self.assertTrue(not any('./' in file_name for file_name in zf.namelist()), f"ERR: Phantom './' files found in created .FCStd file.")

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

    def test_config_export_import__no_compress_no_thumbnail(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = False

        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = False
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()
        original_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        # EXPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--export', self.temp_AssemblyExample_path]):
            main()

        # CHECK EXPORT
        FCStd_dir_name:str = os.path.splitext(os.path.basename(self.temp_AssemblyExample_path))[0]
        expected_dir:str = os.path.join(self.temp_dir, "uncompressed", f"FCStd_{FCStd_dir_name}_FCStd")
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')
        thumbnail_path:str = os.path.join(expected_dir, 'thumbnails', 'Thumbnail.png')
        no_extension_dir:str = os.path.join(expected_dir, NO_EXTENSION_SUBDIR_NAME)
        docXML_path:str = os.path.join(expected_dir, 'Document.xml')
        zip_files:list = [f for f in os.listdir(expected_dir) if f.startswith(self.config_file.zip_prefix) and f.endswith('.zip')]
        brp_files:list = [f for f in os.listdir(expected_dir) if f.endswith('.brp')]
        
        self.assertTrue(os.path.exists(expected_dir), f"ERR: '{expected_dir}' does not exist.")
        self.assertTrue(os.path.exists(no_extension_dir), f"ERR: '{no_extension_dir}' does not exist.")
        
        self.assertTrue(os.path.exists(docXML_path), f"ERR: '{docXML_path}' does not exist.")
        self.assertTrue(len(os.listdir(no_extension_dir)) > 0, f"ERR: '{no_extension_dir}' is empty (files should not be compressed).")
        self.assertTrue(not os.path.exists(thumbnail_path), f"ERR: '{thumbnail_path}' should NOT exist.")
        self.assertTrue(os.path.exists(lockfile_path), f"ERR: '{lockfile_path}' does not exist.")
        self.assertTrue(len(brp_files) > 0, f"ERR: Num brp files '{len(brp_files)}' is <= 0 (files should not be compressed).")
        self.assertTrue(len(zip_files) == 0, f"ERR: Num zip files '{len(zip_files)}' is != 0 (compressing is disabled).")
        
        # IMPORT
        with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--import', self.temp_AssemblyExample_path]):
            main()

        # CHECK IMPORT
        new_size:int = os.path.getsize(self.temp_AssemblyExample_path)
        
        self.assertTrue(os.path.exists(self.temp_AssemblyExample_path), f"ERR: '{self.temp_AssemblyExample_path}' does not exist.")
        self.assertAlmostEqual(new_size, original_size, delta=int(original_size*0.05), msg=f"ERR: Original file size={original_size}, New file size={new_size}, Acceptable Delta={int(original_size*0.05)}")
        
        with zipfile.ZipFile(self.temp_AssemblyExample_path, 'r') as zf:
            self.assertTrue(not any('./' in file_name for file_name in zf.namelist()), f"ERR: Phantom './' files found in created .FCStd file.")

    @patch('sys.argv', [FILE_NAME, '--export', 'dummy.FCStd'])
    def test_export_one_arg_no_config(self):
        # Should print help due to bad args
        main()

    @patch('sys.argv', [FILE_NAME, '--import', 'dummy_dir'])
    def test_import_one_arg_no_config(self):
        # Should print help due to bad args
        main()

    @patch('sys.argv', [FILE_NAME, '--export', 'dummy.FCStd', 'dummy_dir', '--import', 'dummy_dir', 'dummy.FCStd'])
    def test_both_flags(self):
        # Should print help due to bad args
        main()

    def test_lockfile_flag(self):
        # SET CONFIGS:
        self.config_file.enable_locking = True
        self.config_file.enable_thumbnail = False

        self.config_file.dir_suffix = "_FCStd"
        self.config_file.dir_prefix = "FCStd_"
        self.config_file.subdir_enabled = True
        self.config_file.subdir_name = "uncompressed"
        
        self.config_file.enable_compressing = False
        self.config_file.files_to_compress = ["**/no_extension/*", "*.brp", "**/thumbnails/*", "*.Map.*", "*.Table.*"]
        self.config_file.max_size_gb = 2.0
        self.config_file.compression_level = 9
        self.config_file.zip_prefix = "compressed_binaries_"

        self.config_file.createTestConfig()

        with patch('sys.stdout', new_callable=StringIO) as mock_stdout:
            with patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', self.config_file.config_path, '--lockfile', self.temp_AssemblyExample_path]):
                main()

        FCStd_dir_name:str = os.path.splitext(os.path.basename(self.temp_AssemblyExample_path))[0]
        expected_dir:str = os.path.join(self.temp_dir, "uncompressed", f"FCStd_{FCStd_dir_name}_FCStd")
        lockfile_path:str = os.path.join(expected_dir, '.lockfile')

        output:str = mock_stdout.getvalue().strip()
        self.assertEqual(output, lockfile_path, f"ERR: output doesn't match expected lockfile path\noutput={output}, lockfile_path={lockfile_path}")

    @patch('sys.argv', [FILE_NAME, '--lockfile', 'dummy.FCStd'])
    def test_lockfile_without_config(self):
        # Should print help due to bad args
        main()

    @patch('sys.argv', [FILE_NAME, '--CONFIG-FILE', 'dummy.json', '--lockfile', 'dummy.FCStd', '--export', 'dummy.FCStd'])
    def test_lockfile_with_export(self):
        # Should print help due to multiple modes
        main()


if __name__ == "__main__":
    unittest.main()