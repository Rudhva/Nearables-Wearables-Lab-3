import java.io.File;
import java.util.*;
import gifAnimation.*;
import processing.serial.*;

//added
// --- MODES ---
final int MODE_PICK_BG  = 0;
final int MODE_PICK_CAT = 1;
final int MODE_PICK_IMG = 2;
final int MODE_MOVE_OBJ = 3;
final int MODE_SELECT_OBJ = 4; // new mode for picking object from the banner
int mode = MODE_PICK_BG;

// --- CATALOGS ---
String[] CATALOGS = { "frame", "item", "my_love", "words", "other" };
int currentBgIndex = 0;
int currentCatIndex = 0;    // index in CATALOGS
int currentImgIndex = 0;    // index inside current catalog
int bgDrawX = 0, bgDrawY = 0, bgDrawW = 0, bgDrawH = 0;
boolean inPicker = false;

// --- Background choices (thumbnails) ---
ArrayList<String> bgFilenames = new ArrayList<String>();      // e.g., "library/background/foo.gif"
HashMap<String, PImage> bgThumbs = new HashMap<String, PImage>();

// --- Catalog -> list of files (thumbnails) ---
HashMap<String, ArrayList<String>> catFiles = new HashMap<String, ArrayList<String>>(); // key=cat, val=list of "library/cat/file.png"

// --- Also support still background images (PNG/JPG) ---
PImage bgStill = null;

int marginTop = 40;
int marginRight = 40;
int marginBottom = 40;
int marginLeft = 40;

boolean isImageFile(String low) {
  return low.endsWith(".png") || low.endsWith(".jpg") || low.endsWith(".jpeg") || low.endsWith(".gif");
}

void scanBackgrounds() {
  bgFilenames.clear();
  File dir = new File(dataPath("library/background"));
  if (!dir.exists()) return;
  File[] files = dir.listFiles();
  if (files == null) return;
  for (File f : files) {
    if (!f.isFile()) continue;
    String name = f.getName();
    String low = name.toLowerCase();
    if (isImageFile(low)) {
      String rel = "library/background/" + name;
      bgFilenames.add(rel);
      // cache a small thumbnail
      PImage th = loadImage(rel);
      if (th != null) {
        int MAX_THUMB = 200;
        if (th.width > MAX_THUMB || th.height > MAX_THUMB) th.resize(MAX_THUMB, 0);
        bgThumbs.put(rel, th);
      }
    }
  }
}

void scanCatalogs() {
  catFiles.clear();
  for (String cat : CATALOGS) {
    ArrayList<String> list = new ArrayList<String>();
    File dir = new File(dataPath("library/" + cat));
    if (!dir.exists()) { catFiles.put(cat, list); continue; }
    File[] files = dir.listFiles();
    if (files == null) { catFiles.put(cat, list); continue; }
    for (File f : files) {
      if (!f.isFile()) continue;
      String name = f.getName();
      String low = name.toLowerCase();
      if (isImageFile(low)) {
        String rel = "library/" + cat + "/" + name;
        list.add(rel);
        // preview cache: load into imgLibrary keyed by rel
        if (!imgLibrary.containsKey(rel)) {
          PImage im = loadImage(rel);
          if (im != null) {
            int MAX_THUMB = 200;
            if (im.width > MAX_THUMB || im.height > MAX_THUMB) im.resize(MAX_THUMB, 0);
            imgLibrary.put(rel, im);
          }
        }
      }
    }
    catFiles.put(cat, list);
  }
}

void setBackgroundFromPath(String rel) {
  // clear old
  bgGif = null;
  bgStill = null;

  try {
    String low = rel.toLowerCase();
    if (low.endsWith(".gif")) {
      bgGif = new Gif(this, rel);
      bgGif.loop();
      println("BG set to GIF: " + rel);
    } else {
      bgStill = loadImage(rel);
      println("BG set to image: " + rel);
    }
    // resize window to background + margins + banner + infoBar
    int bw = (bgGif != null) ? bgGif.width : (bgStill != null ? bgStill.width : width);
    int bh = (bgGif != null) ? bgGif.height : (bgStill != null ? bgStill.height : height);
    surface.setResizable(true);
    surface.setSize(
      bw + marginLeft + marginRight,
      bh + marginTop + marginBottom + infoBarHeight + int(bannerHeight)
    );

  } catch (Exception e) {
    println("Failed to set background: " + rel);
  }
}


