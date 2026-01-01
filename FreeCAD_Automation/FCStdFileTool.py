EXPORT_FLAG:str = '--export'
IMPORT_FLAG:str = '--import'
SILENT_FLAG:str = '--SILENT'
CONFIG_FILE_FLAG:str = '--CONFIG-FILE' # Uses config file to determine configurations. Optionally provide path to config file. Args interpreted differently from what's listed in help()
DIR_FLAG:str = '--dir'
HELP_MESSAGE:str =f"""
usage: FCStdFileTool.py [{EXPORT_FLAG} INPUT_FCSTD_FILE OUTPUT_FCSTD_DIR] [{IMPORT_FLAG} INPUT_FCSTD_DIR OUTPUT_FCSTD_FILE] [{CONFIG_FILE_FLAG} [CONFIG_PATH] {EXPORT_FLAG} FCSTD_FILE] [{CONFIG_FILE_FLAG} [CONFIG_PATH] {IMPORT_FLAG} FCSTD_FILE] [{DIR_FLAG} FCStd_file_path]

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

    {CONFIG_FILE_FLAG} [CONFIG_PATH]
                        Use config file to determine configurations. Optionally provide path to config file. If not provided, uses default path.
                        Args interpreted differently from what's listed:
                            {EXPORT_FLAG} INPUT_FCSTD_FILE, OUTPUT_FCSTD_DIR -> {EXPORT_FLAG} FCSTD_FILE
                            {IMPORT_FLAG} INPUT_FCSTD_DIR, OUTPUT_FCSTD_FILE -> {IMPORT_FLAG} FCSTD_FILE

    {DIR_FLAG} FCStd_file_path
                        Print path to directory containing contents for the given FCStd file. Requires {CONFIG_FILE_FLAG}. Does not guarantee directory exists.

    {SILENT_FLAG}
                        Suppress all print statements. Nothing will be printed to console
"""
from freecad import project_utility as PU
import datetime
import os
import sys
import argparse
import json
import zipfile
import shutil
import io
import warnings
from pathlib import PurePosixPath

USER_RUNNING_LINUX_OS:bool = sys.platform.startswith('linux')

CONFIG_PATH:str = 'FreeCAD_Automation/config.json'

NO_EXTENSION_SUBDIR_NAME:str = 'no_extension'

INPUT_ARG:int = 0
OUTPUT_ARG:int = 1

WRITABLE:int = 0o644
READONLY:int = 0o444

DEBUG:bool = True
def print_debug(message:str, endswith:str='\n'):
    if DEBUG: print(message, end=endswith)

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

def parseArgs() -> argparse.Namespace:
    """
    Configures and parses CLI arguments.

    Returns:
        argparse.Namespace: Parsed args.
    """
    parser:argparse.ArgumentParser = argparse.ArgumentParser(add_help=False)
    parser.add_argument(EXPORT_FLAG, dest='export_flag', nargs='+')
    parser.add_argument(IMPORT_FLAG, dest='import_flag', nargs='+')
    parser.add_argument(CONFIG_FILE_FLAG, dest="config_file_path", nargs='?', const=CONFIG_PATH, default=None)
    parser.add_argument(DIR_FLAG, dest='dir_flag', nargs=1)
    parser.add_argument(SILENT_FLAG, dest="silent_flag", action='store_true')
    parser.add_argument("-h", "--help", dest="help_flag", action="store_true")
    
    return parser.parse_args()

def get_FCStd_dir_path(FCStd_file_path:str, config:dict) -> str:
    """
    Gets path to uncompressed FCStd file directory according to set configurations.

    Args:
        FCStd_file_path (str): Path to .FCStd file.
        config (dict): Configurations dictionary.

    Returns:
        str: Path to uncompressed FCStd file directory.
    """
    # Fix for https://github.com/MikeOpsGit/GitCAD/issues/2
    if not os.path.exists(FCStd_file_path):
        raise FileNotFoundError(f"ERR: FCStd file '{FCStd_file_path}' does not exist.")
    
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

