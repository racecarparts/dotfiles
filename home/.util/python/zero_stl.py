# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "trimesh",
# ]
# ///
import argparse
import trimesh
import os

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
    else:
        raise ValueError(f"Invalid mode: {mode}. Use 'min', 'center', or 'mass'.")

    mesh.apply_translation(shift)

    # Prepare output path
    if output_path is None:
        base, ext = os.path.splitext(input_path)
        output_path = f"{base}_zeroed.stl"

    # Export
    mesh.export(output_path)
    print(f"Zeroed STL saved to: {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Move an STL file so it starts at (0,0,0), is centered, or centered by mass.")
    parser.add_argument("input_path", help="Input STL file path")
    parser.add_argument("--output", help="Output file path (default: *_zeroed.stl next to input)")
    parser.add_argument(
        "--mode",
        choices=["min", "center", "mass"],
        default="min",
        help="Mode to zero: 'min' (default, move min corner to 0), 'center' (center of bounding box), or 'mass' (center of mass)"
    )
    
    args = parser.parse_args()
    
    zero_stl(args.input_path, args.output, args.mode)