// --- Objects / images library (merged from both codes) ---
ArrayList<DrawingObject> objects;
ArrayList<String> imgFilenames = new ArrayList<String>();      // basenames only (legacy / generic loader)
HashMap<String, PImage> imgLibrary = new HashMap<String, PImage>(); // basename or rel -> PImage

int selectedObjIndex = -1; // selected object (-1 = none)

// Undo/Redo stacks
ArrayList<ArrayList<DrawingObject>> undoStack = new ArrayList<ArrayList<DrawingObject>>();
ArrayList<ArrayList<DrawingObject>> redoStack = new ArrayList<ArrayList<DrawingObject>>();
boolean ignoreNextPush = false;
int maxHistory = 5;

// Key bindings
// Key bindings for JIKL scheme
char KEY_a  = 'i'; // increase size
char KEY_A  = 'I'; // decrease size (capital i)
char KEY_b    = 'l'; // rotate CW
char KEY_B   = 'L'; // rotate CCW (capital L)
char KEY_c = 'k'; // open catalog
char KEY_C = 'K'; // save menu (capital K)
char KEY_d      = 'j'; // undo
char KEY_D      = 'J'; // redo


Gif bgGif = null;
String bgGifName = "HW_BG.gif";
boolean bgCover = false;



// -------------------------
// Serial (from Codice 1)
// -------------------------
Serial myPort;
String latestSerialMessage = "";
boolean Fn=false;
boolean tap=false;

// -------------------------
// Setup
// -------------------------
void setup() {
  size(800, 600);
  cleanImages();

  // Initialize serial as in Codice 1
  try {
    myPort = new Serial(this, "COM3", 115200);
    println("Serial opened on COM3 115200");
  } catch (Exception e) {
    println("Failed to open serial on WINDOWS: " + e.getMessage());
  }
  try {
    String portName = Serial.list()[Serial.list().length - 1];
    myPort = new Serial(this, portName, 115200);
    println("Serial opened on COM3 115200");
  } catch (Exception e) {
    println("Failed to open serial on MAC: " + e.getMessage());
  }


  // Generic loader from data/library root (keeps legacy behavior)
  String libPath = dataPath("library");
  File folder = new File(libPath);
  if (!folder.exists()) folder.mkdirs();
  File[] files = folder.listFiles();

  if (files != null && files.length > 0) {
    for (File f : files) {
      if (!f.isFile()) continue;
      String fname = f.getName();
      if (fname.startsWith(".")) continue;

      String low = fname.toLowerCase();
      if (low.endsWith(".png") || low.endsWith(".gif") ||
        low.endsWith(".jpg") || low.endsWith(".jpeg")) {
        // load from data/library/
        PImage img = loadImage("library/" + fname); // GIF: thumbnail only; animation handled in DrawingObject
        if (img != null) {
          imgLibrary.put("library/" + fname, img); // store with rel key too
          imgLibrary.put(fname, img); // also store by basename
          imgFilenames.add(fname);
          println("Loaded root: " + fname);
        } else {
          println("Failed to load: " + fname);
        }
      }
    }
  } else {
    println("No files found in data/library.");
  }

  // Scan backgrounds and catalogs (Codice 2)
  scanBackgrounds();
  scanCatalogs();

  // Start the keyboard flow at "pick background"
  mode = MODE_PICK_BG;
  currentBgIndex  = 0;
  currentCatIndex = 0;
  currentImgIndex = 0;

  objects = new ArrayList<DrawingObject>();
}

