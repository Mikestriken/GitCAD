EXPORT_FLAG:str = '--export'
IMPORT_FLAG:str = '--import'
CONFIG_FILE_FLAG:str = '--CONFIG-FILE' # Uses config file to determine configurations. Args interpreted differently from what's listed in help()

HELP_MESSAGE:str =f"""
usage: FCStdFileTool.py [{EXPORT_FLAG} INPUT_FCSTD_FILE OUTPUT_FCSTD_DIR] [{IMPORT_FLAG} INPUT_FCSTD_DIR OUTPUT_FCSTD_FILE] [{CONFIG_FILE_FLAG} {EXPORT_FLAG} FCSTD_FILE] [{CONFIG_FILE_FLAG} {IMPORT_FLAG} FCSTD_FILE]

FreeCAD .FCStd file tool. Used to automate the process of importing and exporting .FCStd files.
Importing => Compressing a .FCStd file from an uncompressed directory.
Exporting => Decompressing a .FCStd file to an uncompressed directory.

options:
    -h, --help            
                        show this help message and exit
                        
    {EXPORT_FLAG} INPUT_FCSTD_FILE OUTPUT_FCSTD_DIR
                        export files from .FCStd archive
                        
    {IMPORT_FLAG} INPUT_FCSTD_DIR OUTPUT_FCSTD_FILE
                        Create .FCStd archive from directory
                        
    {CONFIG_FILE_FLAG}
                        Use config file to determine configurations. Args interpreted differently from what's listed:
                            {EXPORT_FLAG} INPUT_FCSTD_FILE, OUTPUT_FCSTD_DIR -> {EXPORT_FLAG} FCSTD_FILE
                            {IMPORT_FLAG} INPUT_FCSTD_DIR, OUTPUT_FCSTD_FILE -> {IMPORT_FLAG} FCSTD_FILE
"""

from freecad import project_utility as PU
import os
import argparse
import json
import zipfile
import shutil
import fnmatch
import io

CONFIG_PATH:str = 'FreeCAD_Automation/git-freecad-config.json'

def load_config_file(config_path:str) -> dict:
    """
    Redefines config file keys for this script.
    This way if the keys for the config file changes, it will not be necessary to update the keys throughout this entire script.
    Instead only the key names in this function need be updated.

    Args:
        config_path (str): Path to config file.


    Returns:
        dict: Config file contents using redefined keys.
    """
    
    data:dict
    with open(config_path, 'r') as f:
        data:dict = json.load(f)

    return {
        "require_lock": data["require-lock-to-modify-FreeCAD-files"],
        "include_thumbnails": data["include-thumbnails"],

        "uncompressed_directory_structure": {
            "uncompressed_directory_suffix": data["uncompressed-directory-structure"]["uncompressed-directory-suffix"],
            "uncompressed_directory_prefix": data["uncompressed-directory-structure"]["uncompressed-directory-prefix"],
            "subdirectory": {
                "put_uncompressed_directory_in_subdirectory": data["uncompressed-directory-structure"]["subdirectory"]["put-uncompressed-directory-in-subdirectory"],
                "subdirectory_name": data["uncompressed-directory-structure"]["subdirectory"]["subdirectory-name"]
            }
        },

        "compress_binaries": {
            "enabled": data["compress-non-human-readable-FreeCAD-files"]["enabled"],
            "binary_file_patterns": data["compress-non-human-readable-FreeCAD-files"]["files-to-compress"],
            "max_compressed_file_size_gigabyte": data["compress-non-human-readable-FreeCAD-files"]["max-compressed-file-size-gigabyte"],
            "compression_level": data["compress-non-human-readable-FreeCAD-files"]["compression-level"],
            "zip_file_prefix": data["compress-non-human-readable-FreeCAD-files"]["zip-file-prefix"]
        }
    }
        
