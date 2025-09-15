from ..FCStdFileTool import *
import unittest
import tempfile
import shutil
import os
import json
import zipfile
import io
from unittest.mock import patch, MagicMock
from freecad import project_utility as PU

class TestFCStdFileTool(unittest.TestCase):
    def setUp(self):
        self.temp_dir:str = tempfile.mkdtemp()
        self.config_path:str = os.path.join(self.temp_dir, 'config.json')
        config_data:dict = {
            "freecad-python-instance-path": "dummy",
            "require-lock-to-modify-FreeCAD-files": True,
            "include-thumbnails": True,
            "uncompressed-directory-structure": {
                "uncompressed-directory-suffix": "_FCStd",
                "uncompressed-directory-prefix": "FCStd_",
                "subdirectory": {
                    "put-uncompressed-directory-in-subdirectory": True,
                    "subdirectory-name": "uncompressed"
                }
            },
            "compress-non-human-readable-FreeCAD-files": {
                "enabled": True,
                "files-to-compress": ["**/no_extension/*", "*.brp"],
                "max-compressed-file-size-gigabyte": 2,
                "compression-level": 9,
                "zip-file-prefix": "compressed_binaries_"
            }
        }
        with open(self.config_path, 'w') as f:
            json.dump(config_data, f)
        self.config:dict = load_config_file(self.config_path)

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def test_load_config_file(self):
        config:dict = load_config_file(self.config_path)
        self.assertIn('require_lock', config)
        self.assertTrue(config['require_lock'])
        self.assertIn('include_thumbnails', config)
        self.assertTrue(config['include_thumbnails'])
        self.assertIn('uncompressed_directory_structure', config)
        self.assertIn('compress_binaries', config)

    @patch('sys.argv', ['script', '--export', 'input.FCStd', 'output_dir'])
    def test_parse_args_export(self):
        args:argparse.Namespace = parseArgs()
        self.assertEqual(args.export_flag, ['input.FCStd', 'output_dir'])
        self.assertIsNone(args.import_flag)
        self.assertIsNone(args.config_file_path)
        self.assertFalse(args.silent_flag)
        self.assertFalse(args.help_flag)

    @patch('sys.argv', ['script', '--import', 'input_dir', 'output.FCStd'])
    def test_parse_args_import(self):
        args:argparse.Namespace = parseArgs()
        self.assertEqual(args.import_flag, ['input_dir', 'output.FCStd'])
        self.assertIsNone(args.export_flag)

    @patch('sys.argv', ['script', '--CONFIG-FILE', 'config.json', '--export', 'file.FCStd'])
    def test_parse_args_config_export(self):
        args:argparse.Namespace = parseArgs()
        self.assertEqual(args.config_file_path, 'config.json')
        self.assertEqual(args.export_flag, ['file.FCStd'])

    @patch('sys.argv', ['script', '--SILENT', '--help'])
    def test_parse_args_silent_help(self):
        args:argparse.Namespace = parseArgs()
        self.assertTrue(args.silent_flag)
        self.assertTrue(args.help_flag)

    def test_get_FCStd_dir_path_with_subdir(self):
        config:dict = self.config
        path:str = get_FCStd_dir_path('/path/to/file.FCStd', config)
        expected:str = os.path.relpath(os.path.join('/path/to', 'uncompressed', 'FCStd_file_FCStd'))
        self.assertEqual(path, expected)

    def test_get_FCStd_dir_path_without_subdir(self):
        config:dict = self.config.copy()
        config['uncompressed_directory_structure']['subdirectory']['put_uncompressed_directory_in_subdirectory'] = False
        path:str = get_FCStd_dir_path('/path/to/file.FCStd', config)
        expected:str = os.path.relpath(os.path.join('/path/to', 'FCStd_file_FCStd'))
        self.assertEqual(path, expected)

    def test_remove_exported_thumbnail(self):
        fcstd_dir:str = os.path.join(self.temp_dir, 'fcstd_dir')
        os.makedirs(fcstd_dir)
        thumbnails_dir:str = os.path.join(fcstd_dir, 'thumbnails')
        os.makedirs(thumbnails_dir)
        with open(os.path.join(thumbnails_dir, 'thumb.png'), 'w') as f:
            f.write('dummy')
        remove_exported_thumbnail(fcstd_dir)
        self.assertFalse(os.path.exists(thumbnails_dir))

    def test_add_thumbnail_to_FCStd_file(self):
        fcstd_dir:str = os.path.join(self.temp_dir, 'fcstd_dir')
        os.makedirs(fcstd_dir)
        thumbnails_dir:str = os.path.join(fcstd_dir, 'thumbnails')
        os.makedirs(thumbnails_dir)
        thumb_path:str = os.path.join(thumbnails_dir, 'Thumbnail.png')
        with open(thumb_path, 'w') as f:
            f.write('dummy thumb')
        fcstd_file:str = os.path.join(self.temp_dir, 'test.FCStd')
        with zipfile.ZipFile(fcstd_file, 'w') as zf:
            zf.writestr('Document.xml', 'dummy')
        add_thumbnail_to_FCStd_file(fcstd_dir, fcstd_file)
        with zipfile.ZipFile(fcstd_file, 'r') as zf:
            self.assertIn('thumbnails/Thumbnail.png', zf.namelist())

    def test_compress_binaries(self):
        fcstd_dir:str = os.path.join(self.temp_dir, 'fcstd_dir')
        os.makedirs(fcstd_dir)
        # Create a file to compress
        brp_file:str = os.path.join(fcstd_dir, 'test.brp')
        with open(brp_file, 'w') as f:
            f.write('binary data')
        compress_binaries(fcstd_dir, self.config)
        self.assertFalse(os.path.exists(brp_file))
        zip_files:list = [f for f in os.listdir(fcstd_dir) if f.startswith('compressed_binaries_') and f.endswith('.zip')]
        self.assertTrue(len(zip_files) > 0)

    def test_write_zip_to_disk(self):
        zip_buffer:io.BytesIO = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, 'w') as zf:
            zf.writestr('test.txt', 'content')
        zip_buffer.seek(0)
        index:int = write_zip_to_disk(self.temp_dir, 'test_', 1, zip_buffer)
        self.assertEqual(index, 2)
        zip_path:str = os.path.join(self.temp_dir, 'test_1.zip')
        self.assertTrue(os.path.exists(zip_path))

    def test_repackFCStd(self):
        fcstd_file:str = os.path.join(self.temp_dir, 'test.FCStd')
        with zipfile.ZipFile(fcstd_file, 'w') as zf:
            zf.writestr('file1', 'content1')
            zf.writestr('file2', 'content2')
        repackFCStd(fcstd_file)
        # Check if repacked
        with zipfile.ZipFile(fcstd_file, 'r') as zf:
            self.assertEqual(len(zf.namelist()), 2)

    def test_move_files_without_extension_to_subdir(self):
        fcstd_dir:str = os.path.join(self.temp_dir, 'fcstd_dir')
        os.makedirs(fcstd_dir)
        no_ext_file:str = os.path.join(fcstd_dir, 'noext')
        with open(no_ext_file, 'w') as f:
            f.write('no ext')
        ext_file:str = os.path.join(fcstd_dir, 'with.ext')
        with open(ext_file, 'w') as f:
            f.write('with ext')
        move_files_without_extension_to_subdir(fcstd_dir)
        no_ext_subdir:str = os.path.join(fcstd_dir, NO_EXTENSION_SUBDIR_NAME)
        self.assertTrue(os.path.exists(os.path.join(no_ext_subdir, 'noext')))
        self.assertTrue(os.path.exists(ext_file))
        self.assertFalse(os.path.exists(no_ext_file))

    def test_ImportingContext_no_config(self):
        fcstd_dir:str = os.path.join(self.temp_dir, 'fcstd_dir')
        os.makedirs(fcstd_dir)
        with ImportingContext(fcstd_dir, None) as ctx:
            self.assertIsNone(ctx)

    def test_ImportingContext_with_config(self):
        fcstd_dir:str = os.path.join(self.temp_dir, 'fcstd_dir')
        os.makedirs(fcstd_dir)
        # Create zip to extract
        zip_path:str = os.path.join(fcstd_dir, 'compressed_binaries_1.zip')
        with zipfile.ZipFile(zip_path, 'w') as zf:
            zf.writestr('extracted.txt', 'content')
        # Create no ext subdir
        no_ext_dir:str = os.path.join(fcstd_dir, NO_EXTENSION_SUBDIR_NAME)
        os.makedirs(no_ext_dir)
        moved_file:str = os.path.join(no_ext_dir, 'moved')
        with open(moved_file, 'w') as f:
            f.write('moved')
        with ImportingContext(fcstd_dir, self.config) as ctx:
            self.assertTrue(os.path.exists(os.path.join(fcstd_dir, 'extracted.txt')))
            self.assertTrue(os.path.exists(os.path.join(fcstd_dir, 'moved')))
        # After exit
        self.assertFalse(os.path.exists(os.path.join(fcstd_dir, 'extracted.txt')))
        self.assertTrue(os.path.exists(moved_file))

    def test_bad_args_no_mode(self):
        args:MagicMock = MagicMock()
        args.export_flag = None
        args.import_flag = None
        self.assertTrue(bad_args(args))

    def test_bad_args_too_many_args(self):
        args:MagicMock = MagicMock()
        args.export_flag = ['a', 'b', 'c']
        args.import_flag = None
        args.config_file_path = None
        self.assertTrue(bad_args(args))

    def test_bad_args_missing_output_no_config(self):
        args:MagicMock = MagicMock()
        args.export_flag = ['input']
        args.import_flag = None
        args.config_file_path = None
        self.assertTrue(bad_args(args))

    def test_bad_args_valid(self):
        args:MagicMock = MagicMock()
        args.export_flag = ['input', 'output']
        args.import_flag = None
        args.config_file_path = 'config'
        self.assertFalse(bad_args(args))

    def test_ensure_lockfile_exists(self):
        fcstd_dir:str = os.path.join(self.temp_dir, 'fcstd_dir')
        os.makedirs(fcstd_dir)
        ensure_lockfile_exists(fcstd_dir)
        lock_file:str = os.path.join(fcstd_dir, '.lockfile')
        self.assertTrue(os.path.exists(lock_file))

    @patch('sys.argv')
    @patch('builtins.print')
    def test_main_help(self, mock_print, mock_argv):
        mock_argv[:] = ['script', '--help']
        main()
        mock_print.assert_called_once_with(HELP_MESSAGE)

    @patch('sys.argv')
    @patch('builtins.print')
    def test_main_bad_args(self, mock_print, mock_argv):
        mock_argv[:] = ['script']
        main()
        mock_print.assert_called_once_with(HELP_MESSAGE)

if __name__ == "__main__":
    unittest.main()