// -------------------------
// Global Variables
// -------------------------
ArrayList<DrawingObject> objects;
ArrayList<String> imgFilenames = new ArrayList<String>();
HashMap<String, PImage> imgLibrary = new HashMap<String, PImage>();

int currentImgIndex = 0;   // which image to place
int selectedObjIndex = -1; // object being edited (-1 = none)

// Undo/Redo stacks
ArrayList<ArrayList<DrawingObject>> undoStack = new ArrayList<ArrayList<DrawingObject>>();
ArrayList<ArrayList<DrawingObject>> redoStack = new ArrayList<ArrayList<DrawingObject>>();
boolean ignoreNextPush = false;
int maxHistory = 5;

// Key bindings
char KEY_INC_SIZE = 'a';
char KEY_DEC_SIZE = 'A';
char KEY_ROT_CW   = 'b';
char KEY_ROT_CCW  = 'B';
char KEY_UNDO     = 'c';
char KEY_REDO     = 'C';
char KEY_BLANK    = 'd'; // placeholder
char KEY_SHOW_MENU= 'D';

//Menu
boolean showMenu = false;
String inputFilename = "";
boolean typingFilename = false;



void cleanImages() {
  String folderPath = sketchPath("data/library");

  // Build the terminal command to make white transparent in place
  String[] cmd = {
    "/bin/bash",
    "-c",
    "magick mogrify -transparent white '" + folderPath + "/*.png'"
  };

  try {
    println("Running ImageMagick command...");
    Process process = Runtime.getRuntime().exec(cmd);
    process.waitFor(); // Wait until it finishes
    println("✅ PNGs processed in-place in 'data/library'!");
  }
  catch (Exception e) {
    e.printStackTrace();
  }
}

// -------------------------
// Setup
// -------------------------
void setup() {
  size(800, 600);

  cleanImages();

  // Load all PNGs from "library" folder
  File folder = new File(dataPath("library"));
  File[] files = folder.listFiles();
  if (files != null) {
    for (File f : files) {
      String fname = f.getName();
      if (fname.toLowerCase().endsWith(".png")) {
        PImage img = loadImage("library/" + fname);
        if (img != null) {
          imgLibrary.put(fname, img);
          imgFilenames.add(fname);
          println("✅ Loaded: " + fname);
        }
      }
    }
  } else {
    println("⚠️ No files found in library folder!");
  }

  objects = new ArrayList<DrawingObject>();
}

// -------------------------
// Draw
// -------------------------
void draw() {
  background(200);
  drawThumbnailBanner();


  // Draw all objects
  for (int i = 0; i < objects.size(); i++) {
    DrawingObject obj = objects.get(i);
    obj.draw();

    // Highlight selected
    if (i == selectedObjIndex) {
      noFill();
      stroke(255, 0, 0);
      strokeWeight(2);
      rectMode(CENTER);
      rect(obj.x, obj.y, obj.img.width * obj.size, obj.img.height * obj.size);
      noStroke();
    }
  }

  // Instructions

  fill(0);
  textAlign(LEFT, BASELINE);
  text(
    "Click = add | </> select object | b/B = rotate CW/CCW | a/A = scale up/down | " +
    "Arrow keys = select image | < > = select sprite | c = undo | C = redo | D = Save Menu",
    10, height - 10
    );

  if (imgFilenames.size() > 0) {
    text(
      "Placing image: " + (currentImgIndex + 1) + " (" + imgFilenames.get(currentImgIndex) +
      ") | Editing object: " + (selectedObjIndex >= 0 ? objects.get(selectedObjIndex).name : "none"),
      10, 20
      );
  } else {
    text("No images loaded! Put PNGs in data/library/", 10, 20);
  }


  // Update menu position
  menuX = (width - menuW) / 2;
  menuY = (height - menuH) / 2;

  // Draw menu if active
  if (showMenu) showSaveLoadMenu();
}

// -------------------------
// Helper: copy objects
// -------------------------
ArrayList<DrawingObject> copyObjectsList(ArrayList<DrawingObject> list) {
  ArrayList<DrawingObject> copy = new ArrayList<DrawingObject>();
  for (DrawingObject obj : list) {
    copy.add(new DrawingObject(obj.img, obj.x, obj.y, obj.size, obj.angle, obj.fileName, obj.name));
  }
  return copy;
}

