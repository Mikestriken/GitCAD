from freecad import project_utility as PU
import os
import argparse
import json
import zipfile
import shutil

CONFIG_PATH:str = 'FreeCAD_Automation/git-freecad-config.json'
    
EXPORT_FLAG:str = '--export'
IMPORT_FLAG:str = '--import'
CLI_FLAG:str = '--CLI' # Ignores config file, just directly interface with the `from freecad import project_utility as PU` API

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
            "binary_file_patterns": data["compress-non-human-readable-FreeCAD-files"]["files-to-compress"]
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
    
    if USE_SUBDIR: return os.path.abspath(os.path.join(FCStd_file_dir, subdir_name, FCStd_constructed_dir_name))
    
    else: return os.path.abspath(os.path.join(FCStd_file_dir, FCStd_constructed_dir_name))

def get_FCStd_file_path(FCStd_dir_path:str, config:dict) -> str:
    """
    Gets path to .FCStd file according to set configurations.

    Args:
        FCStd_dir_path (str): Path to uncompressed FCStd file directory.
        config (dict): Configurations dictionary.

    Returns:
        str: Path to .FCStd file.
    """
    # Load relevant configs
    suffix:str = config['uncompressed_directory_structure']['uncompressed_directory_suffix']
    prefix:str = config['uncompressed_directory_structure']['uncompressed_directory_prefix']
    subdir_name:str = config['uncompressed_directory_structure']['subdirectory']['subdirectory_name']
    
    USE_SUBDIR:bool = config['uncompressed_directory_structure']['subdirectory']['put_uncompressed_directory_in_subdirectory']
    
    # Construct output path
    FCStd_dir_name = os.path.basename(FCStd_dir_path).removesuffix(suffix).removeprefix(prefix)
    FCStd_constructed_file_name = f"{FCStd_dir_name}.FCStd"
    
    if USE_SUBDIR: return os.path.abspath(os.path.join(FCStd_dir_path, "../..", FCStd_constructed_file_name))
    
    else: return os.path.abspath(os.path.join(FCStd_dir_path, "..", FCStd_constructed_file_name))

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
    
    bad_arg_count:bool = True if args.export_flag and len(args.export_flag) > 2 or args.import_flag and len(args.import_flag) > 2 else False
    
    if bad_arg_count: return True
    
    missing_output_arg:bool = True if args.export_flag and len(args.export_flag) != 2 or args.import_flag and len(args.import_flag) != 2 else False
    
    if missing_output_arg and args.cli_flag: return True

def main():
    # Setup CLI args
    parser:argparse.ArgumentParser = argparse.ArgumentParser(description="FreeCAD .FCStd file manager")
    parser.add_argument(EXPORT_FLAG, dest='export_flag', nargs='+', metavar=('INPUT_FCSTD_FILE', 'OUTPUT_FCSTD_DIR'), help='export files from .FCStd archive')
    parser.add_argument(IMPORT_FLAG, dest='import_flag', nargs='+', metavar=('INPUT_FCSTD_DIR', 'OUTPUT_FCSTD_FILE'), help='Create .FCStd archive from directory')
    parser.add_argument(CLI_FLAG, dest="cli_flag", action='store_true', help='Use CLI mode, ignore configurations, user just interfaces with project_utility API')
    
    args = parser.parse_args()
    
    if bad_args(args):
        parser.print_help()
        return

    # Load config file
    config:dict
    if not args.cli_flag:
        config:dict = load_config_file(CONFIG_PATH)
    else:
        config = {}
    
    
    # I think that by default the thumbnail should be included if using the CLI.
    INCLUDE_THUMBNAIL:bool = args.cli_flag or config.get('include_thumbnails', False)
    
    # Main Logic
    if args.export_flag:
        FCStd_file_path, FCStd_dir_path = os.path.abspath(args.export_flag[0]), os.path.abspath(args.export_flag[1]) if len(args.export_flag) > 1 else None
        
        if not args.cli_flag: FCStd_dir_path = get_FCStd_dir_path(FCStd_file_path, config)
        
        if not os.path.exists(FCStd_dir_path): os.makedirs(FCStd_dir_path)

        # PU.extractDocument(FCStd_file_path, FCStd_dir_path)

        # if not INCLUDE_THUMBNAIL:
        #     remove_export_thumbnail(FCStd_dir_path)

        print(f"Exported {FCStd_file_path} to {FCStd_dir_path}")

    elif args.import_flag:
        FCStd_dir_path, FCStd_file_path = os.path.abspath(args.import_flag[0]), os.path.abspath(args.import_flag[1]) if len(args.import_flag) > 1 else None
        if not args.cli_flag:
            FCStd_file_path = get_FCStd_file_path(FCStd_dir_path, config)
        
        os.makedirs(os.path.dirname(FCStd_file_path), exist_ok=True)
        
        # PU.createDocument(os.path.join(FCStd_dir_path, 'Document.xml'), FCStd_file_path)

        # if INCLUDE_THUMBNAIL:
        #     add_thumbnail_to_FCStd_file(FCStd_dir_path, FCStd_file_path)

        print(f"Created {FCStd_file_path} from {FCStd_dir_path}")

    else:
        parser.print_help()

if __name__ == "__main__":
    main()