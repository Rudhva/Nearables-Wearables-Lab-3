import java.io.File;
import java.util.*;
import gifAnimation.*;
import processing.serial.*;   // ok to keep even if serial is in serial.pde

// ==== HAND OVERLAY (top UI bar) ====
int historyBarWidth   = 120;  // width reserved for the left history/thumb column
int handPadding       = 10;   // padding around the hand UI box
int handMaxWidthPx    = 520;  // hard cap for hand UI width
float handWidthFrac   = 0.42; // ~40% of available width feels good
int handRectX=0, handRectY=0, handRectW=0, handRectH=0;
int reservedTopH = 0;

PImage HAND_UI;
int handBarHeight = 160;        // visible bar height; tweak 140–200 as you like

class Spot {
  String id;         // "W","A","S","D","OK","FN","UP","DOWN","LEFT","RIGHT"
  float cx, cy;      // center (0..1) relative to the overlay image
  float nw, nh;      // size as a fraction of overlay *height*
  Spot(String id, float cx, float cy, float nw, float nh) {
    this.id=id; this.cx=cx; this.cy=cy; this.nw=nw; this.nh=nh;
  }
}

Spot[] spots = new Spot[] {
  // --- Left cluster: arrows + OK
  new Spot("LEFT", 0.028f, 0.52f, 0.15f, 0.15f),
  new Spot("OK", 0.1f, 0.52f, 0.15f, 0.15f),
  new Spot("RIGHT", 0.155f, 0.52f, 0.15f, 0.15f),
  new Spot("UP", 0.096f, 0.20f, 0.15f, 0.15f),
  new Spot("DOWN", 0.096f, 0.80f, 0.15f, 0.15f),

  // Fn (bottom-left area)
  new Spot("FN", 0.235f, 0.80f, 0.15f, 0.15f),

  // --- Right cluster: I J K L editing
  new Spot("I", 0.385f, 0.20f, 0.15f, 0.15f),
  new Spot("J", 0.345f, 0.49f, 0.15f, 0.15f),
  new Spot("L", 0.455f, 0.49f, 0.15f, 0.15f),
  new Spot("K", 0.385f, 0.80f, 0.15f, 0.15f),
};

// Active highlights (fade automatically)
HashMap<String, Integer> spotActive = new HashMap<String, Integer>();
int spotFlashFrames = 14;  // ~0.23 sec @60fps

// --- Hand UI helpers (keep aspect, no overlap) ---
int currHandH = 0;  // computed each frame from window width
int handTopPadding = 0; // keep 0 unless you want a gap at the very top

int handBarHeightForWidth(int w) {
  if (HAND_UI == null || HAND_UI.width == 0) return 0;
  return int(round(w * (HAND_UI.height / (float)HAND_UI.width))); // keep aspect
}

// --- MODES ---
final int MODE_PICK_BG  = 0;
final int MODE_PICK_CAT = 1;
final int MODE_PICK_IMG = 2;
final int MODE_MOVE_OBJ = 3;
final int MODE_SELECT_OBJ = 4;
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
    if (!dir.exists()) {
      catFiles.put(cat, list);
      continue;
    }
    File[] files = dir.listFiles();
    if (files == null) {
      catFiles.put(cat, list);
      continue;
    }
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
    } else {
      bgStill = loadImage(rel);
    }

    int bw = (bgGif != null) ? bgGif.width : (bgStill != null ? bgStill.width : width);
    int bh = (bgGif != null) ? bgGif.height : (bgStill != null ? bgStill.height : height);

    int newW = bw + marginLeft + marginRight;
    currHandH = handBarHeightForWidth(newW); // keep updated

    surface.setResizable(true);
    surface.setSize(
      newW,
      bh + marginTop + marginBottom + infoBarHeight + int(bannerHeight)
    );
  }
  catch (Exception e) {
    println("Failed to set background: " + rel);
  }
}

// --- Objects / images library ---
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
char KEY_a  = 'i'; // scale up
char KEY_A  = 'I'; // scale down
char KEY_b  = 'l'; // rotate CW
char KEY_B  = 'L'; // rotate CCW
char KEY_c  = 'k'; // undo
char KEY_C  = 'K'; // redo
char KEY_d  = 'j'; // select mode
char KEY_D  = 'J'; // show Save Menu

Gif bgGif = null;
String bgGifName = "HW_BG.gif";
boolean bgCover = false;