// -------------------------
// Draw
// -------------------------
void draw() {
  background(0);
  if (bgGif != null || bgStill != null) drawBackgroundGif();
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
  
  drawLayerBanner();
  drawThumbnailBanner();

  // Update menu position (if SaveMenu.pde present)
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
// Place / Delete (sensor + keyboard support)
// -------------------------
boolean placingTrack = false; // toggle state from Codice 1

void placeTrackAtCursor() {
  // Place currently selected catalog image at mouseX, mouseY (if possible)

  // determine image to place: prefer current catalog selection if available, else fallback to root imgFilenames
  String rel = null;
  ArrayList<String> list = catFiles.get(CATALOGS[currentCatIndex]);
  if (list != null && list.size() > 0) {
    rel = list.get(currentImgIndex % list.size());
  } else if (imgFilenames.size() > 0) {
    rel = "library/" + imgFilenames.get(currentImgIndex % imgFilenames.size());
  }

  if (rel == null) return;

  PImage img = imgLibrary.get(rel);
  if (img == null) {
    img = loadImage(rel);
    if (img != null) imgLibrary.put(rel, img);
  }
  if (img == null) return;

  pushUndo();

  // generate univocal name for the object
  int count = 1;
  String baseName = rel.substring(rel.lastIndexOf('/') + 1);
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

  objects.add(new DrawingObject(this, img, mouseX, mouseY, 1.0, 0, rel, name));
  selectedObjIndex = objects.size() - 1;
}

void deleteSelectedTrack() {
  println("Deleting...");
  if (selectedObjIndex >= 0 && selectedObjIndex < objects.size()) {
    pushUndo();
    objects.remove(selectedObjIndex);
    // Adjust selected index after deletion
    if (objects.isEmpty()) {
      selectedObjIndex = -1; // No selection left
    } else if (selectedObjIndex >= objects.size()) {
      selectedObjIndex = objects.size() - 1; // Move to last object
    }
  }
}


// -------------------------
// Mouse Input
// -------------------------
void mousePressed() {
  if (showMenu) {
    handleMenuClick();
    return;
  }

  
  // Place using currently selected catalog image if any
  //placeTrackAtCursor();
}



// -------------------------
// Keyboard Input (from Codice 2, preserved)
// -------------------------
void keyPressed() {
  // Block everything until START

  // Menu
  if (key == KEY_D) {
    showMenu = true; typingFilename = false;
    menuX = (width - menuW) / 2; menuY = (height - menuH) / 2;
  }
  handleMenuKey(key);
  if (showMenu) return;

  boolean navLeft  = (keyCode == LEFT );
  boolean navRight = (keyCode == RIGHT );
  boolean okKey    = (key == ENTER || key == RETURN);

  // Undo/Redo still work in any mode
  if (key == KEY_c) {
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
  if (key == KEY_C) {
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
  

  switch (mode) {
    case MODE_SELECT_OBJ: {
  if (objects.size() == 0) return;

  if (keyCode == UP) {
    selectedObjIndex = (selectedObjIndex + 1 + objects.size()) % objects.size();
    return;
  }

  if (keyCode == DOWN) {
    selectedObjIndex = (selectedObjIndex - 1) % objects.size();
    return;
  }

  // ENTER confirms selection and switches back to MOVE_OBJ mode
  if (key == ENTER || key == RETURN) {
    mode = MODE_MOVE_OBJ;
    return;
  }

  break;
}

    case MODE_PICK_BG: {
      if (bgFilenames.size() == 0) return;
      if (navLeft)  { currentBgIndex = (currentBgIndex - 1 + bgFilenames.size()) % bgFilenames.size(); return; }
      if (navRight) { currentBgIndex = (currentBgIndex + 1) % bgFilenames.size(); return; }
      if (okKey) {
        setBackgroundFromPath(bgFilenames.get(currentBgIndex));
        mode = MODE_PICK_CAT;
        return;
      }
      break;
    }
    case MODE_PICK_CAT: {
      if (navLeft)  { currentCatIndex = (currentCatIndex - 1 + CATALOGS.length) % CATALOGS.length; return; }
      if (navRight) { currentCatIndex = (currentCatIndex + 1) % CATALOGS.length; return; }
      if (okKey)    { currentImgIndex = 0; mode = MODE_PICK_IMG; return; }
      break;
    }
    case MODE_PICK_IMG: {
      String cat = CATALOGS[currentCatIndex];
      ArrayList<String> list = catFiles.get(cat);
      if (list == null || list.size() == 0) return;

      if (navLeft)  { currentImgIndex = (currentImgIndex - 1 + list.size()) % list.size(); return; }
      if (navRight) { currentImgIndex = (currentImgIndex + 1) % list.size(); return; }
      if (keyCode == UP) { mode = MODE_PICK_CAT; return; }
      if (okKey) {
        // Create object at center of top region (ignores mouse)
        String rel = list.get(currentImgIndex);
        PImage im = imgLibrary.get(rel);
        if (im == null) im = loadImage(rel);

        float cx = marginLeft + (width - marginLeft - marginRight) / 2.0;
        float cy = marginTop  + (height - bannerHeight - marginTop - marginBottom) / 2.0;

        pushUndo();
        String name = makeUniqueName(rel);
        objects.add(new DrawingObject(this, im, cx, cy, 1.0, 0, rel, name));
        selectedObjIndex = objects.size() - 1;
        mode = MODE_MOVE_OBJ;  // now arrows move the object
        return;
      }
      break;
    }
    case MODE_MOVE_OBJ: {
      if (selectedObjIndex < 0 || selectedObjIndex >= objects.size()) { mode = MODE_PICK_IMG; return; }
      DrawingObject obj = objects.get(selectedObjIndex);

      // movement only in this mode:
      if (key == 'a') { pushUndo(); obj.x -= 10; return; }
      if (key == 'd') { pushUndo(); obj.x += 10; return; }
      if (key == 'w') { pushUndo(); obj.y -= 10; return; }
      if (key == 's') { pushUndo(); obj.y += 10; return; }


      // rotate/scale still available
      if (key == KEY_b)  { pushUndo(); obj.angle += radians(5); return; }
      if (key == KEY_B) { pushUndo(); obj.angle -= radians(5); return; }
      if (key == KEY_a){ pushUndo(); obj.size += 0.05; return; }
      if (key == KEY_A){ pushUndo(); obj.size = max(0.05, obj.size - 0.05); return; }
      
      
      if (key == KEY_d){ mode = MODE_SELECT_OBJ; selectedObjIndex = 0; println("Entering MODE_SELECT_OBJ"); }
      

      // OK confirms location and returns to image picker
      if (okKey) { mode = MODE_PICK_IMG; return; }
      break;
    }
  }
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
    img = loadImage(fileName);
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
// Thumbnail Helpers (from Codice 2)
// -------------------------
int thumbCount = 5; // must be odd
float thumbSize = 50;
float selectedThumbSize = 70;
float thumbSpacing = 60;
float bannerHeight = 100;
int infoBarHeight = 40;

void drawThumbnailBanner() {
  rectMode(CORNER);
  float y0 = height - bannerHeight;

  // Opaque base to prevent flicker
  noStroke();
  fill(0);
  rect(0, y0, width, bannerHeight);

  if (mode == MODE_PICK_BG) {
    inPicker=true;
    drawBgPicker(y0);
  } else if (mode == MODE_PICK_CAT) {
    inPicker=true;
    drawCatalogPicker(y0);
  } else { // MODE_PICK_IMG or MODE_MOVE_OBJ show image picker
    drawImagePicker(y0);
    inPicker=false;
  }
}

void drawBgPicker(float y0) {
  if (bgFilenames.size() == 0) { drawBannerText("No backgrounds in library/background/"); return; }

  int half = thumbCount / 2;
  imageMode(CENTER);
  for (int i = 0; i < thumbCount; i++) {
    int offset = i - half;
    int idx = (currentBgIndex + offset + bgFilenames.size()) % bgFilenames.size();
    String rel = bgFilenames.get(idx);
    PImage im = bgThumbs.get(rel);
    float w = (i == half) ? selectedThumbSize : thumbSize;
    float h = (i == half) ? selectedThumbSize : thumbSize;
    float x = width / 2 - (half * thumbSpacing) + i * thumbSpacing;
    float y = y0 + bannerHeight / 2;
    if (im != null) image(im, x, y, w, h);
    if (i == half) drawThumbHighlight(x, y, w, h);
  }
  drawBannerText("Choose BACKGROUND  •  ←/→ to pick, Enter to OK");
}

void drawCatalogPicker(float y0) {
  int n = CATALOGS.length;
  if (n == 0) { drawBannerText("No catalogs"); return; }

  float pillW = 150;
  float pillH = 44;

  // dynamic spacing across width
  float minSpacing = pillW + 20;                 // gap so they don't touch
  float spacing = max(minSpacing, width / float(n + 1));
  float startX = spacing;

  float y = y0 + bannerHeight / 2;
  rectMode(CENTER);
  textAlign(CENTER, CENTER);
  textSize(14);

  for (int i = 0; i < n; i++) {
    float x = startX + i * spacing;
    boolean sel = (i == currentCatIndex);

    // Orange pill
    noStroke();
    if (sel) fill(255, 165, 70);
    else     fill(255, 140, 0);
    rect(x, y, pillW, pillH, 12);

    // selected outline
    if (sel) { noFill(); stroke(255); strokeWeight(2); rect(x, y, pillW, pillH, 12); noStroke(); }

    // label
    fill(0);
    text(CATALOGS[i], x, y);
  }

  drawBannerText("Choose CATALOG  •  ←/→ to pick, Enter to SELECT");
}

void drawLayerBanner() {
  int bannerX = 25;
  int bannerY = 100;
  int spacing = 60;

  int n = objects.size();
  for (int i = 0; i < n; i++) {
    // Draw newest first
    DrawingObject obj = objects.get(n - 1 - i);
    PImage thumb = (obj.gif != null) ? obj.gif.get() : obj.img;

    if (thumb != null) {
      PImage resized = thumb.copy();
      resized.resize(50, 50);
      image(resized, bannerX, bannerY + i * spacing);
    }

    // Highlight selected object in MODE_SELECT_OBJ
    if (mode == MODE_SELECT_OBJ && selectedObjIndex == n - 1 - i) {
      noFill();
      stroke(255, 0, 0);
      strokeWeight(2);
      rectMode(CENTER);
      rect(bannerX, bannerY + i * spacing, 54, 54); // slightly bigger
      noStroke();
    }
  }
}



void drawImagePicker(float y0) {
  String cat = CATALOGS[currentCatIndex];
  ArrayList<String> list = catFiles.get(cat);
  if (list == null || list.size() == 0) { drawBannerText("No images in library/" + cat + "/"); return; }

  int half = thumbCount / 2;
  imageMode(CENTER);
  for (int i = 0; i < thumbCount; i++) {
    int offset = i - half;
    int idx = (currentImgIndex + offset + list.size()) % list.size();
    String rel = list.get(idx);
    PImage im = imgLibrary.get(rel);
    float w = (i == half) ? selectedThumbSize : thumbSize;
    float h = (i == half) ? selectedThumbSize : thumbSize;
    float x = width / 2 - (half * thumbSpacing) + i * thumbSpacing;
    float y = y0 + bannerHeight / 2;
    if (im != null) image(im, x, y, w, h);
    if (i == half) drawThumbHighlight(x, y, w, h);
  }
  String hint = (mode == MODE_MOVE_OBJ)
    ? "Move ←/→/↑/↓ • Rotate q/e • Scale z/x • Enter OK • s = Menu"
    : "Choose IMAGE  •   ←/→ to pick, OK to SELECT, ↑ to catalogs";
  drawBannerText(hint);
}

void drawThumbHighlight(float x, float y, float w, float h) {
  noFill(); stroke(255, 0, 0); strokeWeight(2);
  rectMode(CENTER);
  rect(x, y, w + 4, h + 4);
  noStroke();
}

void drawBannerText(String s) {
  float infoY0 = height - bannerHeight - infoBarHeight;
  rectMode(CORNER);
  noStroke();
  fill(128, 0, 180);
  rect(0, infoY0, width, infoBarHeight);

  fill(255);
  textSize(12);

  // Left status
  textAlign(LEFT, CENTER);
  String status = "";
  if (mode == MODE_PICK_BG)        status = "Mode: BACKGROUND";
  else if (mode == MODE_PICK_CAT)  status = "Mode: CATALOG";
  else if (mode == MODE_PICK_IMG)  status = "Mode: IMAGE (" + CATALOGS[currentCatIndex] + ")";
  else if (mode == MODE_MOVE_OBJ)  status = "Mode: MOVE (" + (selectedObjIndex >= 0 ? objects.get(selectedObjIndex).name : "none") + ")";
  text(status, 10, infoY0 + infoBarHeight/2);

  textAlign(CENTER, CENTER);
  text(s, width/2, infoY0 + infoBarHeight/2);

  if (mode == MODE_MOVE_OBJ && selectedObjIndex >= 0) {
    DrawingObject o = objects.get(selectedObjIndex);
    String pos = "x=" + int(o.x) + " y=" + int(o.y) + " size=" + nf(o.size,1,2) + " rot=" + int(degrees(o.angle)) + "°";
    textAlign(RIGHT, CENTER);
    text(pos, width - 10, infoY0 + infoBarHeight/2);
  }
}



void drawBackgroundGif() {
  imageMode(CORNER);
  rectMode(CORNER);

  int uiTopY = height - int(bannerHeight + infoBarHeight);
  int leftX  = marginLeft;
  int topY   = marginTop;

  int availW = width  - marginLeft - marginRight;
  int availH = uiTopY - marginTop - marginBottom;

  // default to the full "background window" area
  bgDrawX = leftX;
  bgDrawY = topY;
  bgDrawW = availW;
  bgDrawH = availH;

  noStroke();
  fill(0);
  rect(leftX, topY, availW, availH);

  int srcW = (bgGif != null) ? bgGif.width  : (bgStill != null ? bgStill.width  : availW);
  int srcH = (bgGif != null) ? bgGif.height : (bgStill != null ? bgStill.height : availH);

  float sx = availW / (float) srcW;
  float sy = availH / (float) srcH;
  float s  = bgCover ? max(sx, sy) : min(sx, sy);

  float tw = srcW * s;
  float th = srcH * s;
  float ox = leftX + (availW - tw) * 0.5f;
  float oy = topY  + (availH - th) * 0.5f;

  int xi = Math.round(ox);
  int yi = Math.round(oy);
  int wi = Math.round(tw);
  int hi = Math.round(th);

  // clamp to stay above purple bar
  if (yi + hi > uiTopY) hi = uiTopY - yi;
  if (hi < 0) hi = 0;

  if (bgGif != null) image(bgGif, xi, yi, wi, hi);
  else if (bgStill != null) image(bgStill, xi, yi, wi, hi);

  // record the exact drawn rect so UI bars can match it
  bgDrawX = xi; bgDrawY = yi; bgDrawW = wi; bgDrawH = hi;

  fill(0);
  rect(0, uiTopY - 2, width, 2);
}

String makeUniqueName(String rel) {
  String base = rel.substring(rel.lastIndexOf('/') + 1);
  int dot = base.lastIndexOf('.');
  if (dot >= 0) base = base.substring(0, dot);
  int count = 1;
  String name = base + count;
  boolean exists = true;
  while (exists) {
    exists = false;
    for (DrawingObject o : objects) {
      if (o.name.equals(name)) { exists = true; count++; name = base + count; break; }
    }
  }
  return name;
}

void scrollThumbnailLeft() {
  currentImgIndex = (currentImgIndex - 1 + imgFilenames.size()) % imgFilenames.size();
}

void scrollThumbnailRight() {
  currentImgIndex = (currentImgIndex + 1) % imgFilenames.size();
}

// ------------------------------------------------------------------
// NOTE: This file assumes the presence of the auxiliary files used
// by the original sketches, e.g. SaveMenu.pde (for menuX/menuW/menuH and
// handleMenuClick / handleMenuKey / showSaveLoadMenu) and DrawingObject.pde.
// Those definitions were present in your original project; this merge
// retains and integrates the serial handling into the UI flow.
// ------------------------------------------------------------------
