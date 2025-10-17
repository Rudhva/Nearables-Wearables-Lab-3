import java.io.File;
import java.util.*;
import gifAnimation.*;

boolean hasStarted = false;
float startBtnW = 220;
float startBtnH = 70;


ArrayList<DrawingObject> objects;
ArrayList<String> imgFilenames = new ArrayList<String>();      // basenames only
HashMap<String, PImage> imgLibrary = new HashMap<String, PImage>(); // basename -> PImage

int currentImgIndex = 0;   // which image to place
int selectedObjIndex = -1; // selected object (-1 = none)

// Undo/Redo stacks
ArrayList<ArrayList<DrawingObject>> undoStack = new ArrayList<ArrayList<DrawingObject>>();
ArrayList<ArrayList<DrawingObject>> redoStack = new ArrayList<ArrayList<DrawingObject>>();
boolean ignoreNextPush = false;
int maxHistory = 5;

// Key bindings
char KEY_INC_SIZE = 'z';
char KEY_DEC_SIZE = 'x';
char KEY_ROT_CW   = 'b';
char KEY_ROT_CCW  = 'B';
char KEY_UNDO     = 'c';
char KEY_REDO     = 'C';
char KEY_BLANK    = 'd'; // placeholder
char KEY_SHOW_MENU= 'D';

// Menu state (menu geometry lives in SaveMenu.pde)
boolean showMenu = false;
String inputFilename = "";
boolean typingFilename = false;

Gif bgGif = null;
String bgGifName = "HW_BG.gif";
boolean bgCover = true;

// -------------------------
// Optional: post-process PNGs (white -> transparent)
// -------------------------
void cleanImages() {
  String folderPath = sketchPath("data/library");

  String[] cmd = {
    "/bin/bash",
    "-c",
    "magick mogrify -transparent white '" + folderPath + "/*.png'"
  };

  try {
    println("Running ImageMagick command...");
    Process process = Runtime.getRuntime().exec(cmd);
    process.waitFor();
    println("PNGs processed in-place in 'data/library'.");
  }
  catch (Exception e) {
    // ok to ignore if ImageMagick not installed
    // e.printStackTrace();
  }
}

// -------------------------
// Setup
// -------------------------
void setup() {
  size(800, 600);
  cleanImages();               // optional

  // Load images from data/library
  String libPath = dataPath("library");
  File folder = new File(libPath);
  if (!folder.exists()) folder.mkdirs();
  File[] files = folder.listFiles();

  if (files != null && files.length > 0) {
    for (File f : files) {
      if (!f.isFile()) continue;           // skip subfolders
      String fname = f.getName();
      if (fname.startsWith(".")) continue; // skip hidden

      String low = fname.toLowerCase();
      if (low.endsWith(".png") || low.endsWith(".gif") ||
        low.endsWith(".jpg") || low.endsWith(".jpeg")) {
        // load from data/library/
        PImage img = loadImage("library/" + fname); // GIF: thumbnail only; animation handled in DrawingObject
        if (img != null) {
          imgLibrary.put(fname, img);
          imgFilenames.add(fname);
          println("Loaded: " + fname);
        } else {
          println("Failed to load: " + fname);
        }
      }
    }
  } else {
    println("No files found in data/library.");
  }
  String[] bgPaths = { bgGifName, "library/" + bgGifName };
for (String p : bgPaths) {
  File f2 = new File(dataPath(p));
  if (f2.exists()) {
    try {
      bgGif = new Gif(this, p);
      bgGif.loop();
      println("Background loaded from: " + p);
      break;
    } catch (Exception e) {
      println("Failed to init background from: " + p);
    }
  }
}
  if (bgGif != null) {
    surface.setResizable(true);
    surface.setSize(bgGif.width, bgGif.height + int(bannerHeight)); // reserve space for banner
  }


  objects = new ArrayList<DrawingObject>();
}

// -------------------------
// Draw
// -------------------------
void draw() {
  if (bgGif != null) drawBackgroundGif();
  else background(200);

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
      int w = (obj.gif != null) ? obj.gif.width : (obj.img != null ? obj.img.width : 0);
      int h = (obj.gif != null) ? obj.gif.height : (obj.img != null ? obj.img.height : 0);
      rect(obj.x, obj.y, w * obj.size, h * obj.size);
      noStroke();
    }
  }