def get_FCStd_dir_path(FCStd_file_path:str, config:dict) -> str:
    """
    Gets path to uncompressed FCStd file directory according to set configurations.

    Args:
        FCStd_file_path (str): Path to .FCStd file.
        config (dict): Configurations dictionary.

    Returns:
        str: Path to uncompressed FCStd file directory.
    """
    # Load relevant configs
    suffix:str = config['uncompressed_directory_structure']['uncompressed_directory_suffix']
    prefix:str = config['uncompressed_directory_structure']['uncompressed_directory_prefix']
    subdir_name:str = config['uncompressed_directory_structure']['subdirectory']['subdirectory_name']
    
    USE_SUBDIR:bool = config['uncompressed_directory_structure']['subdirectory']['put_uncompressed_directory_in_subdirectory']
    
    # Construct output path
    FCStd_file_dir:str = os.path.dirname(FCStd_file_path)
    FCStd_file_name:str = os.path.splitext(os.path.basename(FCStd_file_path))[0] # remove .FCStd extension
    FCStd_constructed_dir_name:str = f"{prefix}{FCStd_file_name}{suffix}"
    
    if USE_SUBDIR: return os.path.relpath(os.path.join(FCStd_file_dir, subdir_name, FCStd_constructed_dir_name))
    
    else: return os.path.relpath(os.path.join(FCStd_file_dir, FCStd_constructed_dir_name))

# * Legacy function. Maybe it'll come in use again in the future
def get_FCStd_file_path(FCStd_dir_path:str, config:dict) -> str:
    """
    Gets path to .FCStd file according to set configurations.

    Args:
        FCStd_dir_path (str): Path to uncompressed FCStd file directory.
        config (dict): Configurations dictionary.

    Returns:
        str: Path to .FCStd file.
    """
    """ 
    # Load relevant configs
    suffix:str = config['uncompressed_directory_structure']['uncompressed_directory_suffix']
    prefix:str = config['uncompressed_directory_structure']['uncompressed_directory_prefix']
    subdir_name:str = config['uncompressed_directory_structure']['subdirectory']['subdirectory_name']
    
    USE_SUBDIR:bool = config['uncompressed_directory_structure']['subdirectory']['put_uncompressed_directory_in_subdirectory']
    
    # Construct output path
    FCStd_dir_name:str = os.path.basename(FCStd_dir_path).removesuffix(suffix).removeprefix(prefix)
    FCStd_constructed_file_name:str = f"{FCStd_dir_name}.FCStd"
    
    if USE_SUBDIR: return os.path.relpath(os.path.join(FCStd_dir_path, "../..", FCStd_constructed_file_name))
    
    else: return os.path.relpath(os.path.join(FCStd_dir_path, "..", FCStd_constructed_file_name))
    """
    return None

def remove_exported_thumbnail(FCStd_dir_path:str):
    """
    Remove thumbnail folder and contents from uncompressed FCStd file directory.

    Args:
        FCStd_dir_path (str): Path to uncompressed FCStd file directory.
    """
    thumbnails_dir:str = os.path.join(FCStd_dir_path, 'thumbnails')
    if os.path.exists(thumbnails_dir):
        shutil.rmtree(thumbnails_dir)

def add_thumbnail_to_FCStd_file(FCStd_dir_path:str, FCStd_file_path:str):
    """
    Add thumbnail to .FCStd file if uncompressed FCStd file directory has one.

    Args:
        FCStd_dir_path (str): Path to uncompressed FCStd file directory.
        FCStd_file_path (str): Path to .FCStd file.
    """
    thumbnail_path:str = os.path.join(FCStd_dir_path, 'thumbnails', 'Thumbnail.png')
    if os.path.exists(thumbnail_path):
        with zipfile.ZipFile(FCStd_file_path, 'a', zipfile.ZIP_DEFLATED) as zf:
            zf.write(thumbnail_path, 'thumbnails/Thumbnail.png')

