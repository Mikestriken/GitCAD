from freecad import project_utility as PU
import os
import argparse

def main():
    parser = argparse.ArgumentParser(description="FreeCAD FCStd file manager")
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # Extract command
    extract_parser = subparsers.add_parser('extract', help='Extract files from FCStd archive')
    extract_parser.add_argument('input_file', help='Path to the FCStd file')
    extract_parser.add_argument('output_dir', help='Directory to extract files to')

    # Create command
    create_parser = subparsers.add_parser('create', help='Create FCStd archive from directory')
    create_parser.add_argument('input_dir', help='Directory containing Document.xml')
    create_parser.add_argument('output_file', help='Path for the output FCStd file')

    args = parser.parse_args()

    if args.command == 'extract':
        if not os.path.exists(args.output_dir):
            os.makedirs(args.output_dir)

        PU.extractDocument(args.input_file, args.output_dir)
        print(f"Extracted {args.input_file} to {args.output_dir}")

    elif args.command == 'create':
        PU.createDocument(os.path.join(args.input_dir, 'Document.xml'), args.output_file)
        print(f"Created {args.output_file} from {args.input_dir}")

    else:
        parser.print_help()

if __name__ == "__main__":
    main()