drawThumbnailBanner();
  // Instructions
  fill(0);
  textAlign(LEFT, BASELINE);
  text("Click = add | </> select object | b/B = rotate CW/CCW | a/A = scale up/down | Arrow keys = select image | < > = select sprite | c = undo | C = redo | D = Save Menu",
     10, height - bannerHeight - 10);

  if (imgFilenames.size() > 0) {
    text("Placing: " + (currentImgIndex + 1) + " (" + imgFilenames.get(currentImgIndex) + ") | Editing: " + (selectedObjIndex >= 0 ? objects.get(selectedObjIndex).name : "none"), 10, 20);
  } else {
    text("No images loaded! Put PNGs or GIFs in data/library/", 10, 20);
  }

  // Update menu position
  menuX = (width - menuW) / 2;
  menuY = (height - menuH) / 2;

  // Draw menu if active
  if (showMenu) showSaveLoadMenu();
  if (!hasStarted) {
  drawStartOverlay();  
  return;             
  }
}

// -------------------------
// Helper: copy objects
// -------------------------
ArrayList<DrawingObject> copyObjectsList(ArrayList<DrawingObject> list) {
  ArrayList<DrawingObject> copy = new ArrayList<DrawingObject>();
  for (DrawingObject obj : list) {
    copy.add(new DrawingObject(this, obj.img, obj.x, obj.y, obj.size, obj.angle, obj.fileName, obj.name));
  }
  return copy;
}

void pushUndo() {
  if (ignoreNextPush) return;
  undoStack.add(copyObjectsList(objects));
  if (undoStack.size() > maxHistory) undoStack.remove(0);
  redoStack.clear();
}

// -------------------------
// Mouse Input
// -------------------------
void mousePressed() {
  // Start button click handling first
  if (!hasStarted) {
    if (overStartButton()) {
      hasStarted = true;
    }
    return;  // ignore any other clicks until started
  }

  if (showMenu) {
    handleMenuClick();
    return;
  }
  if (imgFilenames.size() == 0) return;

  PImage img = imgLibrary.get(imgFilenames.get(currentImgIndex));
  pushUndo();

  // Generate unique name
  int count = 1;
  String baseName = imgFilenames.get(currentImgIndex);
  int dot = baseName.lastIndexOf('.');
  if (dot >= 0) baseName = baseName.substring(0, dot);
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

  // Add object (PNG/JPG draws still; GIF animates automatically)
  objects.add(new DrawingObject(this, img, mouseX, mouseY, 1.0, 0, imgFilenames.get(currentImgIndex), name));
  selectedObjIndex = objects.size() - 1;
}

// -------------------------
// Keyboard Input
// -------------------------
void keyPressed() {
  // Block keys until user clicks START
  if (!hasStarted) return;

  // Open menu
  if (key == KEY_SHOW_MENU) {
    showMenu = true;
    typingFilename = false;
    menuX = (width - menuW) / 2;
    menuY = (height - menuH) / 2;
  }

  // Menu typing takes over when open
  handleMenuKey(key);
  if (showMenu) return;

  // --- UNDO / REDO (c/C) ---
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

  // --- IMAGE PICKER: A/D (both cases), always allowed ---
  if (imgFilenames.size() > 0) {
    if (key == 'a' || key == 'A') { scrollThumbnailLeft();  return; }
    if (key == 'd' || key == 'D') { scrollThumbnailRight(); return; }
  }

  // If no objects yet, stop here (so A/D can be used before placing)
  if (objects.size() == 0) return;

  // Select a different placed object with < and >
  if (key == '<') { selectedObjIndex = max(0, (selectedObjIndex < 0 ? 0 : selectedObjIndex - 1)); return; }
  if (key == '>') { selectedObjIndex = min(objects.size() - 1, (selectedObjIndex < 0 ? 0 : selectedObjIndex + 1)); return; }

  if (selectedObjIndex < 0) return;
  DrawingObject obj = objects.get(selectedObjIndex);

  // Push undo before modifications
  if (key == KEY_INC_SIZE || key == KEY_DEC_SIZE || key == KEY_ROT_CW || key == KEY_ROT_CCW ||
      keyCode == UP || keyCode == DOWN || keyCode == LEFT || keyCode == RIGHT) {
    pushUndo();
  }

  // Rotate (b/B)
  if (key == KEY_ROT_CW)  { obj.angle += radians(5); return; }
  if (key == KEY_ROT_CCW) { obj.angle -= radians(5); return; }

  // Scale (z/x)
  if (key == KEY_INC_SIZE) { obj.size += 0.05; return; }
  if (key == KEY_DEC_SIZE) { obj.size = max(0.05, obj.size - 0.05); return; }

  // Move selected object with arrows
  if (keyCode == UP)    { obj.y -= 10; return; }
  if (keyCode == DOWN)  { obj.y += 10; return; }
  if (keyCode == LEFT)  { obj.x -= 10; return; }
  if (keyCode == RIGHT) { obj.x += 10; return; }
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
  println("Saved " + filename);
}