def compress_binaries(FCStd_dir_path: str, config: dict):
    """
    Compresses binary files and folders in the FCStd directory that match the configured patterns.
    Uses io.BytesIO buffers to manage and size limits. Files are removed after compression

    Args:
        FCStd_dir_path (str): Path to the FCStd directory.
        config (dict): Configuration dictionary.
    """
    assert config['compress_binaries']['enabled'], "ERROR: Attempting to compress binaries despite that config being disabled!"

    patterns:list = config['compress_binaries']['binary_file_patterns']
    max_size_gb:float = config['compress_binaries']['max_compressed_file_size_gigabyte']
    compression_level:int = config['compress_binaries']['compression_level']
    zip_file_prefix:str = config['compress_binaries']['zip_file_prefix']

    max_size_bytes:float = max_size_gb * (1024 ** 3)

    # Collect items to compress
    to_compress:list = []
    for root, dirs, files in os.walk(FCStd_dir_path):
        for name in dirs + files:
            full_path:str = os.path.join(root, name)
            for pattern in patterns:
                # "!." is a custom pattern (file has no extension)
                if fnmatch.fnmatch(name, pattern) or (pattern == "!." and os.path.isfile(full_path) and fnmatch.fnmatch(name, "*") and "." not in name):
                    to_compress.append(full_path)
                    break

    # Compress items into zip files
    zip_index:int = 1
    current_zip:io.BytesIO = io.BytesIO()
    i:int = 0
    while (i < len(to_compress)):
        item:str = to_compress[i]
        # Backup before adding
        backup:io.BytesIO = io.BytesIO(current_zip.getvalue())
        path_to_item_in_zip:str = os.path.relpath(path=item, start=FCStd_dir_path)
        if os.path.isfile(item):
            # Add file
            with zipfile.ZipFile(current_zip, 'a', zipfile.ZIP_DEFLATED, compresslevel=compression_level) as zf:
                zf.write(item, path_to_item_in_zip)
            
            if current_zip.tell() > max_size_bytes:
                # Restore
                current_zip:io.BytesIO = backup
                
                # Write to disk
                zip_index:int = write_zip_to_disk(FCStd_dir_path, zip_file_prefix, zip_index, current_zip)
                
                # New buffer
                current_zip:io.BytesIO = io.BytesIO()
                
                # Retry this file with new archive
                continue
            
            # Remove file
            os.remove(item)
            
        elif os.path.isdir(item):
            # Add Directory
            with zipfile.ZipFile(current_zip, 'a', zipfile.ZIP_DEFLATED, compresslevel=compression_level) as zf:
                for root, _, files in os.walk(item):
                    for file in files:
                        file_path:str = os.path.join(root, file)
                        path_to_item_in_zip:str = os.path.relpath(path=file_path, start=FCStd_dir_path)
                        zf.write(file_path, path_to_item_in_zip)
            
            
            if current_zip.tell() >= max_size_bytes:
                # Restore
                current_zip:io.BytesIO = backup
                
                # Write to disk
                zip_index:int = write_zip_to_disk(FCStd_dir_path, zip_file_prefix, zip_index, current_zip)
                
                # New buffer
                current_zip:io.BytesIO = io.BytesIO()
                
                # Retry this file with new archive
                continue
            
            # Remove Directory
            shutil.rmtree(item)
        
        i += 1
        # End of while loop

    # Write last opened archive (that didn't exceed size) to disk
    if current_zip.tell() > 0:
        zip_index:int = write_zip_to_disk(FCStd_dir_path, zip_file_prefix, zip_index, current_zip)

def write_zip_to_disk(FCStd_dir_path:str, zip_file_prefix:str, zip_index:int, current_zip:io.BytesIO) -> int:
    """
    Writes current_zip to disk (from memory).
    Zip files are named f"{zip_file_prefix}{zip_index}.zip".

    Args:
        FCStd_dir_path (str): Path were to write zip file to on disk.
        zip_file_prefix (str): Prefix for zip file name.
        zip_index (int): Index/iterator of current zip file name being written. This function is called by compress_binaries(), 
                         so the zip_index is essentially the only unique part of the name for each zip file created by compress_binaries().
        current_zip (io.BytesIO): Zip file being written to disk.

    Returns:
        int: next zip_index for next time this function is called. Essentially it's zip_index + 1.
    """
    zip_name:str = f"{zip_file_prefix}{zip_index}.zip"
    zip_path:str = os.path.join(FCStd_dir_path, zip_name)
    with open(zip_path, 'wb') as f:
        f.write(current_zip.getvalue())
    zip_index += 1
    return zip_index


