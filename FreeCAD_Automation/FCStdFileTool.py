from freecad import project_utility as PU
import os
import argparse
import json
import zipfile
import shutil

CONFIG_PATH:str = 'FreeCAD_Automation/git-freecad-config.json'

# Config file keys
INCLUDE_THUMBNAILS:str = 'include-thumbnails'
COMPRESS_NON_HUMAN:str = 'compress-non-human-readable-FreeCAD-files'
UNCOMPRESSED_DIR_STRUCTURE:str = 'uncompressed-directory-structure'
UNCOMPRESSED_SUFFIX:str = 'uncompressed-directory-suffix'
UNCOMPRESSED_PREFIX:str = 'uncompressed-directory-prefix'
SUBDIRECTORY:str = 'subdirectory'
PUT_IN_SUBDIR:str = 'put-uncompressed-directory-in-subdirectory'
SUBDIR_NAME:str = 'subdirectory-name'

# Config file dictionary and its default values
CONFIG = {
    INCLUDE_THUMBNAILS: False,
    COMPRESS_NON_HUMAN: True,
    UNCOMPRESSED_DIR_STRUCTURE: {
        UNCOMPRESSED_SUFFIX: '_FCStd',
        UNCOMPRESSED_PREFIX: 'FCStd_',
        SUBDIRECTORY: {
            PUT_IN_SUBDIR: True,
            SUBDIR_NAME: 'uncompressed'
        }
    }
}

EXPORT_FLAG:str = '--export'
IMPORT_FLAG:str = '--import'
CLI_FLAG:str = '--CLI' # Ignores config file, just directly interface with the `from freecad import project_utility as PU` API
        
def construct_output_dir(FCStd_file_path:str, config):
    structure = config.get(UNCOMPRESSED_DIR_STRUCTURE, CONFIG[UNCOMPRESSED_DIR_STRUCTURE])
    suffix = structure.get(UNCOMPRESSED_SUFFIX, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][UNCOMPRESSED_SUFFIX])
    prefix = structure.get(UNCOMPRESSED_PREFIX, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][UNCOMPRESSED_PREFIX])
    sub = structure.get(SUBDIRECTORY, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][SUBDIRECTORY])
    base_name = os.path.basename(FCStd_file_path).replace('.FCStd', '').replace('.fcstd', '')
    constructed_name = f"{prefix}{base_name}{suffix}"
    if sub.get(PUT_IN_SUBDIR, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][SUBDIRECTORY][PUT_IN_SUBDIR]):
        subdir = sub.get(SUBDIR_NAME, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][SUBDIRECTORY][SUBDIR_NAME])
        return os.path.join(subdir, constructed_name)
    else:
        return constructed_name

def construct_output_file(FCStd_dir_path:str, FCStd_file_path:str, config):
    structure = config.get(UNCOMPRESSED_DIR_STRUCTURE, CONFIG[UNCOMPRESSED_DIR_STRUCTURE])
    suffix = structure.get(UNCOMPRESSED_SUFFIX, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][UNCOMPRESSED_SUFFIX])
    prefix = structure.get(UNCOMPRESSED_PREFIX, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][UNCOMPRESSED_PREFIX])
    sub = structure.get(SUBDIRECTORY, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][SUBDIRECTORY])
    base_name = os.path.basename(FCStd_dir_path)
    constructed_name = f"{prefix}{base_name}{suffix}"
    if sub.get(PUT_IN_SUBDIR, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][SUBDIRECTORY][PUT_IN_SUBDIR]):
        subdir = sub.get(SUBDIR_NAME, CONFIG[UNCOMPRESSED_DIR_STRUCTURE][SUBDIRECTORY][SUBDIR_NAME])
        return os.path.join(subdir, constructed_name, os.path.basename(FCStd_file_path))
    else:
        return os.path.join(constructed_name, os.path.basename(FCStd_file_path))

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

def main():
    # Setup CLI args
    parser:argparse.ArgumentParser = argparse.ArgumentParser(description="FreeCAD .FCStd file manager")
    parser.add_argument(EXPORT_FLAG, dest='export_flag', nargs=2, metavar=('INPUT_FCSTD_FILE', 'OUTPUT_FCSTD_DIR'), help='export files from .FCStd archive')
    parser.add_argument(IMPORT_FLAG, dest='import_flag', nargs=2, metavar=('INPUT_FCSTD_DIR', 'OUTPUT_FCSTD_FILE'), help='Create .FCStd archive from directory')
    parser.add_argument(CLI_FLAG, dest="cli_flag", action='store_true', help='Use CLI mode, ignore configurations, user just interfaces with project_utility API')

    args = parser.parse_args()

    # Load config files
    config = {}
    
    if not args.cli_flag:
        with open(CONFIG_PATH, 'r') as f:
            config = json.load(f)
    
    # Store booleans used globally in easier to read bool variables
    INCLUDE_THUMBNAIL:bool = args.cli_flag or config.get(INCLUDE_THUMBNAILS, CONFIG[INCLUDE_THUMBNAILS])

    # Main Logic
    if args.export_flag:
        FCStd_file_path, FCStd_dir_path = args.export_flag
        if not args.CLI:
            FCStd_dir_path = construct_output_dir(FCStd_file_path, config)
        
        if not os.path.exists(FCStd_dir_path):
            os.makedirs(FCStd_dir_path)

        PU.extractDocument(FCStd_file_path, FCStd_dir_path)

        if not INCLUDE_THUMBNAIL:
            remove_export_thumbnail(FCStd_dir_path, config)

        print(f"Exported {FCStd_file_path} to {FCStd_dir_path}")

    elif args.import_flag:
        FCStd_dir_path, FCStd_file_path = args.import_flag
        if not args.CLI:
            FCStd_file_path = construct_output_file(FCStd_dir_path, FCStd_file_path, config)
        
        os.makedirs(os.path.dirname(FCStd_file_path), exist_ok=True)
        
        PU.createDocument(os.path.join(FCStd_dir_path, 'Document.xml'), FCStd_file_path)

        if INCLUDE_THUMBNAIL:
            add_thumbnail_to_FCStd_file(FCStd_dir_path, FCStd_file_path, config)

        print(f"Created {FCStd_file_path} from {FCStd_dir_path}")

    else:
        parser.print_help()

if __name__ == "__main__":
    main()