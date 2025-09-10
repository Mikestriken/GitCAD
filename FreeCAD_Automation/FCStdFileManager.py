from freecad import project_utility as PU
import os
import argparse
import json
import zipfile

CONFIG_PATH:str = 'FreeCAD_Automation/git-freecad-config.json'

EXPORT_CMD:str = '--export'
IMPORT_CMD:str = '--import'
        
def main():
    parser = argparse.ArgumentParser(description="FreeCAD FCStd file manager")
    parser.add_argument(EXPORT_CMD, dest='export_flag', nargs=2, metavar=('INPUT_FILE', 'OUTPUT_DIR'), help='export files from .FCStd archive')
    parser.add_argument(IMPORT_CMD, dest='import_flag', nargs=2, metavar=('INPUT_DIR', 'OUTPUT_FILE'), help='Create .FCStd archive from directory')

    args = parser.parse_args()

    if args.export_flag:
        input_file, output_dir = args.export_flag
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        PU.extractDocument(input_file, output_dir)

        print(f"Exported {input_file} to {output_dir}")

    elif args.import_flag:
        input_dir, output_file = args.import_flag
        PU.createDocument(os.path.join(input_dir, 'Document.xml'), output_file)

        with open(CONFIG_PATH, 'r') as f:
            config = json.load(f)

        if config.get('include-thumbnails', False):
            thumbnails_dir = os.path.join(input_dir, 'thumbnails')

            if os.path.exists(thumbnails_dir):

                with zipfile.ZipFile(output_file, 'a', zipfile.ZIP_DEFLATED) as zf:

                    for root, dirs, files in os.walk(thumbnails_dir):
                        for file in files:
                            filepath = os.path.join(root, file)
                            arcname = os.path.relpath(filepath, input_dir)
                            zf.write(filepath, arcname)

        print(f"Created {output_file} from {input_dir}")

    else:
        parser.print_help()

if __name__ == "__main__":
    main()