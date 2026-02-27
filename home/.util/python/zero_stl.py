# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "trimesh",
# ]
# ///
import argparse
import trimesh
import os
import sys

def zero_stl(input_path, output_path=None, mode="min"):
    # Load the mesh
    mesh = trimesh.load(input_path)

    if mode == "min":
        shift = -mesh.bounds[0]
    elif mode == "center":
        # Geometric center of bounding box
        center_bb = (mesh.bounds[0] + mesh.bounds[1]) / 2
        shift = -center_bb
    elif mode == "mass":
        # Center of mass
        shift = -mesh.center_mass
    elif mode == "mass_bottom":
        # Center of mass in X,Y, but minimum Z at origin
        shift = -mesh.center_mass
        shift[2] = -mesh.bounds[0][2]
    else:
        raise ValueError(f"Invalid mode: {mode}. Use 'min', 'center', 'mass', or 'mass_bottom'.")

    mesh.apply_translation(shift)

    # Prepare output path
    if output_path is None:
        base, ext = os.path.splitext(input_path)
        output_path = f"{base}_zeroed.stl"

    # Export
    mesh.export(output_path)
    print(f"Zeroed STL saved to: {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Move an STL file so it starts at (0,0,0), is centered, or centered by mass with optional bottom alignment.")
    parser.add_argument("--output", help="Output file path (default: *_zeroed.stl next to input)")
    parser.add_argument(
        "--mode",
        choices=["min", "center", "mass", "mass_bottom"],
        default="min",
        help="Mode to zero: 'min' (default, move min corner to 0), 'center' (center of bounding box), 'mass' (center of mass), or 'mass_bottom' (center X/Y on mass, Z min at 0)"
    )
    parser.add_argument("input_path", help="Input STL file path")

    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(0)

    args = parser.parse_args()

    if not args.input_path:
        parser.print_help()
        sys.exit(0)

    zero_stl(args.input_path, args.output, args.mode)
