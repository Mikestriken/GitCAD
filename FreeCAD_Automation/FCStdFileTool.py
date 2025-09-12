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
        data = json.load(f)

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
            "compression_level": data["compress-non-human-readable-FreeCAD-files"]["compression-level"]
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
    FCStd_dir_name = os.path.basename(FCStd_dir_path).removesuffix(suffix).removeprefix(prefix)
    FCStd_constructed_file_name = f"{FCStd_dir_name}.FCStd"
    
    if USE_SUBDIR: return os.path.relpath(os.path.join(FCStd_dir_path, "../..", FCStd_constructed_file_name))
    
    else: return os.path.relpath(os.path.join(FCStd_dir_path, "..", FCStd_constructed_file_name))
    """
    return None

def remove_export_thumbnail(FCStd_dir_path:str):
    """
    Remove thumbnail folder and contents from uncompressed FCStd file directory.

    Args:
        FCStd_dir_path (str): Path to uncompressed FCStd file directory.
    """
    thumbnails_dir = os.path.join(FCStd_dir_path, 'thumbnails')
    if os.path.exists(thumbnails_dir):
        shutil.rmtree(thumbnails_dir)

def add_thumbnail_to_FCStd_file(FCStd_dir_path:str, FCStd_file_path:str):
    """
    Add thumbnail to .FCStd file if uncompressed FCStd file directory has one.

    Args:
        FCStd_dir_path (str): Path to uncompressed FCStd file directory.
        FCStd_file_path (str): Path to .FCStd file.
    """
    thumbnail_path = os.path.join(FCStd_dir_path, 'thumbnails', 'Thumbnail.png')
    if os.path.exists(thumbnail_path):
        with zipfile.ZipFile(FCStd_file_path, 'a', zipfile.ZIP_DEFLATED) as zf:
            zf.write(thumbnail_path, 'thumbnails/Thumbnail.png')

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
    
    args = parser.parse_args()
    
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
        FCStd_file_path = os.path.relpath(args.export_flag[0])
        FCStd_dir_path = os.path.relpath(args.export_flag[1]) if len(args.export_flag) > 1 else None
        
        if args.configFile_flag: 
            FCStd_dir_path = get_FCStd_dir_path(FCStd_file_path, config)
        
        if not os.path.exists(FCStd_dir_path): os.makedirs(FCStd_dir_path)

        PU.extractDocument(FCStd_file_path, FCStd_dir_path)

        if not INCLUDE_THUMBNAIL:
            remove_export_thumbnail(FCStd_dir_path)
            
        if config['compress_binaries']['enabled']: compress_binaries(FCStd_dir_path, config)

        print(f"Exported {FCStd_file_path} to {FCStd_dir_path}")

    elif args.import_flag:
        FCStd_dir_path = os.path.relpath(args.import_flag[0])
        FCStd_file_path = os.path.relpath(args.import_flag[1]) if len(args.import_flag) > 1 else None
        
        if args.configFile_flag:
            FCStd_file_path = FCStd_dir_path
            FCStd_dir_path = get_FCStd_dir_path(FCStd_file_path, config)
        
        with decompress_binaries(FCStd_dir_path, config):
            
            PU.createDocument(os.path.join(FCStd_dir_path, 'Document.xml'), FCStd_file_path)

            if INCLUDE_THUMBNAIL:
                add_thumbnail_to_FCStd_file(FCStd_dir_path, FCStd_file_path)        
        
        print(f"Created {FCStd_file_path} from {FCStd_dir_path}")

    else:
        print(HELP_MESSAGE)

if __name__ == "__main__":
    main()