void pushUndo() {
  if (    ignoreNextPush) return;
  undoStack.add(copyObjectsList(objects));
  if (undoStack.size() > maxHistory) undoStack.remove(0);
  redoStack.clear();
}

// -------------------------
// Mouse Input
// -------------------------
void mousePressed() {
  if (imgFilenames.size() == 0 || showMenu) {
    handleMenuClick();  // make sure menu clicks are handled first
    return; // ignore clicks on menu
  }
  PImage img = imgLibrary.get(imgFilenames.get(currentImgIndex));
  pushUndo();

  // Generate unique name
  int count = 1;
  String baseName = imgFilenames.get(currentImgIndex).substring(0, imgFilenames.get(currentImgIndex).lastIndexOf('.'));
  String name = baseName + count;
  boolean exists = true;
  while (exists) {
    exists = false;
    for (DrawingObject o : objects) {
      if (o.name.equals(name)) {
        exists = true;
        count++;
        name = baseName + count;
        break;
      }
    }
  }

  objects.add(new DrawingObject(img, mouseX, mouseY, 1.0, 0, imgFilenames.get(currentImgIndex), name));
  selectedObjIndex = objects.size() - 1;
}


// -------------------------
// Keyboard Input
// -------------------------
void keyPressed() {
  // Show menu
  if (key == KEY_SHOW_MENU) {
    showMenu = true;
    typingFilename = false;

    // Calculate menu position once
    menuX = (width - menuW) / 2;
    menuY = (height - menuH) / 2;
  }


  // Menu typing
  handleMenuKey(key);
  if (showMenu) return; // block other keys

  // Cycle image library
  if (key == 'n') currentImgIndex = (currentImgIndex + 1) % imgFilenames.size();
  if (key == 'p') currentImgIndex = (currentImgIndex - 1 + imgFilenames.size()) % imgFilenames.size();

  // Undo / Redo
  if (key == KEY_UNDO) {
    if (undoStack.size() > 0) {
      ignoreNextPush = true;
      redoStack.add(copyObjectsList(objects));
      if (redoStack.size() > maxHistory) redoStack.remove(0);
      objects = undoStack.remove(undoStack.size() - 1);
      selectedObjIndex = objects.size() - 1;
      ignoreNextPush = false;
    }
    return;
  }

  if (key == KEY_REDO) {
    if (redoStack.size() > 0) {
      ignoreNextPush = true;
      undoStack.add(copyObjectsList(objects));
      if (undoStack.size() > maxHistory) undoStack.remove(0);
      objects = redoStack.remove(redoStack.size() - 1);
      selectedObjIndex = objects.size() - 1;
      ignoreNextPush = false;
    }
    return;
  }

  if (objects.size() == 0 || selectedObjIndex < 0) return;
  DrawingObject obj = objects.get(selectedObjIndex);

  // Select object
  if (key == '<') selectedObjIndex = max(0, selectedObjIndex - 1);
  if (key == '>') selectedObjIndex = min(objects.size() - 1, selectedObjIndex + 1);

  // Push undo before modifying
  if (key == KEY_INC_SIZE || key == KEY_DEC_SIZE || key == KEY_ROT_CW || key == KEY_ROT_CCW ||
    keyCode == UP || keyCode == DOWN || keyCode == LEFT || keyCode == RIGHT) {
    pushUndo();
  }

  // Rotate
  if (key == KEY_ROT_CW) obj.angle += radians(5);
  if (key == KEY_ROT_CCW) obj.angle -= radians(5);

  // Scale
  if (key == KEY_INC_SIZE) obj.size += 0.05;
  if (key == KEY_DEC_SIZE) obj.size = max(0.05, obj.size - 0.05);

  // Move
  if (keyCode == UP) obj.y -= 10;
  if (keyCode == DOWN) obj.y += 10;
  if (keyCode == LEFT) obj.x -= 10;
  if (keyCode == RIGHT) obj.x += 10;

  //Select Sprite To Place
  if (keyCode == LEFT)  scrollThumbnailLeft();
  if (keyCode == RIGHT) scrollThumbnailRight();
}

