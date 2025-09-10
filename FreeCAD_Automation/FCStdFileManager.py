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

EXPORT_CMD:str = '--export'
IMPORT_CMD:str = '--import'
        
def main():
    parser:argparse.ArgumentParser = argparse.ArgumentParser(description="FreeCAD .FCStd file manager")
    parser.add_argument(EXPORT_CMD, dest='export_flag', nargs=2, metavar=('INPUT_FILE', 'OUTPUT_DIR'), help='export files from .FCStd archive')
    parser.add_argument(IMPORT_CMD, dest='import_flag', nargs=2, metavar=('INPUT_DIR', 'OUTPUT_FILE'), help='Create .FCStd archive from directory')

    args = parser.parse_args()
    
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)

    if args.export_flag:
        input_file, output_dir = args.export_flag
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        PU.extractDocument(input_file, output_dir)

        if not config.get(INCLUDE_THUMBNAILS, DEFAULT_CONFIG[INCLUDE_THUMBNAILS]):
            thumbnails_dir = os.path.join(output_dir, 'thumbnails')
            if os.path.exists(thumbnails_dir):
                shutil.rmtree(thumbnails_dir)

        print(f"Exported {input_file} to {output_dir}")

    elif args.import_flag:
        input_dir, output_file = args.import_flag
        PU.createDocument(os.path.join(input_dir, 'Document.xml'), output_file)

        if config.get(INCLUDE_THUMBNAILS, DEFAULT_CONFIG[INCLUDE_THUMBNAILS]):
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