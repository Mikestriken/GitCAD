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

DEFAULT_CONFIG = {
    INCLUDE_THUMBNAILS: False,
    COMPRESS_NON_HUMAN: True
}

EXPORT_FLAG:str = '--export'
IMPORT_FLAG:str = '--import'
CLI_FLAG:str = '--CLI' # Ignores config file, just directly interface with the `from freecad import project_utility as PU` API
        
def main():
    # Setup CLI args
    parser:argparse.ArgumentParser = argparse.ArgumentParser(description="FreeCAD .FCStd file manager")
    parser.add_argument(EXPORT_FLAG, dest='export_flag', nargs=2, metavar=('INPUT_FILE', 'OUTPUT_DIR'), help='export files from .FCStd archive')
    parser.add_argument(IMPORT_FLAG, dest='import_flag', nargs=2, metavar=('INPUT_DIR', 'OUTPUT_FILE'), help='Create .FCStd archive from directory')
    parser.add_argument(CLI_FLAG, dest="cli_flag", action='store_true', help='Use CLI mode, ignore configurations, user just interfaces with project_utility API')

    args = parser.parse_args()

    # Load config files
    config = {}
    
    if not args.cli_flag:
        with open(CONFIG_PATH, 'r') as f:
            config = json.load(f)
    
    # Store booleans used globally in easier to read bool variables
    CLI_MODE:bool = args.cli_flag
    INCLUDE_THUMBNAIL:bool = config.get(INCLUDE_THUMBNAILS, DEFAULT_CONFIG[INCLUDE_THUMBNAILS])

    # Main Logic
    if args.export_flag:
        input_file, output_dir = args.export_flag
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        PU.extractDocument(input_file, output_dir)

        # Store thumbnail? logic
        if not CLI_MODE and not INCLUDE_THUMBNAIL:
            thumbnails_dir = os.path.join(output_dir, 'thumbnails')
            if os.path.exists(thumbnails_dir):
                shutil.rmtree(thumbnails_dir)

        print(f"Exported {input_file} to {output_dir}")

    elif args.import_flag:
        input_dir, output_file = args.import_flag
        PU.createDocument(os.path.join(input_dir, 'Document.xml'), output_file)

        # Store thumbnail? logic
        if CLI_MODE or INCLUDE_THUMBNAIL:
            thumbnails_dir = os.path.join(input_dir, 'thumbnails')

            if os.path.exists(thumbnails_dir):

                thumbnail_path = os.path.join(input_dir, 'thumbnails', 'Thumbnail.png')
                
                if os.path.exists(thumbnail_path):
                    with zipfile.ZipFile(output_file, 'a', zipfile.ZIP_DEFLATED) as zf:
                        zf.write(thumbnail_path, 'thumbnails/Thumbnail.png')

        print(f"Created {output_file} from {input_dir}")

    else:
        parser.print_help()

if __name__ == "__main__":
    main()