def compress_binaries(FCStd_dir_path:str, config:dict):
    """
    Compresses binary files and folders in the FCStd directory that match the configured patterns.
    Uses io.BytesIO buffers to manage and size limits. Files are removed after compression

    Args:
        FCStd_dir_path (str): Path to the FCStd directory.
        config (dict): Configuration dictionary.
    """
    assert config['compress_binaries']['enabled'], "Error: Attempting to compress binaries despite that config being disabled!"

    patterns:list = config['compress_binaries']['binary_file_patterns']
    max_size_gb:float = config['compress_binaries']['max_compressed_file_size_gigabyte']
    compression_level:int = config['compress_binaries']['compression_level']
    zip_file_prefix:str = config['compress_binaries']['zip_file_prefix']

    max_size_bytes:float = max_size_gb * (1024 ** 3)

    # Collect items to compress
    to_compress:list = []
    for root, _, files in os.walk(FCStd_dir_path):
        for item_name in files:
            item_full_path:str = os.path.join(root, item_name)
            item_rel_path:str = os.path.relpath(item_full_path, start=FCStd_dir_path)
            posix_path:PurePosixPath = PurePosixPath('/' + item_rel_path.replace(os.sep, '/'))
            
            for pattern in patterns:
                if posix_path.match(pattern):
                    to_compress.append(item_full_path)
                    break

    # Compress items into zip files
    zip_index:int = 1
    current_zip:io.BytesIO = io.BytesIO()
    i:int = 0
    isRecompressingFile:bool = False
    wasRecompressingFile:bool = False
    while (i < len(to_compress)):
        item:str = to_compress[i]
        
        if isRecompressingFile and wasRecompressingFile:
            raise ValueError(f"ERR: Config Max Zip Size='{max_size_gb}' GB and Compression Level='{compression_level}' is too small for '{os.path.basename(item)}' with size='{os.path.getsize(item)/(1024 ** 3)}' GB.")
        
        # Backup before adding
        backup:io.BytesIO = io.BytesIO(current_zip.getvalue())
        path_to_item_in_zip:str = os.path.relpath(path=item, start=FCStd_dir_path)
        
        assert not os.path.isdir(item), "ERR: Only individual files should be matched."
        
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
                wasRecompressingFile:bool = isRecompressingFile
                isRecompressingFile:bool = True
                continue
            
            # Remove file
            os.remove(item)
            
        isRecompressingFile:bool = False
        wasRecompressingFile:bool = False
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
        f.flush()
        os.fsync(f.fileno())
    zip_index += 1
    return zip_index

def repackFCStd(FCStd_file_path:str):
    """
    Recreates a provided .FCStd file by copying the contents and the order of the contents.
    Then recreating the .FCStd file from the copied contents.
    
    The this mainly serves to fix this issue: https://github.com/FreeCAD/FreeCAD/issues/23914

    Args:
        FCStd_file_path (str): Path to .FCStd file that needs to be repacked.
    """
    namelist:list = None
    file_data:dict = {}
    with zipfile.ZipFile(FCStd_file_path, 'r') as zf:
        namelist = zf.namelist()
        for file_name in namelist:
            if file_name == "./": continue
            
            with zf.open(file_name) as f:
                file_data[file_name] = f.read()
    
    with open(FCStd_file_path, 'wb') as f:
        with zipfile.ZipFile(f, 'w', zipfile.ZIP_DEFLATED) as zf:
            for file_name in namelist:
                if file_name == "./": continue
                
                zf.writestr(file_name, file_data[file_name])
        f.flush()
        os.fsync(f.fileno())

def move_files_without_extension_to_subdir(FCStd_dir_path:str):
    """
    Moves files without extensions from FCStd_dir_path to a subdirectory named NO_EXTENSION_SUBDIR_NAME.
    
    Args:
        FCStd_dir_path (str): Path to the FCStd directory.
    """
    no_extension_subdir_path:str = os.path.join(FCStd_dir_path, NO_EXTENSION_SUBDIR_NAME)
    os.makedirs(no_extension_subdir_path, exist_ok=True)
    
    for item_name in os.listdir(FCStd_dir_path):
        item_path:str = os.path.join(FCStd_dir_path, item_name)
        if os.path.isfile(item_path) and '.' not in item_name:
            shutil.move(item_path, os.path.join(no_extension_subdir_path, item_name))

