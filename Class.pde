class DrawingObject {
  PImage img;
  float x, y;
  float size;
  float angle;
  String fileName;   // PNG file
  String name;       // Unique display name

  DrawingObject(PImage img, float x, float y, float size, float angle, String fileName, String name) {
    this.img = img;
    this.x = x;
    this.y = y;
    this.size = size;
    this.angle = angle;
    this.fileName = fileName;
    this.name = name;
  }

  void draw() {
    pushMatrix();
    translate(x, y);
    rotate(angle);
    imageMode(CENTER);
    image(img, 0, 0, img.width * size, img.height * size);
    popMatrix();
  }

  String toCSV() {
    return x + "," + y + "," + size + "," + angle + "," + fileName + "," + name;
  }
}
