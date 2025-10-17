import gifAnimation.*;
import processing.core.PApplet;

class DrawingObject {
  PApplet app;

  // Media
  PImage img;        
  Gif gif;          
  boolean isGif = false;

  // Pose / identity
  float x, y;
  float size;
  float angle;
  String fileName;   
  String name;      

  DrawingObject(PApplet app, PImage img, float x, float y, float size, float angle, String fileName, String name) {
    this.app = app;
    this.img = img;
    this.x = x;
    this.y = y;
    this.size = size;
    this.angle = angle;
    this.fileName = fileName;
    this.name = name;

    String low = (fileName == null) ? "" : fileName.toLowerCase();
    if (low.endsWith(".gif")) {
      isGif = true;
      try {
        gif = new Gif(app, fileName);
        gif.loop();
      } catch (Exception e) {
        // Fallback to library/ prefix
        try {
          gif = new Gif(app, "library/" + fileName);
          gif.loop();
        } catch (Exception e2) {
        }
      }
    }
  }

  void ensureGifLoaded() {
    if (isGif && gif == null && app != null && fileName != null) {
      try {
        gif = new Gif(app, fileName);
        gif.loop();
      } catch (Exception e) {
        try {
          gif = new Gif(app, "library/" + fileName);
          gif.loop();
        } catch (Exception e2) {
          // give up
        }
      }
    }
  }

  void draw() {
    pushMatrix();
    translate(x, y);
    rotate(angle);
    imageMode(CENTER);

    if (isGif) ensureGifLoaded();

    if (isGif && gif != null) {
      image(gif, 0, 0, gif.width * size, gif.height * size);
    } else if (img != null) {
      image(img, 0, 0, img.width * size, img.height * size);
    }
    popMatrix();
  }

  String toCSV() {
    return x + "," + y + "," + size + "," + angle + "," + fileName + "," + name;
  }
}
