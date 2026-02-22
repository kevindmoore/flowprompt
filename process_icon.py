from PIL import Image
import os

def create_adaptive_icon(input_path, output_path):
    # Open the image
    with Image.open(input_path) as img:
        # Convert to RGBA
        img = img.convert("RGBA")
        width, height = img.size
        
        # Get the color of the top-left pixel to use as background
        bg_color = img.getpixel((0, 0))
        
        # Create a new background image of the same size
        new_bg = Image.new("RGBA", (width, height), bg_color)
        
        # Calculate new size (85% of original to be safe)
        scale_factor = 0.85
        new_width = int(width * scale_factor)
        new_height = int(height * scale_factor)
        
        # Resize the original image
        resized_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # Calculate position to center the resized image
        x_offset = (width - new_width) // 2
        y_offset = (height - new_height) // 2
        
        # Paste the resized image onto the background
        # Use the resized image itself as the mask for transparency if needed
        new_bg.paste(resized_img, (x_offset, y_offset), resized_img)
        
        # Save the result
        new_bg.save(output_path)
        print(f"Created adaptive icon at: {output_path}")
        print(f"Using background color: {bg_color}")

if __name__ == "__main__":
    input_file = "assets/images/app_icon_splash.png"
    output_file = "assets/images/app_icon_adaptive.png"
    
    if os.path.exists(input_file):
        create_adaptive_icon(input_file, output_file)
    else:
        print(f"Error: Input file {input_file} not found.")