// -------------------------
// setup()
// -------------------------
void setup() {
  size(800, 600);

  cleanImages();               // safe no-op if ImageMagick missing
  HAND_UI = loadImage("ui_hand.png");  // data/ui_hand.png
  setupSerial();

  // Load any loose images in data/library/ (legacy behavior)
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
        PImage img = loadImage("library/" + fname);
        if (img != null) {
          imgLibrary.put("library/" + fname, img);
          imgLibrary.put(fname, img);
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

  // Scan folders
  scanBackgrounds();
  scanCatalogs();

  // Start flow
  mode = MODE_PICK_BG;
  currentBgIndex  = 0;
  currentCatIndex = 0;
  currentImgIndex = 0;

  objects = new ArrayList<DrawingObject>();
}

// -------------------------
// draw()
// -------------------------
void draw() {
  background(0);

  // Hand overlay layout first
  computeHandLayout();

  // Background (draws below hand UI)
  if (bgGif != null || bgStill != null) drawBackgroundGif();
  else background(200);

  // Scene content
  for (int i = 0; i < objects.size(); i++) {
    DrawingObject obj = objects.get(i);
    obj.draw();
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

  // UI banners
  drawLayerBanner();
  drawThumbnailBanner();

  // Menu (from SaveMenu.pde)
  menuX = (width - menuW) / 2;
  menuY = (height - menuH) / 2;
  if (showMenu) showSaveLoadMenu();

  // Hand UI (topmost)
  drawHandOverlay();
}

// -------------------------
// cleanImages() (kept here so working.pde compiles standalone)
// -------------------------
void cleanImages() {
  String folderPath = sketchPath("data/library");
  String[] cmd = { "/bin/bash", "-c", "magick mogrify -transparent white '" + folderPath + "/*.png'" };
  try {
    println("Running ImageMagick command...");
    Process process = Runtime.getRuntime().exec(cmd);
    process.waitFor();
    println("PNGs processed in-place in 'data/library'.");
  } catch (Exception e) {
    // ok to ignore if ImageMagick not installed
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
// Place / Delete
// -------------------------
boolean placingTrack = false;

void placeTrackAtCursor() {
  String rel = null;
  ArrayList<String> list = catFiles.get(CATALOGS[currentCatIndex]);
  if (list != null && list.size() > 0) rel = list.get(currentImgIndex % list.size());
  else if (imgFilenames.size() > 0)    rel = "library/" + imgFilenames.get(currentImgIndex % imgFilenames.size());
  if (rel == null) return;

  PImage img = imgLibrary.get(rel);
  if (img == null) { img = loadImage(rel); if (img != null) imgLibrary.put(rel, img); }
  if (img == null) return;

  pushUndo();

  int count = 1;
  String baseName = rel.substring(rel.lastIndexOf('/') + 1);
  int dot = baseName.lastIndexOf('.');
  if (dot >= 0) baseName = baseName.substring(0, dot);
  String name = baseName + count;

  boolean exists = true;
  while (exists) {
    exists = false;
    for (DrawingObject o : objects) {
      if (o.name.equals(name)) { exists = true; count++; name = baseName + count; break; }
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
    if (objects.isEmpty()) selectedObjIndex = -1;
    else if (selectedObjIndex >= objects.size()) selectedObjIndex = objects.size() - 1;
  }
}

// -------------------------
// Keyboard Input
// -------------------------
void keyPressed() {
  // Hand-bar highlights
  if (key == 'i' || key == 'I') markPressed("I");
  if (key == 'j' || key == 'J') markPressed("J");
  if (key == 'k' || key == 'K') markPressed("K");
  if (key == 'l' || key == 'L') markPressed("L");
  if (key == ENTER || key == RETURN) markPressed("OK");
  if (keyCode == UP)    markPressed("UP");
  if (keyCode == DOWN)  markPressed("DOWN");
  if (keyCode == LEFT)  markPressed("LEFT");
  if (keyCode == RIGHT) markPressed("RIGHT");

  // Menu (from SaveMenu.pde)
  if (key == KEY_D) {
    showMenu = true;
    typingFilename = false;
    menuX = (width - menuW) / 2;
    menuY = (height - menuH) / 2;
  }
  handleMenuKey(key, " ");
  if (showMenu) return;

  boolean navLeft  = (keyCode == LEFT );
  boolean navRight = (keyCode == RIGHT );
  boolean okKey    = (key == ENTER || key == RETURN);

  // Undo/Redo in any mode
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
      if (selectedObjIndex < 0) selectedObjIndex = 0;

      if (keyCode == UP)   { selectedObjIndex = (selectedObjIndex + 1) % objects.size(); return; }
      if (keyCode == DOWN) { selectedObjIndex = (selectedObjIndex - 1 + objects.size()) % objects.size(); return; }

      if (okKey) { mode = MODE_MOVE_OBJ; return; }
      break;
    }

    case MODE_PICK_BG: {
      if (bgFilenames.size() == 0) return;
      if (navLeft)  { currentBgIndex = (currentBgIndex - 1 + bgFilenames.size()) % bgFilenames.size(); return; }
      if (navRight) { currentBgIndex = (currentBgIndex + 1) % bgFilenames.size(); return; }
      if (okKey)    { setBackgroundFromPath(bgFilenames.get(currentBgIndex)); mode = MODE_PICK_CAT; return; }
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
        String rel = list.get(currentImgIndex);
        PImage im = imgLibrary.get(rel);
        if (im == null) im = loadImage(rel);

        float cx = marginLeft + (width - marginLeft - marginRight) / 2.0;
        float cy = marginTop  + (height - bannerHeight - marginTop - marginBottom) / 2.0;

        pushUndo();
        String name = makeUniqueName(rel);
        objects.add(new DrawingObject(this, im, cx, cy, 1.0, 0, rel, name));
        selectedObjIndex = objects.size() - 1;
        mode = MODE_MOVE_OBJ;
        return;
      }
      break;
    }

    case MODE_MOVE_OBJ: {
      if (selectedObjIndex < 0 || selectedObjIndex >= objects.size()) { mode = MODE_PICK_IMG; return; }
      DrawingObject obj = objects.get(selectedObjIndex);

      // Move with ARROWS
      if (keyCode == LEFT)  { pushUndo(); obj.x -= 10; return; }
      if (keyCode == RIGHT) { pushUndo(); obj.x += 10; return; }
      if (keyCode == UP)    { pushUndo(); obj.y -= 10; return; }
      if (keyCode == DOWN)  { pushUndo(); obj.y += 10; return; }

      // IJKL edits
      if (key == KEY_b) { pushUndo(); obj.angle += radians(5); return; }  // l (CW)
      if (key == KEY_B) { pushUndo(); obj.angle -= radians(5); return; }  // L (CCW)
      if (key == KEY_a) { pushUndo(); obj.size  += 0.05; return; }        // i (bigger)
      if (key == KEY_A) { pushUndo(); obj.size  = max(0.05, obj.size - 0.05); return; } // I (smaller)

      if (key == KEY_d) {                  // j -> select object mode
        mode = MODE_SELECT_OBJ;
        selectedObjIndex = 0;
        println("Entering MODE_SELECT_OBJ");
      }

      if (okKey) {                         // Enter -> back to picker
        mode = MODE_PICK_IMG;
        return;
      }
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
    img = loadImage(fileName);  // try to load on-demand from library/
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
int infoBarHeight = 40;

void drawThumbnailBanner() {
  rectMode(CORNER);
  float y0 = height - bannerHeight;

  // fill first
  noStroke();
  fill(0);
  rect(0, y0, width, bannerHeight);

  // yellow frame
  noFill();
  stroke(255, 255, 0);
  strokeWeight(2);
  rect(1, y0 + 1, width - 2, bannerHeight - 2);

  if (mode == MODE_PICK_BG) {
    inPicker = true;
    drawBgPicker(y0);
  } else if (mode == MODE_PICK_CAT) {
    inPicker = true;
    drawCatalogPicker(y0);
  } else if (mode == MODE_SELECT_OBJ) {
    drawImagePicker(y0);
    inPicker = false;
    drawBannerText("Select OBJECT  •  ↑/↓ to cycle  •  Enter to confirm  •  J = Menu  •  Undo k  •  Redo K");
  } else { // MODE_PICK_IMG or MODE_MOVE_OBJ
    drawImagePicker(y0);
    inPicker = false;
  }
}

void drawBgPicker(float y0) {
  if (bgFilenames.size() == 0) {
    drawBannerText("No backgrounds in library/background/");
    return;
  }

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
  drawBannerText("Choose BACKGROUND  •  ←/→ to pick  •  Enter to OK  •  J = Menu  •  Undo k  •  Redo K");
}

void drawCatalogPicker(float y0) {
  int n = CATALOGS.length;
  if (n == 0) {
    drawBannerText("No catalogs");
    return;
  }

  float pillW = 150;
  float pillH = 44;

  float minSpacing = pillW + 20;
  float spacing = max(minSpacing, width / float(n + 1));
  float startX = spacing;

  float y = y0 + bannerHeight / 2;
  rectMode(CENTER);
  textAlign(CENTER, CENTER);
  textSize(14);

  for (int i = 0; i < n; i++) {
    float x = startX + i * spacing;
    boolean sel = (i == currentCatIndex);

    noStroke();
    if (sel) fill(255, 165, 70);
    else     fill(255, 140, 0);
    rect(x, y, pillW, pillH, 12);

    if (sel) {
      noFill();
      stroke(255);
      strokeWeight(2);
      rect(x, y, pillW, pillH, 12);
      noStroke();
    }

    fill(0);
    text(CATALOGS[i], x, y);
  }

  drawBannerText("Choose CATALOG  •  ←/→ to pick  •  Enter to SELECT  •  J = Menu  •  Undo k  •  Redo K");
}

void drawLayerBanner() {
  // panel area
  int panelX = 0;
  int panelY = handTopPadding;
  int panelW = historyBarWidth;
  int panelH = height - int(bannerHeight + infoBarHeight) - panelY;

  // background
  noStroke();
  fill(0, 140);
  rectMode(CORNER);
  rect(panelX, panelY, panelW, panelH);

  // yellow frame
  noFill();
  stroke(255, 255, 0);
  strokeWeight(2);
  rect(panelX + 1, panelY + 1, panelW - 2, panelH - 2);

  // --- title + usage hint ---
  fill(255);
  textAlign(CENTER, TOP);
  textSize(14);
  text("HISTORY", panelX + panelW/2, panelY + 6);

  textSize(11);
  textAlign(CENTER, TOP);
  int hintY = panelY + 24;
  text("j select", panelX + panelW/2, hintY);
  text("↑/↓ cycle • Enter edit", panelX + panelW/2, hintY + 14);

  // --- centered column of thumbnails ---
  int n = objects.size();
  if (n == 0) return;

  int spacing = 60;
  int thumbWH = 50;
  int colCX   = panelX + panelW / 2;

  int bgCenterY = bgDrawY + bgDrawH / 2;
  int firstCenterY = bgCenterY - ((n - 1) * spacing) / 2;

  int minCenter = panelY + 25 + 40;
  int maxCenter = panelY + panelH - 25;
  int lastCenterY = firstCenterY + (n - 1) * spacing;

  int shift = 0;
  if (firstCenterY < minCenter) shift = minCenter - firstCenterY;
  else if (lastCenterY > maxCenter) shift = maxCenter - lastCenterY;

  imageMode(CENTER);

  for (int i = 0; i < n; i++) {
    DrawingObject obj = objects.get(n - 1 - i); // newest first
    PImage thumb = (obj.gif != null) ? obj.gif.get() : obj.img;

    int cy = firstCenterY + shift + i * spacing;

    if (thumb != null) {
      PImage resized = thumb.copy();
      resized.resize(thumbWH, thumbWH);
      image(resized, colCX, cy);
    }

    if (mode == MODE_SELECT_OBJ && selectedObjIndex == n - 1 - i) {
      noFill();
      stroke(255, 0, 0);
      strokeWeight(2);
      rectMode(CENTER);
      rect(colCX, cy, thumbWH + 4, thumbWH + 4);
      noStroke();
    }
  }

  imageMode(CORNER);
}

void drawHandOverlay() {
  if (HAND_UI == null) { currHandH = 0; return; }

  int handX = handRectX;
  int handY = handRectY;
  int targetW = handRectW;
  int targetH = handRectH;

  imageMode(CORNER);
  image(HAND_UI, handX, handY, targetW, targetH);

  // yellow frame
  noFill();
  stroke(255, 255, 0);
  strokeWeight(2);
  rectMode(CORNER);
  rect(handX - 1, handY - 1, targetW + 2, targetH + 2);

  // highlights
  rectMode(CENTER);
  noStroke();
  for (Spot s : spots) {
    Integer until = spotActive.get(s.id);
    if (until != null && frameCount <= until) {
      float cx = handX + s.cx * targetW;
      float cy = handY + s.cy * targetH;
      float w  = s.nw * targetH;
      float h  = s.nh * targetH;

      fill(255, 255, 0, 110);
      rect(cx, cy, w, h, 8);
      noFill();
      stroke(255);
      strokeWeight(2);
      rect(cx, cy, w+4, h+4, 8);
      noStroke();
    }
  }
}

void computeHandLayout() {
  if (HAND_UI == null) { 
    handRectW = handRectH = reservedTopH = 0; 
    return; 
  }

  // Background horizontal region (to the right of the history bar)
  int bgLeftX  = historyBarWidth + marginLeft;
  int bgAvailW = width - marginLeft - marginRight - historyBarWidth;
  int bgCenterX = bgLeftX + bgAvailW / 2;

  // Hand size based on background width
  int targetW = min(int(bgAvailW * handWidthFrac), handMaxWidthPx);
  targetW = max(180, targetW);
  int targetH = int(targetW * (HAND_UI.height / (float)HAND_UI.width));

  // Place hand UI horizontally centered to background midline
  int handX = bgCenterX - targetW / 2;
  handX = max(bgLeftX, min(handX, bgLeftX + bgAvailW - targetW));

  int handY = marginTop;                   // at the top strip
  reservedTopH = targetH + handPadding * 2;

  handRectX = handX; 
  handRectY = handY; 
  handRectW = targetW; 
  handRectH = targetH;
  currHandH = targetH;
}

// helper to trigger a flash
void markPressed(String id) {
  spotActive.put(id, frameCount + spotFlashFrames);
}

void drawImagePicker(float y0) {
  String cat = CATALOGS[currentCatIndex];
  ArrayList<String> list = catFiles.get(cat);
  if (list == null || list.size() == 0) {
    drawBannerText("No images in library/" + cat + "/");
    return;
  }

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
    ? "Move ←/→/↑/↓  •  Rotate l/L  •  Scale i/I  •  Undo k  •  Redo K  •  Enter OK  •  J = Menu  •  j = Select Object"
    : "Choose IMAGE  •  ←/→ to pick  •  Enter to SELECT  •  ↑ back to catalogs  •  J = Menu  •  Undo k  •  Redo K";
  drawBannerText(hint);
}

void drawThumbHighlight(float x, float y, float w, float h) {
  noFill();
  stroke(255, 0, 0);
  strokeWeight(2);
  rectMode(CENTER);
  rect(x, y, w + 4, h + 4);
  noStroke();
}

void drawBannerText(String s) {
  float infoY0 = height - bannerHeight - infoBarHeight;
  rectMode(CORNER);

  // bar fill
  noStroke();
  fill(128, 0, 180);
  rect(0, infoY0, width, infoBarHeight);

  // yellow frame
  noFill();
  stroke(255, 255, 0);
  strokeWeight(2);
  rect(1, infoY0 + 1, width - 2, infoBarHeight - 2);

  // text
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

  // Center hint
  textAlign(CENTER, CENTER);
  text(s, width/2, infoY0 + infoBarHeight/2);

  // Right position readout
  if (mode == MODE_MOVE_OBJ && selectedObjIndex >= 0) {
    DrawingObject o = objects.get(selectedObjIndex);
    String pos = "x=" + int(o.x) + " y=" + int(o.y) + " size=" + nf(o.size, 1, 2) + " rot=" + int(degrees(o.angle)) + "°";
    textAlign(RIGHT, CENTER);
    text(pos, width - 10, infoY0 + infoBarHeight/2);
  }
}

void drawBackgroundGif() {
  imageMode(CORNER);
  rectMode(CORNER);

  int uiTopY = height - int(bannerHeight + infoBarHeight);
  int leftX  = historyBarWidth + marginLeft;                 // right of history bar
  int topY   = marginTop + reservedTopH;                     // BELOW the hand UI

  int availW = width  - marginLeft - marginRight - historyBarWidth; // right area only
  int availH = uiTopY - topY - marginBottom;

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

  if (yi + hi > uiTopY) hi = uiTopY - yi;
  if (hi < 0) hi = 0;

  if (bgGif != null) image(bgGif, xi, yi, wi, hi);
  else if (bgStill != null) image(bgStill, xi, yi, wi, hi);

  // record exact drawn rect
  bgDrawX = xi;
  bgDrawY = yi;
  bgDrawW = wi;
  bgDrawH = hi;

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
      if (o.name.equals(name)) {
        exists = true;
        count++;
        name = base + count;
        break;
      }
    }
  }
  return name;
}

void scrollThumbnailLeft()  { currentImgIndex = (currentImgIndex - 1 + imgFilenames.size()) % imgFilenames.size(); }
void scrollThumbnailRight() { currentImgIndex = (currentImgIndex + 1) % imgFilenames.size(); }


// ------------------------------------------------------------------
// NOTE: This file assumes the presence of the auxiliary files used
// by the original sketches, e.g. SaveMenu.pde (for menuX/menuW/menuH and
// handleMenuClick / handleMenuKey / showSaveLoadMenu) and DrawingObject.pde.
// Those definitions were present in your original project; this merge
// retains and integrates the serial handling into the UI flow.
// ------------------------------------------------------------------