// -------------------------
// CSV Save/Load
// -------------------------
void saveObjectsCSV(String filename) {
  if (objects.size() == 0) return;

  String[] lines = new String[objects.size() + 1];
  lines[0] = "x,y,size,angle,fileName,spriteName";

  for (int i = 0; i < objects.size(); i++) {
    lines[i + 1] = objects.get(i).toCSV();
  }

  saveStrings(filename, lines);
  println("✅ Saved " + filename);
}

void loadObjectsFromInput(String filename) {
  String[] lines = null;
  try {
    lines = loadStrings(filename);
  }
  catch (Exception e) {
    println("⚠️ File not found: " + filename);
    return;
  }

  if (lines == null || lines.length < 2) {
    println("⚠️ File empty or invalid: " + filename);
    return;
  }

  objects.clear();
  selectedObjIndex = -1;

  for (int i = 1; i < lines.length; i++) {
    if (trim(lines[i]).length() == 0) continue;
    DrawingObject obj = createObjectFromCSV(lines[i]);
    if (obj != null) objects.add(obj);
  }

  if (objects.size() > 0) selectedObjIndex = objects.size() - 1;
  println("✅ Loaded " + filename + " (" + objects.size() + " objects)");
}

DrawingObject createObjectFromCSV(String line) {
  String[] parts = split(line, ',');
  if (parts.length < 6) return null;

  float x = float(parts[0]);
  float y = float(parts[1]);
  float size = float(parts[2]);
  float angle = float(parts[3]);
  String fileName = parts[4];
  String name = parts[5];

  PImage img = imgLibrary.get(fileName);
  if (img == null) {
    println("⚠️ Missing image " + fileName + ", skipping object.");
    return null;
  }

  return new DrawingObject(img, x, y, size, angle, fileName, name);
}


// -------------------------
// Thumbnail Helper
// -------------------------
int thumbCount = 5; // always odd
float thumbSize = 50;
float selectedThumbSize = 70;
float thumbSpacing = 60;
float bannerHeight = 100;

void drawThumbnailBar() {
  if (imgFilenames.size() == 0) return;

  int half = thumbCount / 2;

  for (int i = 0; i < thumbCount; i++) {
    int offset = i - half;
    int idx = (currentImgIndex + offset + imgFilenames.size()) % imgFilenames.size();

    PImage img = imgLibrary.get(imgFilenames.get(idx));
    float w = (i == half) ? selectedThumbSize : thumbSize;
    float h = (i == half) ? selectedThumbSize : thumbSize;

    float x = width / 2 - (half * thumbSpacing) + i * thumbSpacing;
    float y = 50;

    image(img, x, y, w, h);

    // Optional highlight for selected (middle)
    if (i == half) {
      noFill();
      stroke(255, 0, 0);
      strokeWeight(2);
      rectMode(CENTER);
      rect(x, y, w + 4, h + 4);
      noStroke();
    }
  }
}


void drawThumbnailBanner() {
  rectMode(CORNER);
  if (imgFilenames.size() == 0) return;

  // Draw translucent banner
  fill(0, 120); // semi-transparent black
  noStroke();
  rect(0, 0, width, bannerHeight);

  int half = thumbCount / 2;
  for (int i = 0; i < thumbCount; i++) {
    int offset = i - half;
    int idx = (currentImgIndex + offset + imgFilenames.size()) % imgFilenames.size();

    PImage img = imgLibrary.get(imgFilenames.get(idx));
    float w = (i == half) ? selectedThumbSize : thumbSize;
    float h = (i == half) ? selectedThumbSize : thumbSize;

    float x = width / 2 - (half * thumbSpacing) + i * thumbSpacing;
    float y = bannerHeight / 2;

    image(img, x, y, w, h);

    // Highlight middle (selected) thumbnail
    if (i == half) {
      noFill();
      stroke(255, 0, 0);
      strokeWeight(2);
      rectMode(CENTER);
      rect(x, y, w + 4, h + 4);
      noStroke();
    }
  }
}


// Scroll thumbnails left/right
void scrollThumbnailLeft() {
  currentImgIndex = (currentImgIndex - 1 + imgFilenames.size()) % imgFilenames.size();
}

void scrollThumbnailRight() {
  currentImgIndex = (currentImgIndex + 1) % imgFilenames.size();
}