class ImportingContext:
    """
    Context manager for importing data to .FCStd file.
    Extracts (compressed and in NO_EXTENSION_SUBDIR_NAME) files in __enter__ to self.FCStd_dir_path and removes them in __exit__.
    """
    def __init__(self, FCStd_dir_path:str, FCStd_file_path:str, config:dict):
        self.FCStd_dir_path:str = FCStd_dir_path
        self.no_extension_subdir_path:str = os.path.join(self.FCStd_dir_path, NO_EXTENSION_SUBDIR_NAME)
        
        self.FCStd_file_path:str = FCStd_file_path
        self.FCStd_file_isReadonly:bool = os.access(self.FCStd_file_path, os.R_OK) and not os.access(self.FCStd_file_path, os.W_OK)

        self.config:dict = config
        self.no_config:bool = config is None
        self.extracted_items:list = []
        self.moved_items:list = []

    def __enter__(self):
        if self.no_config: return
        # Temporarily make file writable
        if self.FCStd_file_isReadonly:
            os.chmod(self.FCStd_file_path, WRITABLE)
        
        # Decompress zip files into self.FCStd_dir_path
        if self.config['compress_binaries']['enabled']:
            zip_files:list = [f for f in os.listdir(self.FCStd_dir_path) if f.startswith(self.config['compress_binaries']['zip_file_prefix']) and f.endswith('.zip')]
                
    
            for zip_file in sorted(zip_files):
                zip_path:str = os.path.join(self.FCStd_dir_path, zip_file)
                with zipfile.ZipFile(zip_path, 'r') as zf:
                    zf.extractall(self.FCStd_dir_path)
                    self.extracted_items.extend(zf.namelist())
        
        # Move files from NO_EXTENSION_SUBDIR_NAME to self.FCStd_dir_path
        os.makedirs(self.no_extension_subdir_path, exist_ok=True)
        for item in os.listdir(self.no_extension_subdir_path):
            src:str = os.path.join(self.no_extension_subdir_path, item)
            dst:str = os.path.join(self.FCStd_dir_path, item)
            if os.path.exists(src):
                shutil.move(src, dst)
                self.moved_items.append(item)
                        
    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.no_config: return
        
        # Restore file permissions
        if self.FCStd_file_isReadonly:
            os.chmod(self.FCStd_file_path, READONLY)
        
        # Move files back to NO_EXTENSION_SUBDIR_NAME
        os.makedirs(self.no_extension_subdir_path, exist_ok=True)
        for item_name in self.moved_items:
            src:str = os.path.join(self.FCStd_dir_path, item_name)
            dst:str = os.path.join(self.no_extension_subdir_path, item_name)
            if os.path.exists(src):
                shutil.move(src, dst)
        
        # When leaving context, remove all extracted items
        if self.config['compress_binaries']['enabled']:
            for item_name in self.extracted_items:
                item_path:str = os.path.join(self.FCStd_dir_path, item_name)
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
    mode_flags:list = [bool(args.export_flag), bool(args.import_flag), bool(args.dir_flag)]
    no_mode_specified:bool = sum(mode_flags) < 1
    if no_mode_specified: return True

    multiple_modes_specified:bool = sum(mode_flags) > 1
    if multiple_modes_specified: return True

    bad_arg_count:bool = True if args.export_flag and len(args.export_flag) > 2 or args.import_flag and len(args.import_flag) > 2 else False
    if bad_arg_count: return True

    missing_output_arg:bool = True if args.export_flag and len(args.export_flag) != 2 or args.import_flag and len(args.import_flag) != 2 else False
    no_config:bool = args.config_file_path is None
    if missing_output_arg and no_config: return True

    mode_requires_config:bool = no_config and (args.dir_flag)
    if mode_requires_config: return True
    
    mode_cannot_be_silent:bool = args.silent_flag and (args.dir_flag)
    if mode_cannot_be_silent: return True
    
    return False

def create_lockfile_and_changefile(FCStd_dir_path:str, FCStd_file_path:str):
    """
    Creates a `.changefile` in FCStd_dir_path with current timestamp and path to FCStd file from FCStd_dir_path.
    Creates an empty `.lockfile` in FCStd_dir_path.

    Args:
        FCStd_dir_path (str): Path to FCStd directory.
        FCStd_file_path (str): Path to .FCStd file.
    """
    lock_file_path:str = os.path.join(FCStd_dir_path, '.lockfile')
    change_file_path:str = os.path.join(FCStd_dir_path, '.changefile')
    FCStd_file_relpath:str = os.path.relpath(FCStd_file_path, start=FCStd_dir_path).replace(os.sep, '/')
    
    current_time:str = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    # Create .changefile with FCStd_file_relpath and timestamp file was created
    with open(change_file_path, 'w') as f:
        f.write(f"File Last Exported On: {current_time}\nFCStd_file_relpath='{FCStd_file_relpath}'\n")
        f.flush()
        os.fsync(f.fileno())
    
    # Create an empty .lockfile
    with open(lock_file_path, 'w') as f:
        f.flush()
        os.fsync(f.fileno())