void loadObjectsFromInput(String filename) {
  String[] lines = null;
  try {
    lines = loadStrings(filename);
  }
  catch (Exception e) {
    println("File not found: " + filename);
    return;
  }

  if (lines == null || lines.length < 2) {
    println("File empty or invalid: " + filename);
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
  println("Loaded " + filename + " (" + objects.size() + " objects)");
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
    // try to load on-demand from library/
    img = loadImage("library/" + fileName);
    if (img != null) {
      imgLibrary.put(fileName, img);
    } else {
      println("Missing image " + fileName + ", skipping object.");
      return null;
    }
  }

  return new DrawingObject(this, img, x, y, size, angle, fileName, name);
}

// -------------------------
// Thumbnail Helpers
// -------------------------
int thumbCount = 5; // must be odd
float thumbSize = 50;
float selectedThumbSize = 70;
float thumbSpacing = 60;
float bannerHeight = 100;
void drawThumbnailBanner() {
  rectMode(CORNER);
  if (imgFilenames.size() == 0) return;

  // --- draw translucent bar at the bottom ---
  float y0 = height - bannerHeight;
  fill(0, 120); // semi-transparent black
  noStroke();
  rect(0, y0, width, bannerHeight);

  // --- thumbnails centered horizontally, aligned to the bar vertically ---
  int half = thumbCount / 2;
  imageMode(CENTER); // center thumbnails on (x, y)

  for (int i = 0; i < thumbCount; i++) {
    int offset = i - half;
    int idx = (currentImgIndex + offset + imgFilenames.size()) % imgFilenames.size();

    PImage img = imgLibrary.get(imgFilenames.get(idx));
    float w = (i == half) ? selectedThumbSize : thumbSize;
    float h = (i == half) ? selectedThumbSize : thumbSize;

    float x = width / 2 - (half * thumbSpacing) + i * thumbSpacing;
    float y = y0 + bannerHeight / 2;  // vertical center of the bottom bar

    image(img, x, y, w, h);

    // Highlight for the selected (middle) thumbnail
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
boolean overStartButton() {
  // place the button centered in the *background area*, not over the bottom banner
  float y0 = height - bannerHeight;              // top edge of the banner
  float x = (width - startBtnW) / 2.0;
  float y = (y0 - startBtnH) / 2.0;              // vertically center in the top region
  return mouseX >= x && mouseX <= x + startBtnW &&
         mouseY >= y && mouseY <= y + startBtnH;
}

void drawStartOverlay() {
  // dim only the top region (keep banner visible)
  float y0 = height - bannerHeight;
  noStroke();
  fill(0, 140);
  rectMode(CORNER);
  rect(0, 0, width, y0);

  // button
  float x = (width - startBtnW) / 2.0;
  float y = (y0 - startBtnH) / 2.0;
  boolean hover = overStartButton();

  fill(hover ? color(70, 160, 255) : color(40, 120, 220));
  stroke(255);
  strokeWeight(2);
  rect(x, y, startBtnW, startBtnH, 12);

  // label
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(20);
  text("START", x + startBtnW/2.0, y + startBtnH/2.0);

  // hint text (optional)
  textSize(12);
  fill(230);
  text("START → A/D = select image | Click = place | b/B = rotate | z/x = scale | </> = select object | c/C = undo/redo | D = Save Menu",
     10, height - bannerHeight - 10);
}

void drawBackgroundGif() {
  imageMode(CORNER);

  // Height available for the background (top region)
  int availH = height - int(bannerHeight);

  // Scale to cover or fit within the top region
  float sx = width  / (float) bgGif.width;
  float sy = availH / (float) bgGif.height;
  float s  = bgCover ? max(sx, sy) : min(sx, sy);

  float tw = bgGif.width  * s;
  float th = bgGif.height * s;

  // Center the background within the top region
  float ox = (width  - tw) * 0.5f;
  float oy = (availH - th) * 0.5f;

  // Draw background in the top region only
  image(bgGif, ox, oy, tw, th);
}

void scrollThumbnailLeft() {
  currentImgIndex = (currentImgIndex - 1 + imgFilenames.size()) % imgFilenames.size();
}

void scrollThumbnailRight() {
  currentImgIndex = (currentImgIndex + 1) % imgFilenames.size();
}