class DecompressBinaries:
    """
    Context manager for decompressing binary zip files in the FCStd directory.
    Extracts files in __enter__ and removes them in __exit__.
    """
    def __init__(self, FCStd_dir_path: str, config: dict):
        self.FCStd_dir_path:str = FCStd_dir_path
        self.config:dict = config
        self.extracted_items:list = []

    def __enter__(self):
        # Do nothing if compress_binaries are disabled
        if not self.config['compress_binaries']['enabled']: return

        # Decompress zip files into self.FCStd_dir_path
        zip_files:list = [f for f in os.listdir(self.FCStd_dir_path) if f.startswith(self.config['compress_binaries']['zip_file_prefix']) and f.endswith('.zip')]
        
        for zip_file in sorted(zip_files):
            zip_path:str = os.path.join(self.FCStd_dir_path, zip_file)
            with zipfile.ZipFile(zip_path, 'r') as zf:
                zf.extractall(self.FCStd_dir_path)
                self.extracted_items.extend(zf.namelist())

    def __exit__(self, exc_type, exc_val, exc_tb):
        # Do nothing if compress_binaries are disabled (admittedly redundant)
        if not self.config['compress_binaries']['enabled']: return
        
        # When leaving context, remove all extracted items
        for item in self.extracted_items:
            item_path:str = os.path.join(self.FCStd_dir_path, item)
            if os.path.exists(item_path):
                if os.path.isdir(item_path):
                    shutil.rmtree(item_path)
                else:
                    os.remove(item_path)

def bad_args(args:argparse.Namespace) -> bool:
    """
    Checks if CLI arguments are invalid. Returns True if invalid.

    Args:
        args (argparse.Namespace): CLI arguments to check.

    Returns:
        bool: True if invalid, else False.
    """
    no_mode_specified:bool = True if not args.export_flag and not args.import_flag else False
    
    if no_mode_specified: return True
    
    bad_arg_count:bool = True if args.export_flag and len(args.export_flag) > 2 or args.import_flag and len(args.import_flag) > 2 else False
    
    if bad_arg_count: return True
    
    missing_output_arg:bool = True if args.export_flag and len(args.export_flag) != 2 or args.import_flag and len(args.import_flag) != 2 else False
    script_called_directly_by_user:bool = not args.configFile_flag
    
    if missing_output_arg and script_called_directly_by_user: return True

def main():
    # Setup CLI args
    parser:argparse.ArgumentParser = argparse.ArgumentParser(add_help=False)
    parser.add_argument(EXPORT_FLAG, dest='export_flag', nargs='+')
    parser.add_argument(IMPORT_FLAG, dest='import_flag', nargs='+')
    parser.add_argument(CONFIG_FILE_FLAG, dest="configFile_flag", action='store_true')
    parser.add_argument("-h", "--help", dest="help_flag", action="store_true")
    
    args:argparse.Namespace = parser.parse_args()
    
    if bad_args(args) or args.help_flag:
        print(HELP_MESSAGE)
        return

    # Load config file
    config:dict
    if args.configFile_flag:
        config:dict = load_config_file(CONFIG_PATH)
    
    script_called_directly_by_user:bool = not args.configFile_flag
    INCLUDE_THUMBNAIL:bool = script_called_directly_by_user or config.get('include_thumbnails', False)
    
    # Main Logic
    if args.export_flag:
        FCStd_file_path:str = os.path.relpath(args.export_flag[0])
        FCStd_dir_path:str = os.path.relpath(args.export_flag[1]) if len(args.export_flag) > 1 else None
        
        if args.configFile_flag: 
            FCStd_dir_path:str = get_FCStd_dir_path(FCStd_file_path, config)
        
        if not os.path.exists(FCStd_dir_path): os.makedirs(FCStd_dir_path)

        PU.extractDocument(FCStd_file_path, FCStd_dir_path)

        if not INCLUDE_THUMBNAIL:
            remove_exported_thumbnail(FCStd_dir_path)
            
        if config['compress_binaries']['enabled']: compress_binaries(FCStd_dir_path, config)

        print(f"Exported {FCStd_file_path} to {FCStd_dir_path}")

    elif args.import_flag:
        FCStd_dir_path:str = os.path.relpath(args.import_flag[0])
        FCStd_file_path:str = os.path.relpath(args.import_flag[1]) if len(args.import_flag) > 1 else None
        
        if args.configFile_flag:
            FCStd_file_path:str = FCStd_dir_path
            FCStd_dir_path:str = get_FCStd_dir_path(FCStd_file_path, config)
        
        with DecompressBinaries(FCStd_dir_path, config):
            
            PU.createDocument(os.path.join(FCStd_dir_path, 'Document.xml'), FCStd_file_path)

            if INCLUDE_THUMBNAIL:
                add_thumbnail_to_FCStd_file(FCStd_dir_path, FCStd_file_path)        
        
        print(f"Created {FCStd_file_path} from {FCStd_dir_path}")

    else:
        print(HELP_MESSAGE)

if __name__ == "__main__":
    main()