def main():
    args:argparse.Namespace = parseArgs()
    
    if (bad_args(args) or args.help_flag) and not args.silent_flag:
        print(HELP_MESSAGE)
        return
    
    if args.silent_flag:
        warnings.filterwarnings("ignore")
    
    # Load config file
    config_provided:bool = not args.config_file_path is None
    
    config:dict = None
    if config_provided:
        config:dict = load_config_file(args.config_file_path)

    INCLUDE_THUMBNAIL:bool = not config_provided or config['include_thumbnails'] # Thumbnails should be included (by default) if config isn't provided.
    
    # Main Logic
    if args.dir_flag:
        FCStd_file_path:str = os.path.relpath(args.dir_flag[INPUT_ARG])

        FCStd_dir_path:str = get_FCStd_dir_path(FCStd_file_path, config)

        dir_path:str = os.path.abspath(FCStd_dir_path)
            
        if not args.silent_flag:
            print(dir_path)
        
    elif args.export_flag:
        FCStd_file_path:str = os.path.relpath(args.export_flag[INPUT_ARG])
        FCStd_dir_path:str = os.path.relpath(args.export_flag[OUTPUT_ARG]) if len(args.export_flag) > 1 else None
        
        if not os.path.exists(FCStd_file_path):
            raise FileNotFoundError(f"ERR: FCStd file '{FCStd_file_path}' does not exist.")
        
        if config_provided:
            FCStd_dir_path:str = get_FCStd_dir_path(FCStd_file_path, config)

        # Clear previously exported files
        if os.path.exists(FCStd_dir_path):
            lockfile_path = os.path.join(FCStd_dir_path, '.lockfile')
            if os.path.exists(lockfile_path):
                os.chmod(lockfile_path, WRITABLE) # Note: os.remove and rmtree will err if lockfile is readonly.
                os.remove(lockfile_path)
            
            shutil.rmtree(FCStd_dir_path)

        os.makedirs(FCStd_dir_path, exist_ok=True)

        try:
            PU.extractDocument(FCStd_file_path, FCStd_dir_path)
        except Exception as e:
            print(f"Error extracting {FCStd_file_path} to {FCStd_dir_path}: {e}", file=sys.stderr)
            raise

        if not INCLUDE_THUMBNAIL:
            remove_exported_thumbnail(FCStd_dir_path)
            
        if config_provided:
            move_files_without_extension_to_subdir(FCStd_dir_path)
            
            if config['compress_binaries']['enabled']:
                compress_binaries(FCStd_dir_path, config)

            create_lockfile_and_changefile(FCStd_dir_path, FCStd_file_path)
                
        if not args.silent_flag:
            print(f"Exported {FCStd_file_path} to {FCStd_dir_path}")
        
        if USER_RUNNING_LINUX_OS: os.sync()

    elif args.import_flag:
        FCStd_dir_path:str = os.path.relpath(args.import_flag[INPUT_ARG])
        FCStd_file_path:str = os.path.relpath(args.import_flag[OUTPUT_ARG]) if len(args.import_flag) > 1 else None
        
        if config_provided:
            FCStd_file_path:str = FCStd_dir_path
            FCStd_dir_path:str = get_FCStd_dir_path(FCStd_file_path, config)
            
        if not os.path.exists(FCStd_dir_path):
            raise FileNotFoundError(f"ERR: FCStd directory '{FCStd_dir_path}' does not exist.")
        
        with ImportingContext(FCStd_dir_path, FCStd_file_path, config):
            
            duplicate_warning:bool = False
            with warnings.catch_warnings(record=True) as caught:
                warnings.simplefilter("always")
                
                try:
                    PU.createDocument(os.path.join(FCStd_dir_path, 'Document.xml'), FCStd_file_path)
                except Exception as e:
                    print(f"Error extracting {FCStd_file_path} to {FCStd_dir_path}: {e}", file=sys.stderr)
                    raise
                
                duplicate_warning:bool = any(
                isinstance(warning.message, UserWarning) and "Duplicate name: './'" in str(warning.message)
                for warning in caught
                )
            
            # Fix for this issue: https://github.com/FreeCAD/FreeCAD/issues/23914
            if duplicate_warning:
                repackFCStd(FCStd_file_path)

            if INCLUDE_THUMBNAIL:
                add_thumbnail_to_FCStd_file(FCStd_dir_path, FCStd_file_path)
        
        if not args.silent_flag:
            print(f"Created {FCStd_file_path} from {FCStd_dir_path}")
        
        if USER_RUNNING_LINUX_OS: os.sync()

    elif not args.silent_flag:
        print(HELP_MESSAGE)

if __name__ == "__main__":
    main()